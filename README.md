# Shorty

`Shorty` is a small macOS utility that binds global shortcuts to specific windows, not just apps.

Example: `cmd+option+1` can always bring your "project-a" VS Code window to the front, even if another VS Code window is focused or the target window is minimized.

## What It Does

- Registers global shortcuts with native macOS APIs.
- Finds a matching window by bundle ID, app identity, executable path, and optional window metadata matchers.
- Unminimizes the window if needed and brings it to the front.
- Reloads its JSON config file automatically when you save changes.
- Runs as a menu bar utility with `Reload Config`, `Reveal Config`, and `Quit`.

## Requirements

- macOS 13+
- Swift 6 / Xcode command line tools
- Accessibility permission for the built `Shorty` binary

## Build

```bash
./build.sh
```

## Run

```bash
./run.sh
```

`run.sh` launches the built binary with the repo-local `./config.json`.

If you want to run a different config directly:

```bash
./.build/arm64-apple-macosx/debug/Shorty --config ./Config.sample.json
```

If the binary does not exist yet, `run.sh` will build it once. After code changes, rebuild manually with `./build.sh` before restarting.

To inspect current windows and discover match values:

```bash
./.build/arm64-apple-macosx/debug/Shorty --list-windows
./.build/arm64-apple-macosx/debug/Shorty --list-windows --verbose
```

Plain mode prints one line per accessible window as:

```text
bundle.id<TAB>window title<TAB>document-or-url-or-identifier-or-executable-path
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
~/Library/Application Support/Shorty/config.json
```

The first time you run it, macOS should prompt for Accessibility access. If it does not, add the built `Shorty` binary manually in:

`System Settings > Privacy & Security > Accessibility`

## Validate Config

```bash
./.build/arm64-apple-macosx/debug/Shorty --validate-config --config ./Config.sample.json
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

The config file is plain JSON:

```json
{
  "shortcuts": [
    {
      "id": "project-a",
      "hotkey": "cmd+option+1",
      "bundleId": "com.microsoft.VSCode",
      "titleRegex": "project-a"
    }
  ]
}
```

`Config.sample.json` includes examples for every supported matcher type.

The repo-local `config.json` is your personal runtime config and is ignored by git.

### Shortcut Fields

- `id`: Optional name shown in logs.
- `hotkey`: Global shortcut like `cmd+option+1`, `ctrl+shift+f3`, `cmd+alt+space`.
- `bundleId`: Exact macOS bundle identifier, e.g. `com.microsoft.VSCode`.
- `appNameRegex`: Optional regex for the app display name.
- `executablePathRegex`: Optional regex for the app executable path. Useful when multiple installs share a bundle ID.
- `titleRegex`: Optional regex applied to the window title.
- `titleContains`: Optional case-insensitive plain substring match on the window title.
- `documentRegex`: Optional regex applied to the window document path when the app exposes one.
- `urlRegex`: Optional regex applied to the window URL when the app exposes one.
- `identifierRegex`: Optional regex applied to the Accessibility identifier when the app exposes one.
- `windowIndex`: Optional zero-based index if multiple windows match. Defaults to `0`.

At least one matcher must be set: `bundleId`, `appNameRegex`, `executablePathRegex`, `titleRegex`, `titleContains`, `documentRegex`, `urlRegex`, or `identifierRegex`.

## Notes

- VS Code usually exposes enough title text for project-level matching.
- Cursor, Zed, and other editors may expose a more useful `document` or `url` than `title`; use `--list-windows --verbose` to inspect that first.
- If you run multiple app installs with the same bundle ID, match the install directly with `executablePathRegex` and leave out window-title matchers.
- If a target app does not expose useful Accessibility window metadata, try combining `bundleId` with a broader `titleRegex`.
- If you want, this can be wrapped into a signed `.app` bundle or a `launchd` agent next.
