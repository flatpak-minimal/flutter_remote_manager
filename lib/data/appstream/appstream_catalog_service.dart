import 'dart:convert';
import 'dart:io';

import 'package:appstream_dart/appstream_dart.dart';
import 'package:flutter/foundation.dart';

/// Display metadata resolved from a remote's AppStream catalog for a
/// single Flatpak app. `flatpak_dart` only exposes the raw ref/ostree
/// metadata (name/summary/icon straight off the flatpak metadata file);
/// everything richer (long description, developer, categories,
/// screenshots, OARS content rating) comes from AppStream, which is why
/// this lookup is a separate step layered on top of `FlatpakClient`.
class AppstreamComponentInfo {
  final String name;
  final String summary;
  final String description;
  final String developer;
  final List<String> categories;
  final String iconUrl;
  final List<String> screenshots;
  final String contentRatingType;
  final Map<String, String> contentRating;

  const AppstreamComponentInfo({
    this.name = '',
    this.summary = '',
    this.description = '',
    this.developer = '',
    this.categories = const [],
    this.iconUrl = '',
    this.screenshots = const [],
    this.contentRatingType = '',
    this.contentRating = const {},
  });

  static const empty = AppstreamComponentInfo();

  bool get isEmpty =>
      name.isEmpty && summary.isEmpty && description.isEmpty;
}

/// Builds (once per remote) and queries a local SQLite catalog of a
/// remote's AppStream metadata using `appstream_dart`, sourced from the
/// AppStream XML that `flatpak` itself already caches on disk for every
/// configured remote (`<installation>/appstream/<remote>/<arch>/...`).
///
/// This exists because `flatpak_dart` (the libflatpak FFI bridge) does not
/// parse AppStream metadata at all - it only surfaces what libflatpak's
/// ref/metadata APIs give it (id, origin, installed size, and the terse
/// `appdata name/summary/icon` fields baked into the flatpak metadata
/// file). Anything richer - long description, developer name, categories,
/// screenshots, OARS content rating - has to come from AppStream directly.
class AppstreamCatalogService {
  AppstreamCatalogService._();

  static final AppstreamCatalogService instance = AppstreamCatalogService._();

  final Map<String, Future<CatalogDatabase?>> _catalogs = {};
  bool _initialized = false;

  void _ensureInitialized() {
    if (_initialized) return;
    try {
      Appstream.initialize();
      _initialized = true;
    } catch (e) {
      debugPrint(
        '[AppstreamCatalogService] Failed to initialize appstream_dart: $e',
      );
    }
  }

  String get _cacheRoot {
    final home = Platform.environment['HOME'] ?? '.';
    return '$home/.cache/agl-store/appstream';
  }

  /// Locate flatpak's own cached AppStream XML for [remote] under
  /// [installationBase] (e.g. `/var/lib/flatpak` for the system
  /// installation, or `$HOME/.local/share/flatpak` for the user one).
  /// Handles both the modern `active/appstream.xml` symlink layout and
  /// the older flat/`*.xml.gz` layouts.
  String? _findRemoteAppstreamXml(String installationBase, String remote) {
    const archCandidates = ['x86_64', 'aarch64'];
    for (final arch in archCandidates) {
      final activeXml = File(
        '$installationBase/appstream/$remote/$arch/active/appstream.xml',
      );
      if (activeXml.existsSync()) return activeXml.path;

      final flatXml = File(
        '$installationBase/appstream/$remote/$arch/appstream.xml',
      );
      if (flatXml.existsSync()) return flatXml.path;

      final gz = File(
        '$installationBase/appstream/$remote/$arch/appstream.xml.gz',
      );
      if (gz.existsSync()) {
        try {
          final decoded = gzip.decode(gz.readAsBytesSync());
          final cacheDir = Directory(_cacheRoot)..createSync(recursive: true);
          final outFile = File('${cacheDir.path}/${remote}_$arch.xml');
          outFile.writeAsBytesSync(decoded);
          return outFile.path;
        } catch (e) {
          debugPrint(
            '[AppstreamCatalogService] Failed to decompress ${gz.path}: $e',
          );
        }
      }
    }
    return null;
  }

  Future<CatalogDatabase?> _catalogFor(
    String installationBase,
    String remote,
  ) {
    final key = '$installationBase::$remote';
    return _catalogs.putIfAbsent(
      key,
      () => _buildCatalog(installationBase, remote),
    );
  }

  Future<CatalogDatabase?> _buildCatalog(
    String installationBase,
    String remote,
  ) async {
    _ensureInitialized();
    if (!_initialized) return null;

    final xmlPath = _findRemoteAppstreamXml(installationBase, remote);
    if (xmlPath == null) {
      debugPrint(
        '[AppstreamCatalogService] No cached AppStream XML found for '
        '"$remote" under $installationBase',
      );
      return null;
    }

    final cacheDir = Directory(_cacheRoot)..createSync(recursive: true);
    final dbPath = '${cacheDir.path}/$remote.db';
    if (!File(dbPath).existsSync()) {
      try {
        await for (final event in Appstream.parseToSqlite(
          xmlPath: xmlPath,
          dbPath: dbPath,
        )) {
          if (event is ParseFailed) {
            debugPrint(
              '[AppstreamCatalogService] Parse failed for "$remote": '
              '${event.message}',
            );
            return null;
          }
        }
      } catch (e) {
        debugPrint(
          '[AppstreamCatalogService] Error parsing AppStream XML for '
          '"$remote": $e',
        );
        return null;
      }
    }

    try {
      return CatalogDatabase.open(dbPath);
    } catch (e) {
      debugPrint(
        '[AppstreamCatalogService] Failed to open catalog for "$remote": $e',
      );
      return null;
    }
  }

  /// Look up display metadata for [appId] within [remote]'s catalog.
  /// Returns [AppstreamComponentInfo.empty] if no catalog could be built
  /// or the component isn't present (never throws).
  Future<AppstreamComponentInfo> lookup({
    required String installationBase,
    required String remote,
    required String appId,
  }) async {
    final db = await _catalogFor(installationBase, remote);
    if (db == null) return AppstreamComponentInfo.empty;

    try {
      var detail = await db.getComponentDetail(appId);
      detail ??= await db.getComponentDetail('$appId.desktop');
      if (detail == null) return AppstreamComponentInfo.empty;

      final component = detail.component;

      final ratingRows = await (db.select(
        db.contentRatingAttrs,
      )..where((r) => r.componentId.equals(component.id))).get();
      final contentRating = {
        for (final row in ratingRows) row.attrId: row.value,
      };

      return AppstreamComponentInfo(
        name: component.name,
        summary: component.summary ?? '',
        description: component.description ?? '',
        developer: component.developerName ?? '',
        categories: detail.categories,
        iconUrl: detail.icons.isNotEmpty ? detail.icons.first.value : '',
        screenshots: detail.screenshotImages.map((s) => s.url).toList(),
        contentRatingType: component.contentRatingType ?? '',
        contentRating: contentRating,
      );
    } catch (e) {
      debugPrint(
        '[AppstreamCatalogService] Lookup failed for "$appId" in '
        '"$remote": $e',
      );
      return AppstreamComponentInfo.empty;
    }
  }
}

/// Small helper so callers can turn [AppstreamComponentInfo] into the
/// legacy JSON-string shape (`appdata`, `metadata`) that
/// [DiscoveryCubit]'s existing `jsonDecode`-based helpers expect, without
/// having to touch that presentation-layer code.
String encodeAppdataJson(AppstreamComponentInfo info) => jsonEncode({
      'description': info.description,
    });

String encodeMetadataJson(AppstreamComponentInfo info) => jsonEncode({
      'developer': info.developer,
      'categories': info.categories,
    });
