# Siargao GenUI app

Flutter app that renders the Siargao A2UI v0.9 catalog with genui 0.10.4. Shared rules live in `../docs/CONTRACT.md`.

Toolchain: `export PATH=~/fvm/versions/3.47.5/bin:$PATH` (Flutter 3.47.5, Dart 3.13.4). Package versions are pinned exactly in `pubspec.yaml`.

## Run

```sh
flutter run -d chrome                                   # offline fixtures (default)
flutter run -d chrome --dart-define=DEMO_MODE=live \
  --dart-define=AGENT_URL=http://localhost:10002 \
  --dart-define=MCP_URL=http://localhost:10003/mcp
```

Deep links (web): `?tab=chat|home|search|gallery`, `&intent=<id>` runs a chat prompt, `&view=text|a2ui|both`. On iOS and Android pass the same query as `--dart-define=DEEP_LINK=tab=home`.

A2UI stream inspector: the `{ }` button in the app bar (or `inspect=1`) shows every request and A2UI message as it arrives, beside the surface it builds. Pace `instant|slow|step` (`pace=` in the link) holds each message before it renders; in Step, PageDown or the right arrow renders the next one, so a presentation clicker works. Code in `lib/inspector/`.

## Test

```sh
flutter analyze
dart format --set-exit-if-changed .
flutter test                                  # widget, golden, service, fixture tests
flutter test --update-goldens test/goldens    # after an intended visual change
```

## Shared files

- Catalog schemas: `lib/catalog/catalog_schemas.g.dart` is generated. Do not edit it. Regenerate with `cd ../catalog && .venv/bin/python tools/gen_dart.py`.
- Fixtures: `assets/fixtures/` and `assets/catalog/images.json` are copies. Run `tool/sync_shared.sh` after `../fixtures` or `../catalog/images.json` change; `test/shared_sync_test.dart` fails until you do.
- Images: drop `<key>.jpg|png|webp` into `assets/img/`. Missing files show a placeholder.

## Screenshots

```sh
flutter build web --release --no-web-resources-cdn --dart-define=DEMO_MODE=offline
(cd build/web && python3 -m http.server 8080) &
tool/screenshots.sh http://localhost:8080 ../docs/screens
```

## Layout

`lib/catalog/` one file per widget, `lib/a2ui/` surface hosting and the unknown component guard, `lib/services/` A2A, MCP and fixtures, `lib/features/<screen>/` the tabs and the gallery.
