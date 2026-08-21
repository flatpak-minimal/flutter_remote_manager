import 'package:equatable/equatable.dart';
import 'package:flatpak_dart/flatpak_dart.dart';

import '../appstream/appstream_catalog_service.dart';

class Application extends Equatable {
  final String name;
  final String id;
  final String summary;
  final String version;
  final String origin;
  final String license;
  final int installedSize;
  final String deployDir;
  final bool isCurrent;
  final String contentRatingType;
  final Map<String, dynamic> contentRating;
  final String latestCommit;
  final String eol;
  final String eolRebase;
  final List<String> subpaths;
  final String metadata;
  final String appdata;

  const Application({
    required this.name,
    required this.id,
    required this.summary,
    required this.version,
    required this.origin,
    required this.license,
    required this.installedSize,
    required this.deployDir,
    required this.isCurrent,
    required this.contentRatingType,
    required this.contentRating,
    required this.latestCommit,
    required this.eol,
    required this.eolRebase,
    required this.subpaths,
    required this.metadata,
    required this.appdata,
  });

  factory Application.empty() {
    return const Application(
      name: '',
      id: '',
      summary: '',
      version: '',
      origin: '',
      license: '',
      installedSize: 0,
      deployDir: '',
      isCurrent: false,
      contentRatingType: '',
      contentRating: {},
      latestCommit: '',
      eol: '',
      eolRebase: '',
      subpaths: [],
      metadata: '',
      appdata: '',
    );
  }

  String get shortId {
    if (id.startsWith('app/')) {
      final parts = id.split('/');
      if (parts.length >= 2) {
        return parts[1];
      }
    }
    return id;
  }

  @override
  List<Object?> get props => [id];
}

class ApplicationModel extends Application {
  const ApplicationModel({
    required super.name,
    required super.id,
    required super.summary,
    required super.version,
    required super.origin,
    required super.license,
    required super.installedSize,
    required super.deployDir,
    required super.isCurrent,
    required super.contentRatingType,
    required super.contentRating,
    required super.latestCommit,
    required super.eol,
    required super.eolRebase,
    required super.subpaths,
    required super.metadata,
    required super.appdata,
  });

  /// Build from a `flatpak_dart` [FlatpakApplication] (installed app or
  /// runtime). `flatpak_dart` only surfaces the terse `appdata` fields
  /// baked into the flatpak metadata file (name/summary/version/icon) -
  /// [appstream] optionally supplements those with the richer AppStream
  /// catalog data (description, developer, categories, content rating)
  /// looked up separately via [AppstreamCatalogService].
  factory ApplicationModel.fromFlatpakApplication(
    FlatpakApplication app, {
    AppstreamComponentInfo? appstream,
  }) {
    final info = appstream ?? AppstreamComponentInfo.empty;
    final ref = app.ref;
    return ApplicationModel(
      name: info.name.isNotEmpty ? info.name : app.appDataName,
      id: 'app/${ref.name}/${ref.arch}/${ref.branch}',
      summary: info.summary.isNotEmpty ? info.summary : app.appDataSummary,
      version: app.appDataVersion,
      origin: app.origin,
      license: '',
      installedSize: app.installedSize,
      deployDir: app.installedPath,
      isCurrent: app.isCurrentArch,
      contentRatingType: info.contentRatingType,
      contentRating: Map<String, dynamic>.from(info.contentRating),
      latestCommit: app.latestCommit,
      eol: app.endOfLife ? 'true' : '',
      eolRebase: app.endOfLifeRebase,
      subpaths: const [],
      metadata: encodeMetadataJson(info),
      appdata: encodeAppdataJson(info),
    );
  }

  /// Build from a `flatpak_dart` [FlatpakRef] as returned when browsing a
  /// remote (`FlatpakRemoteManager.listApps`). Refs carry no appdata at
  /// all, so all display metadata comes from the AppStream [appstream]
  /// lookup when available.
  factory ApplicationModel.fromRemoteRef(
    FlatpakRef ref, {
    required String origin,
    AppstreamComponentInfo? appstream,
  }) {
    final info = appstream ?? AppstreamComponentInfo.empty;
    return ApplicationModel(
      name: info.name.isNotEmpty ? info.name : ref.name,
      id: 'app/${ref.name}/${ref.arch}/${ref.branch}',
      summary: info.summary,
      version: '',
      origin: origin,
      license: '',
      installedSize: 0,
      deployDir: '',
      isCurrent: true,
      contentRatingType: info.contentRatingType,
      contentRating: Map<String, dynamic>.from(info.contentRating),
      latestCommit: ref.commit,
      eol: '',
      eolRebase: '',
      subpaths: const [],
      metadata: encodeMetadataJson(info),
      appdata: encodeAppdataJson(info),
    );
  }
}
