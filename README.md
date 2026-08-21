# flutter_remote_manager

A Flutter app-store UI for managing Flatpaks on AGL/IVI systems — browse remotes,
install and update apps, and manage portal permissions.

It talks to libflatpak in-process through
[flatpak_dart](https://github.com/flatpak-minimal/flatpak_dart)'s FFI bridge, with app
metadata coming from `appstream_dart`. There is no platform-channel plugin involved.

The app is built and packaged for Flatpak by
[org.flatpak_minimal.flatpak_dart.example.flutter_remote_manager](https://github.com/flatpak-minimal/org.flatpak_minimal.flatpak_dart.example.flutter_remote_manager),
which runs it under `homescreen` rather than Flutter's own Linux runner.

## Running

```sh
flutter pub get
flutter run -d linux
```

Running under `homescreen` instead needs a custom device configured and the app built as
an ivi-homescreen bundle — the packaging repo does that via `emb bundle`.

## Native dependencies

`flatpak_dart`'s build hook compiles a C++ bridge, so a first build produces three
libraries alongside the usual Flutter output: `libflatpak_nc.so`, `libappstream.so` and
`libsqlite3.so`. They land in `build/flutter_assets/native_assets/linux/` and are declared
in `NativeAssetsManifest.json` with bare sonames, so at runtime they resolve through the
normal library search path. Anything packaging this app has to place them somewhere the
loader will find them.

## Dependency pins

`pubspec.yaml` carries `dependency_overrides` for `hooks`, `code_assets` and
`native_toolchain_c`. They pin one consistent generation of the native-assets build-hook
packages: this Flutter SDK ships `meta 1.18.0`, `hooks` 2.x needs `meta ^1.19.0`,
`code_assets` 1.2.x needs `hooks` 2.x, and `native_toolchain_c` 0.19.x reads
`CodeConfig.sanitizer` which only exists in `code_assets` 1.2.x. Mixing generations fails
to compile any build hook. Revisit when the SDK ships `meta >= 1.19.0`.
