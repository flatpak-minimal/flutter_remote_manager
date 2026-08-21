import 'dart:async';

import 'package:flatpak_dart/flatpak_dart.dart';
import 'package:flutter/foundation.dart';

import '../models/flatpak_event_model.dart';

/// Per-app-install/-update/-uninstall progress event bus.
///
/// The old native plugin pushed progress over a dynamically-named
/// `EventChannel` per transaction id. `flatpak_dart` instead hands back a
/// [FlatpakTransaction] (with its own `progress` stream and `result`
/// future) directly from `install`/`update`/`uninstall`. To keep the
/// `FlatpakRepository` seam (`startEventListening`/`getTransactionStream`/
/// `stopEventListening`, all keyed by transaction id) unchanged for
/// [InstallationCubit], this class now just owns the broadcast
/// controllers and offers [attachTransaction] for
/// `FlatpakLocalDataSourceImpl` to pipe a live [FlatpakTransaction] into
/// once it starts one.
abstract class FlatpakEventDataSource {
  Stream<FlatpakEventModel> getTransactionStream(String transactionId);
  void startListening(String transactionId);
  void stopListening(String transactionId);

  /// Pipe [transaction]'s progress/result into the broadcast stream for
  /// [transactionId] (which must already have been created via
  /// [startListening]).
  void attachTransaction(
    String transactionId,
    FlatpakTransaction transaction, {
    required String operation,
  });

  void dispose();
}

class FlatpakEventDataSourceImpl implements FlatpakEventDataSource {
  final Map<String, StreamController<FlatpakEventModel>> _controllers = {};
  final Map<String, StreamSubscription> _progressSubscriptions = {};

  // Throttling state for the native progress bridge below - libflatpak's
  // progress callback can fire many times per second (effectively once
  // per chunk of bytes transferred), and forwarding every single tick
  // straight into `InstallationCubit.emit()` (which fans out into
  // `AppStatusCubit` updates and widget rebuilds) would cause far more
  // UI churn than the on-screen percentage ever needs.
  static const _progressThrottle = Duration(milliseconds: 120);
  final Map<String, DateTime> _lastProgressEmit = {};
  final Map<String, int> _lastProgressPercent = {};

  bool _isDisposed = false;

  @override
  Stream<FlatpakEventModel> getTransactionStream(String transactionId) {
    if (_isDisposed) {
      throw StateError('EventDataSource has been disposed');
    }

    return _controllerFor(transactionId).stream;
  }

  StreamController<FlatpakEventModel> _controllerFor(String transactionId) {
    return _controllers.putIfAbsent(
      transactionId,
      () => StreamController<FlatpakEventModel>.broadcast(
        onCancel: () {
          debugPrint(
            '[FlatpakEventDataSource] Stream for $transactionId cancelled',
          );
          stopListening(transactionId);
        },
      ),
    );
  }

  @override
  void startListening(String transactionId) {
    if (_isDisposed) {
      debugPrint('[FlatpakEventDataSource] Cannot start - disposed');
      return;
    }
    debugPrint('[FlatpakEventDataSource] Ready to listen to $transactionId');
    _controllerFor(transactionId);
  }

  @override
  void attachTransaction(
    String transactionId,
    FlatpakTransaction transaction, {
    required String operation,
  }) {
    if (_isDisposed) return;

    final controller = _controllerFor(transactionId);

    final startedType = switch (operation) {
      'install' => FlatpakEventType.installationStarted,
      'update' => FlatpakEventType.updateStarted,
      'uninstall' => FlatpakEventType.uninstallationStarted,
      _ => FlatpakEventType.unknown,
    };
    if (!controller.isClosed) {
      controller.add(FlatpakEventModel(type: startedType));
    }

    _lastProgressEmit.remove(transactionId);
    _lastProgressPercent.remove(transactionId);

    _progressSubscriptions[transactionId]?.cancel();
    _progressSubscriptions[transactionId] = transaction.progress.listen(
      (progress) {
        if (controller.isClosed) return;
        if (!_shouldEmitProgress(transactionId, progress.progressPercent)) {
          return;
        }
        controller.add(
          FlatpakEventModel(
            type: _progressType(operation),
            ref: progress.ref,
            progress: progress.progressPercent / 100.0,
            message: progress.status,
            bytes: progress.bytesTransferred,
            operationType: operation,
          ),
        );
      },
      onError: (Object error) {
        debugPrint(
          '[FlatpakEventDataSource] Progress stream error for '
          '$transactionId: $error',
        );
      },
    );

    transaction.result.then(
      (_) {
        if (controller.isClosed) return;
        controller.add(
          FlatpakEventModel(
            type: _completeType(operation),
            operationType: operation,
            success: true,
          ),
        );
      },
      onError: (Object error) {
        if (controller.isClosed) return;
        controller.add(
          FlatpakEventModel(
            type: _failedType(operation),
            operationType: operation,
            success: false,
            error: error.toString(),
            message: error.toString(),
          ),
        );
      },
    );
  }

  /// Decide whether a progress tick for [transactionId] is worth forwarding:
  /// always let the first event and a changed percentage through, but rate
  /// -limit same-percentage or rapid-fire ticks to at most one every
  /// [_progressThrottle]. The percentage-changed check ensures a jump
  /// straight to 100% is never swallowed by the time gate.
  bool _shouldEmitProgress(String transactionId, int percent) {
    final now = DateTime.now();
    final lastEmit = _lastProgressEmit[transactionId];
    final lastPercent = _lastProgressPercent[transactionId];

    final percentChanged = lastPercent == null || percent != lastPercent;
    final dueForTick =
        lastEmit == null || now.difference(lastEmit) >= _progressThrottle;

    if (!percentChanged && !dueForTick) return false;

    _lastProgressEmit[transactionId] = now;
    _lastProgressPercent[transactionId] = percent;
    return true;
  }

  FlatpakEventType _progressType(String operation) => switch (operation) {
    'update' => FlatpakEventType.updateProgress,
    'uninstall' => FlatpakEventType.uninstallProgress,
    _ => FlatpakEventType.installProgress,
  };

  FlatpakEventType _completeType(String operation) => switch (operation) {
    'update' => FlatpakEventType.updateComplete,
    'uninstall' => FlatpakEventType.uninstallComplete,
    _ => FlatpakEventType.installComplete,
  };

  FlatpakEventType _failedType(String operation) => switch (operation) {
    'update' => FlatpakEventType.updateFailed,
    'uninstall' => FlatpakEventType.uninstallFailed,
    _ => FlatpakEventType.installFailed,
  };

  @override
  void stopListening(String transactionId) {
    debugPrint('[FlatpakEventDataSource] Stopping $transactionId');

    _progressSubscriptions[transactionId]?.cancel();
    _progressSubscriptions.remove(transactionId);
    _lastProgressEmit.remove(transactionId);
    _lastProgressPercent.remove(transactionId);

    _controllers[transactionId]?.close();
    _controllers.remove(transactionId);
  }

  @override
  void dispose() {
    debugPrint('[FlatpakEventDataSource] Disposing all transactions...');
    _isDisposed = true;

    final transactionIds = List<String>.from(_controllers.keys);
    for (final transactionId in transactionIds) {
      stopListening(transactionId);
    }

    _progressSubscriptions.clear();
    _lastProgressEmit.clear();
    _lastProgressPercent.clear();
    _controllers.clear();
  }
}
