import 'package:equatable/equatable.dart';
import 'package:flutter_remote_manager/data/models/remote_model.dart';

class Installation extends Equatable {
  final String id;
  final String displayName;
  final String path;
  final bool noInteraction;
  final bool isUser;
  final int priority;
  final List<String> defaultLanguages;
  final List<String> defaultLocale;
  final List<Remote> remotes;

  const Installation({
    required this.id,
    required this.displayName,
    required this.path,
    required this.noInteraction,
    required this.isUser,
    required this.priority,
    required this.defaultLanguages,
    required this.defaultLocale,
    required this.remotes,
  });

  @override
  List<Object?> get props => [id, path];
}

class InstallationModel extends Installation {
  const InstallationModel({
    required super.id,
    required super.displayName,
    required super.path,
    required super.noInteraction,
    required super.isUser,
    required super.priority,
    required super.defaultLanguages,
    required super.defaultLocale,
    required super.remotes,
  });

  /// Build the "installation" the app displays for a given
  /// `FlatpakClient` scope (system or user).
  ///
  /// `flatpak_dart` has no equivalent of the old pigeon `Installation`
  /// type - it doesn't enumerate `/etc/flatpak/installations.d/*.conf`
  /// or expose path/priority/default-language configuration at all; it
  /// only gives you a client scoped to "system", "user", or an explicit
  /// path via `FlatpakClient.at()`. This synthesizes a single logical
  /// installation per scope from what's actually available (its remotes).
  factory InstallationModel.forScope({
    required bool isUser,
    required List<RemoteModel> remotes,
  }) {
    return InstallationModel(
      id: isUser ? 'user' : 'default',
      displayName: isUser ? 'User' : 'System',
      // flatpak_dart does not expose the on-disk installation path;
      // callers needing it should read $XDG_DATA_HOME/flatpak (user) or
      // /var/lib/flatpak (system) directly.
      path: '',
      noInteraction: false,
      isUser: isUser,
      priority: isUser ? 0 : 1,
      defaultLanguages: const [],
      defaultLocale: const [],
      remotes: remotes,
    );
  }
}
