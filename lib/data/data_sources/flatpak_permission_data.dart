import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/flatpak_permission_model.dart';
import '../../core/permissions/permission_types.dart';

/// xdg-desktop-portal permission-request bridge.
///
/// NOTE: interactive Flatpak sandbox permission prompts (camera,
/// microphone, filesystem access, etc.) are driven by the
/// `xdg-desktop-portal` D-Bus interface, not libflatpak. Neither
/// `flatpak_dart` (a libflatpak FFI bridge) nor `appstream_dart` (an
/// AppStream XML/SQLite catalog) talk to that portal, so there is
/// currently no Dart-side replacement for what the old native plugin's
/// MethodChannel/EventChannel pair did here. This class is kept as a
/// no-op stub - it preserves the type/method shape that
/// `FlatpakRepository`, `PermissionListenerBloc`, and the permission
/// dialog widgets are built against, so none of that call graph has to
/// change - but it never emits real portal events and every request
/// resolves as unhandled/false. Wiring a real xdg-desktop-portal client
/// is out of scope for this migration.
class FlatpakPermissionDataSource {
  StreamController<PermissionEventModel>? _permissionStreamController;
  Stream<PermissionEventModel> get permissionStream =>
      _permissionStreamController?.stream ?? const Stream.empty();

  FlatpakPermissionDataSource();

  void startListening() {
    if (_permissionStreamController != null) {
      debugPrint('[FlatpakPermissionData] Already listening');
      return;
    }
    debugPrint(
      '[FlatpakPermissionData] Stub started (no xdg-desktop-portal client '
      'wired up - see class doc comment)',
    );
    _permissionStreamController =
        StreamController<PermissionEventModel>.broadcast();
  }

  void stopListening() {
    _permissionStreamController?.close();
    _permissionStreamController = null;
  }

  Future<void> respondToPermissionRequest({
    required String requestId,
    required FlatpakPermission permission,
    required bool granted,
  }) async {
    debugPrint(
      '[FlatpakPermissionData] respondToPermissionRequest is a no-op stub '
      '(requestId=$requestId, permission=${permission.name}, '
      'granted=$granted)',
    );
  }

  Future<Map<FlatpakPermission, bool>> checkPermissions({
    required String appId,
    required List<FlatpakPermission> permissions,
  }) async {
    debugPrint(
      '[FlatpakPermissionData] checkPermissions is a no-op stub for $appId',
    );
    return {};
  }

  Future<bool> revokePermission({
    required String appId,
    required FlatpakPermission permission,
  }) async {
    debugPrint(
      '[FlatpakPermissionData] revokePermission is a no-op stub '
      '($appId / ${permission.name})',
    );
    return false;
  }

  Future<Map<String, dynamic>?> getSystemStorage() async {
    debugPrint(
      '[FlatpakPermissionData] getSystemStorage is a no-op stub - it used the '
      'removed native MethodChannel and has no libflatpak equivalent',
    );
    return null;
  }

  Future<bool> grantPermission({
    required String appId,
    required FlatpakPermission permission,
  }) async {
    debugPrint(
      '[FlatpakPermissionData] grantPermission is a no-op stub '
      '($appId / ${permission.name})',
    );
    return false;
  }
}
