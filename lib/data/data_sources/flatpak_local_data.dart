import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:flatpak_dart/flatpak_dart.dart';

import '../../helpers/errors_exception.dart';
import '../appstream/appstream_catalog_service.dart';
import '../models/application_model.dart';
import '../models/installation_model.dart';
import '../models/remote_model.dart';
import 'flatpak_event_data.dart';

/// Holds the two `flatpak_dart` clients the app needs: a user-scoped one
/// (used for essentially everything - installs, launches, browsing) and a
/// system-scoped one (used only to surface the system installation's
/// remotes in the system-info screen, mirroring what the old
/// `getSystemInstallations()` pigeon call exposed).
class FlatpakClients {
  final FlatpakClient user;
  final FlatpakClient system;

  FlatpakClients({required this.user, required this.system});

  factory FlatpakClients.create() =>
      FlatpakClients(user: FlatpakClient.user(), system: FlatpakClient.system());

  Future<void> closeAll() async {
    await user.close();
    await system.close();
  }
}

abstract class FlatpakLocalDataSource {
  Future<String> getVersion();
  Future<String> getDefaultArch();
  Future<List<String>> getSupportedArches();
  Future<List<InstallationModel>> getSystemInstallations();
  Future<InstallationModel> getUserInstallation();
  Future<bool> remoteAdd(RemoteModel remote);
  Future<bool> remoteRemove(String id);
  Future<List<ApplicationModel>> getApplicationsInstalled();
  Future<List<ApplicationModel>> getApplicationsUpdate();
  Future<List<ApplicationModel>> getApplicationsRemote(String remoteId);
  Future<bool> applicationInstall(String id);
  Future<bool> applicationUninstall(String id);
  Future<bool> applicationUpdate(String id);
  Future<bool> applicationStart(String id);
  Future<bool> applicationStop(String id);
  Future<void> setupEventChannel(String id);
}

class FlatpakLocalDataSourceImpl implements FlatpakLocalDataSource {
  final FlatpakClients _clients;
  final FlatpakEventDataSource _eventDataSource;
  final AppstreamCatalogService _appstream;

  FlatpakLocalDataSourceImpl(
    this._clients,
    this._eventDataSource, {
    AppstreamCatalogService? appstream,
  }) : _appstream = appstream ?? AppstreamCatalogService.instance;

  FlatpakClient get _client => _clients.user;

  // ── System info ─────────────────────────────────────────────────────
  //
  // flatpak_dart has no equivalent of `flatpak --version` / the default
  // and supported architecture lists the old pigeon plugin exposed - it's
  // a pure libflatpak FFI bridge with no CLI-info surface. Best-effort
  // fallbacks are used below and documented at each call site; see the
  // migration report for the full gap list.

  @override
  Future<String> getVersion() async {
    // Gap: flatpak_dart doesn't expose libflatpak's version string.
    return '';
  }

  @override
  Future<String> getDefaultArch() async {
    return _hostArch();
  }

  @override
  Future<List<String>> getSupportedArches() async {
    // Gap: flatpak_dart doesn't expose the multiarch list libflatpak
    // computes (e.g. x86_64 hosts also support i386). Only the host's
    // own arch is returned.
    return [_hostArch()];
  }

  String _hostArch() {
    switch (Abi.current()) {
      case Abi.linuxX64:
        return 'x86_64';
      case Abi.linuxArm64:
        return 'aarch64';
      case Abi.linuxArm:
        return 'arm';
      default:
        return Abi.current().toString();
    }
  }

  @override
  Future<List<InstallationModel>> getSystemInstallations() async {
    try {
      final remotes = await _clients.system.listRemotes();
      return [
        InstallationModel.forScope(
          isUser: false,
          remotes: remotes.map(RemoteModel.fromFlatpakRemote).toList(),
        ),
      ];
    } on FlatpakException catch (e) {
      throw PlatformException(e.message);
    }
  }

  @override
  Future<InstallationModel> getUserInstallation() async {
    try {
      final remotes = await _client.listRemotes();
      return InstallationModel.forScope(
        isUser: true,
        remotes: remotes.map(RemoteModel.fromFlatpakRemote).toList(),
      );
    } on FlatpakException catch (e) {
      throw PlatformException(e.message);
    }
  }

  // ── Remote management ──────────────────────────────────────────────

  @override
  Future<bool> remoteAdd(RemoteModel remote) async {
    try {
      await _client.remotes.add(remote.name, remote.toRemoteConfig());
      _client.dropCaches();
      return true;
    } on FlatpakException catch (e) {
      throw PlatformException(e.message);
    }
  }

  @override
  Future<bool> remoteRemove(String id) async {
    try {
      await _client.remotes.remove(id);
      _client.dropCaches();
      return true;
    } on FlatpakException catch (e) {
      throw PlatformException(e.message);
    }
  }

  // ── Application discovery ──────────────────────────────────────────

  String get _userInstallationBase {
    final home = Platform.environment['HOME'] ?? '.';
    final xdgDataHome = Platform.environment['XDG_DATA_HOME'];
    return xdgDataHome != null
        ? '$xdgDataHome/flatpak'
        : '$home/.local/share/flatpak';
  }

  Future<AppstreamComponentInfo> _lookupAppstream(
    String remote,
    String appId,
  ) {
    if (remote.isEmpty) return Future.value(AppstreamComponentInfo.empty);
    return _appstream.lookup(
      installationBase: _userInstallationBase,
      remote: remote,
      appId: appId,
    );
  }

  @override
  Future<List<ApplicationModel>> getApplicationsInstalled() async {
    try {
      final apps = await _client.listApplications();
      // The appstream lookup for each app is an independent SQLite query
      // against a (per-remote) catalog that's already been parsed and
      // cached by `AppstreamCatalogService` - running them concurrently
      // instead of one-at-a-time avoids paying N sequential await
      // round-trips for what is otherwise embarrassingly parallel work.
      final appstreams = await Future.wait(
        apps.map((app) => _lookupAppstream(app.origin, app.ref.name)),
      );
      return [
        for (var i = 0; i < apps.length; i++)
          ApplicationModel.fromFlatpakApplication(
            apps[i],
            appstream: appstreams[i],
          ),
      ];
    } on FlatpakException catch (e) {
      throw PlatformException(e.message);
    }
  }

  @override
  Future<List<ApplicationModel>> getApplicationsUpdate() async {
    try {
      final refs = await _client.checkForUpdates();
      final infos = await Future.wait(
        refs.map((ref) async {
          try {
            return await _client.info(
              ref.name,
              arch: ref.arch,
              branch: ref.branch,
            );
          } on FlatpakException {
            return null;
          }
        }),
      );

      final appstreams = await Future.wait([
        for (var i = 0; i < refs.length; i++)
          infos[i] != null
              ? _lookupAppstream(infos[i]!.origin, refs[i].name)
              : Future.value(AppstreamComponentInfo.empty),
      ]);

      return [
        for (var i = 0; i < refs.length; i++)
          infos[i] != null
              // Successfully resolved via `info()`: use the richer model.
              ? ApplicationModel.fromFlatpakApplication(
                  infos[i]!,
                  appstream: appstreams[i],
                )
              // Fall back to a minimal entry built straight from the ref
              // if `info()` couldn't resolve it (e.g. transient failure).
              : ApplicationModel.fromRemoteRef(refs[i], origin: ''),
      ];
    } on FlatpakException catch (e) {
      throw PlatformException(e.message);
    }
  }

  @override
  Future<List<ApplicationModel>> getApplicationsRemote(
    String remoteId,
  ) async {
    try {
      final refs = await _client.remotes
          .listApps(remoteId, includeRuntimes: false)
          .toList();
      // Same rationale as `getApplicationsInstalled`: the remote's
      // AppStream catalog is built/cached once (see
      // `AppstreamCatalogService._catalogFor`), so the per-app lookups
      // below are independent queries that can run concurrently instead
      // of serially blocking on each other.
      final appstreams = await Future.wait(
        refs.map((ref) => _lookupAppstream(remoteId, ref.name)),
      );
      return [
        for (var i = 0; i < refs.length; i++)
          ApplicationModel.fromRemoteRef(
            refs[i],
            origin: remoteId,
            appstream: appstreams[i],
          ),
      ];
    } on FlatpakException catch (e) {
      throw PlatformException(e.message);
    }
  }

  // ── Application lifecycle ──────────────────────────────────────────

  /// `flatpak_dart`'s `install()` needs an explicit remote name, but the
  /// repository's `installApplication(appId)` only carries the app ref.
  /// Resolve the remote by checking which configured remote actually
  /// serves this ref, preferring `flathub` since that's the overwhelming
  /// common case for this app. This does mean install can be slow the
  /// first time for apps not on flathub, since it walks remote listings.
  Future<String> _resolveRemoteForInstall(String shortId) async {
    final remotes = await _client.remotes.list();
    final ordered = [
      ...remotes.where((r) => r.name.toLowerCase() == 'flathub'),
      ...remotes.where((r) => r.name.toLowerCase() != 'flathub'),
    ];
    for (final remote in ordered) {
      final found = await _client.remotes
          .listApps(remote.name)
          .any((ref) => ref.name == shortId);
      if (found) return remote.name;
    }
    throw FlatpakNotFoundException(
      'No configured remote serves app "$shortId"',
    );
  }

  String _shortIdOf(String ref) {
    var id = ref;
    if (id.startsWith('app/')) id = id.substring(4);
    return id.split('/').first;
  }

  @override
  Future<bool> applicationInstall(String id) async {
    try {
      final shortId = _shortIdOf(id);
      final remote = await _resolveRemoteForInstall(shortId);
      final tx = _client.install(remote, id);
      _eventDataSource.attachTransaction(shortId, tx, operation: 'install');
      unawaited(tx.result);
      return true;
    } on FlatpakException catch (e) {
      throw PlatformException(e.message);
    }
  }

  @override
  Future<bool> applicationUninstall(String id) async {
    try {
      final shortId = _shortIdOf(id);
      final tx = _client.uninstall(id);
      _eventDataSource.attachTransaction(shortId, tx, operation: 'uninstall');
      unawaited(tx.result);
      return true;
    } on FlatpakException catch (e) {
      throw PlatformException(e.message);
    }
  }

  @override
  Future<bool> applicationUpdate(String id) async {
    try {
      final shortId = _shortIdOf(id);
      final tx = _client.update(ref: id);
      _eventDataSource.attachTransaction(shortId, tx, operation: 'update');
      unawaited(tx.result);
      return true;
    } on FlatpakException catch (e) {
      throw PlatformException(e.message);
    }
  }

  @override
  Future<bool> applicationStart(String id) async {
    // launch()/stop()/listRunning() are the newest, least battle-tested
    // part of flatpak_dart (added on its `launcher` branch) - wrap the
    // call defensively and surface a clear message rather than letting a
    // partially-baked native path crash the app.
    try {
      final shortId = _shortIdOf(id);
      await _client.launch(shortId);
      return true;
    } on FlatpakException catch (e) {
      throw PlatformException('Failed to launch $id: ${e.message}');
    } catch (e) {
      throw PlatformException('Failed to launch $id: $e');
    }
  }

  @override
  Future<bool> applicationStop(String id) async {
    try {
      final shortId = _shortIdOf(id);
      await _client.stop(shortId);
      return true;
    } on FlatpakException catch (e) {
      throw PlatformException('Failed to stop $id: ${e.message}');
    } catch (e) {
      throw PlatformException('Failed to stop $id: $e');
    }
  }

  @override
  Future<void> setupEventChannel(String id) async {
    // No-op: flatpak_dart hands back a live FlatpakTransaction with its
    // own progress stream directly from install/update/uninstall, so
    // there's no separate native-side channel to arm ahead of time.
    // Kept only so InstallationCubit's existing call sequence still
    // compiles unchanged.
  }
}
