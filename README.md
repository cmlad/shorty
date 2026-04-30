# Shorty

`Shorty` is a small macOS utility that binds global shortcuts to specific windows, not just apps.

Example: `cmd+option+1` can always bring your "project-a" VS Code window to the front, even if another VS Code window is focused or the target window is minimized.

## What It Does

- Registers global shortcuts with native macOS APIs.
- Finds a matching window by bundle ID, app identity, executable path, and optional window metadata matchers.
- Unminimizes the window if needed and brings it to the front.
- Reloads its YAML config file automatically when you save changes.
- Runs as a menu bar utility with loaded shortcuts, `Show Windows`, `Reload Config`, `Reveal Config`, and `Quit`.

## Requirements

- macOS 13+
- Swift 6 / Xcode command line tools
- Accessibility permission for the built `Shorty` binary

## Build

```bash
./build.sh
```

If the project directory moved and SwiftPM has stale module-cache paths, `build.sh` cleans local SwiftPM build artifacts and retries once.

## Build App

```bash
./build-app.sh
```

That creates:

```text
./dist/Shorty.app
```

Run it with:

```bash
open ./dist/Shorty.app
```

When launched as an app, Shorty uses its default config path:

```text
~/config/shorty.yaml
```

Create that directory and put your config there before launching from Finder:

```bash
mkdir -p "$HOME/config"
cp ./config.yaml "$HOME/config/shorty.yaml"
```

## Run

```bash
./run.sh
```

`run.sh` launches the built binary with the repo-local `./config.yaml`.

If you want to run a different config directly:

```bash
./.build/arm64-apple-macosx/debug/Shorty --config ./Config.sample.yaml
```

If the binary does not exist yet, `run.sh` will build it once. After code changes, rebuild manually with `./build.sh` before restarting.

To inspect current windows and discover match values:

```bash
./.build/arm64-apple-macosx/debug/Shorty --list-windows
./.build/arm64-apple-macosx/debug/Shorty --list-windows --verbose
```

Plain mode prints one labeled block per accessible window:

```text
Bundle ID: com.example.App
Window title: Project
Best match value: file:///Users/example/project/file.txt
```

Verbose mode also prints:

- `appWindowIndex`
- `document`
- `url`
- `identifier`
- `executablePath`
- `role` / `subrole`
- `position` / `size`
- `minimized`

If you omit `--config`, Shorty looks for:

```text
~/config/shorty.yaml
```

The first time you run it, macOS should prompt for Accessibility access. If it does not, add the built `Shorty` binary manually in:

`System Settings > Privacy & Security > Accessibility`

For the `.app` bundle, add `dist/Shorty.app` to Accessibility instead of the raw binary.

## Validate Config

```bash
./.build/arm64-apple-macosx/debug/Shorty --validate-config --config ./Config.sample.yaml
```

## Finding Bundle IDs

Use Shorty itself:

```bash
./.build/arm64-apple-macosx/debug/Shorty --list-windows
```

If you already know the app name, these macOS commands also work:

```bash
osascript -e 'id of app "Visual Studio Code"'
mdls -name kMDItemCFBundleIdentifier -r /Applications/Visual\ Studio\ Code.app
```

## Config Format

The default config file is YAML:

```yaml
shortcuts:
  project-a:
    hotkey: cmd+option+1
    bundle-id: com.microsoft.VSCode
    title-regex: project-a
```

Each key under `shortcuts` is the shortcut id shown in logs. `Config.sample.yaml` includes examples for every supported matcher type.

The repo-local `config.yaml` is your personal runtime config and is ignored by git.

### Shortcut Fields

- `hotkey`: Global shortcut like `cmd+option+1`, `ctrl+shift+f3`, `cmd+alt+space`.
- `bundle-id`: Exact macOS bundle identifier, e.g. `com.microsoft.VSCode`.
- `app-name-regex`: Optional regex for the app display name.
- `executable-path-prefix`: Optional plain prefix for the app executable path. Use a normal path like `/Applications/Cursor.app/`, with no `^` or regex escaping.
- `title-regex`: Optional regex applied to the window title.
- `title-contains`: Optional case-insensitive plain substring match on the window title.
- `document-regex`: Optional regex applied to the window document path when the app exposes one.
- `url-regex`: Optional regex applied to the window URL when the app exposes one.
- `identifier-regex`: Optional regex applied to the Accessibility identifier when the app exposes one.
- `window-index`: Optional zero-based index if multiple windows match. Defaults to `0`.

At least one matcher must be set: `bundle-id`, `app-name-regex`, `executable-path-prefix`, `title-regex`, `title-contains`, `document-regex`, `url-regex`, or `identifier-regex`.

## Notes

- VS Code usually exposes enough title text for project-level matching.
- Cursor, Zed, and other editors may expose a more useful `document` or `url` than `title`; use `--list-windows --verbose` to inspect that first.
- If you run multiple app installs with the same bundle ID, match the install directly with `executable-path-prefix` and leave out window-title matchers.
- If a target app does not expose useful Accessibility window metadata, try combining `bundle-id` with a broader `title-regex`.
- If you want, this can be wrapped into a signed `.app` bundle or a `launchd` agent next.
