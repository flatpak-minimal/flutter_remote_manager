import 'package:equatable/equatable.dart';
import 'package:flatpak_dart/flatpak_dart.dart';

class Remote extends Equatable {
  final String name;
  final String url;
  final String collectionId;
  final String title;
  final String comment;
  final String description;
  final String homepage;
  final String icon;
  final String defaultBranch;
  final String mainRef;
  final String remoteType;
  final String filter;
  final String appstreamTimestamp;
  final String appstreamDir;
  final bool gpgVerify;
  final bool noEnumerate;
  final bool noDeps;
  final bool disabled;
  final int prio;

  const Remote({
    required this.name,
    required this.url,
    required this.collectionId,
    required this.title,
    required this.comment,
    required this.description,
    required this.homepage,
    required this.icon,
    required this.defaultBranch,
    required this.mainRef,
    required this.remoteType,
    required this.filter,
    required this.appstreamTimestamp,
    required this.appstreamDir,
    required this.gpgVerify,
    required this.noEnumerate,
    required this.noDeps,
    required this.disabled,
    required this.prio,
  });

  @override
  List<Object?> get props => [name, url, collectionId];
}

class RemoteModel extends Remote {
  const RemoteModel({
    required super.name,
    required super.url,
    required super.collectionId,
    required super.title,
    required super.comment,
    required super.description,
    required super.homepage,
    required super.icon,
    required super.defaultBranch,
    required super.mainRef,
    required super.remoteType,
    required super.filter,
    required super.appstreamTimestamp,
    required super.appstreamDir,
    required super.gpgVerify,
    required super.noEnumerate,
    required super.noDeps,
    required super.disabled,
    required super.prio,
  });

  /// Build from a `flatpak_dart` [FlatpakRemote].
  ///
  /// `flatpak_dart` does not expose everything the old pigeon `Remote`
  /// type carried (no `mainRef`, `icon`, `appstreamTimestamp`,
  /// `appstreamDir`, or `noEnumerate` - those were libostree/libflatpak
  /// internals the old native plugin happened to surface). Those fields
  /// are kept on [Remote] for API stability but default to empty/false.
  factory RemoteModel.fromFlatpakRemote(FlatpakRemote remote) {
    return RemoteModel(
      name: remote.name,
      url: remote.url,
      collectionId: remote.collectionId,
      title: remote.title,
      comment: remote.comment,
      description: remote.description,
      homepage: remote.homepage,
      icon: '',
      defaultBranch: remote.defaultBranch,
      mainRef: '',
      remoteType: remote.remoteType.name,
      filter: remote.filter,
      appstreamTimestamp: '',
      appstreamDir: '',
      gpgVerify: remote.gpgVerify,
      noEnumerate: false,
      noDeps: remote.noDeps,
      disabled: remote.disabled,
      prio: remote.priority,
    );
  }

  /// Convert to a `flatpak_dart` [FlatpakRemoteConfig] for
  /// `FlatpakRemoteManager.add`/`.modify`. [name] is passed separately to
  /// those calls; it isn't part of the config payload itself.
  FlatpakRemoteConfig toRemoteConfig() {
    return FlatpakRemoteConfig(
      url: url,
      title: title.isEmpty ? null : title,
      comment: comment.isEmpty ? null : comment,
      homepage: homepage.isEmpty ? null : homepage,
      defaultBranch: defaultBranch.isEmpty ? null : defaultBranch,
      collectionId: collectionId.isEmpty ? null : collectionId,
      filter: filter.isEmpty ? null : filter,
      priority: prio,
      gpgVerify: gpgVerify,
      disabled: disabled,
      noDeps: noDeps,
    );
  }
}
