import 'package:flutter_remote_manager/business_logic/app_status/app_status_cubit.dart';
import 'package:flutter_remote_manager/business_logic/system_info/system_info_cubit.dart';
import 'package:get_it/get_it.dart';

import '../../data/repositories/flatpak_repository_impl.dart';

import 'business_logic/app_launch/app_launch_cubit.dart';
import 'business_logic/discovery/discovery_cubit.dart';
import 'business_logic/permission_listener/permission_listener_bloc.dart';
import 'business_logic/installation/installation_cubit.dart';
import 'data/data_sources/flatpak_event_data.dart';
import 'data/data_sources/flatpak_local_data.dart';
import 'data/data_sources/flatpak_permission_data.dart';
import 'data/repositories/flatpak_repository.dart';

final sl = GetIt.instance;

Future<void> initializeDependencies() async {
  // `flatpak_dart` clients: `user` is the primary client this app drives
  // everything through (install/uninstall/update/launch/browse), matching
  // how a per-user app store normally operates without root. `system` is
  // only consulted to list the system installation's remotes for the
  // system-info screen.
  final clients = FlatpakClients.create();
  sl.registerSingleton<FlatpakClients>(clients);

  // Data Sources
  sl.registerLazySingleton<FlatpakEventDataSource>(
    () => FlatpakEventDataSourceImpl(),
  );

  sl.registerLazySingleton<FlatpakLocalDataSource>(
    () => FlatpakLocalDataSourceImpl(sl(), sl()),
  );

  sl.registerLazySingleton<FlatpakPermissionDataSource>(
    () => FlatpakPermissionDataSource(),
  );

  // Repository
  sl.registerLazySingleton<FlatpakRepository>(
    () => FlatpakRepositoryImpl(
      localDataSource: sl(),
      eventDataSource: sl(),
      permissionDataSource: sl(),
    ),
  );

  // Permission listener
  sl.registerLazySingleton<PermissionListenerBloc>(
    () => PermissionListenerBloc(repository: sl()),
  );

  sl.registerLazySingleton<AppStatusCubit>(
    () => AppStatusCubit(repository: sl()),
  );

  // Installation cubit
  sl.registerLazySingleton<InstallationCubit>(
    () => InstallationCubit(repository: sl(), appStatusCubit: sl()),
  );

  // Discovery cubit
  sl.registerLazySingleton<DiscoveryCubit>(
    () => DiscoveryCubit(flatpakRepository: sl()),
  );

  // App launch cubit
  sl.registerLazySingleton<AppLaunchCubit>(
    () => AppLaunchCubit(repository: sl()),
  );

  // System info cubit
  sl.registerLazySingleton<SystemInfoCubit>(
    () => SystemInfoCubit(flatpakRepository: sl()),
  );
}

/// Clean up all singleton instances, including releasing the native
/// `flatpak_dart` client resources (`FlatpakClient.close()`).
Future<void> resetDependencies() async {
  if (sl.isRegistered<FlatpakClients>()) {
    await sl<FlatpakClients>().closeAll();
  }
  await sl.reset();
}
