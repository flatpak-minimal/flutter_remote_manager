import 'package:flutter/material.dart';
import 'app.dart';
import 'injection_container.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeDependencies();

  // Release the flatpak_dart FlatpakClient native resources on process
  // exit (SIGINT/SIGTERM/window close on desktop).
  AppLifecycleListener(onDetach: () async {
    await resetDependencies();
  });

  runApp(const FlatpakApp());
}
