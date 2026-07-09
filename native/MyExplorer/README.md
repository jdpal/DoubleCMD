# My Explorer Native

This is the native macOS rewrite path for My Explorer. It is intentionally kept beside the existing Lazarus/Double Commander code while feature parity is built.

The current milestone provides:

- AppKit app shell with native menus and toolbar.
- Dual-pane file manager layout.
- Path bars and refresh navigation.
- File listing with name, size, kind, and modified date.
- Basic open, copy, move, rename, and delete operations.
- The existing My Explorer app icon.

Build locally:

```sh
swift build --package-path native/MyExplorer
```

Create a `.app` bundle:

```sh
native/MyExplorer/Scripts/build_app.sh
```

The bundled app is written to `native/MyExplorer/.build/My Explorer.app`.

Build a specific architecture:

```sh
ARCH=arm64 native/MyExplorer/Scripts/build_app.sh
ARCH=x86_64 native/MyExplorer/Scripts/build_app.sh
```
