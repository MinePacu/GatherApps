# GatherTab

English | [한국어](README.md) | [日本語](README.ja.md)

GatherTab is a SwiftUI macOS app for grouping related apps and bringing them forward together. Save the apps you use for a workflow, such as a browser, messenger, and IDE, then activate the group when you want those app windows back in front.

## Features

- Add currently running apps to groups
- Save and delete app groups
- Generate group icons automatically
- Activate all app windows in a selected group
- Open a floating group switcher from the toolbar
- Generate Command-Tab launcher apps for individual groups
- Activate groups through the `gathertab://activate-group/<GROUP_UUID>` URL scheme

## Requirements

- macOS 14.0 or later
- Xcode 15 or later recommended
- macOS Accessibility permission may be required to reliably raise app windows.

## Getting Started

1. Open `GatherTab.xcodeproj` in Xcode.
2. Select the `GatherTab` scheme.
3. Press Run to launch the app.
4. Create a group with the `Create Group` button in the sidebar.
5. Add apps from the running-app list with the `+` button.
6. Press `Activate Group` to bring the grouped app windows forward.

## Command-Tab Launchers

Each group can generate a small macOS `.app` launcher. The generated launcher stays in the Command-Tab application switcher like a regular app and asks GatherTab to activate its group when selected.

- Location: `~/Applications/GatherTab Launchers/`
- How to generate: click `Generate Launcher` in the group detail view
- Implementation notes: [docs/launcher-apps.md](docs/launcher-apps.md)

## Data Locations

GatherTab stores group data and generated icons in the user's Application Support directory.

- Group data: `~/Library/Application Support/GatherTab/groups.json`
- Group icons: `~/Library/Application Support/GatherTab/Icons/`
- Window helper diagnostics: `~/Library/Application Support/GatherTab/window-helper-diagnostics.txt`

## Project Structure

- `GatherTab/`: main SwiftUI app
- `GatherTabWindowHelper/`: helper runtime for raising app windows
- `GatherTabLauncherRuntime/`: runtime used by generated group launcher apps
- `GatherTabTests/`: unit tests
- `GatherTabUITests/`: UI tests
- `docs/`: additional design and implementation notes

## Testing

Use Xcode's Test action, or run the test suite from the terminal:

```sh
xcodebuild test -project GatherTab.xcodeproj -scheme GatherTab
```

## Notes

- Generated launcher apps are created for local development by default. Distribution requires code signing and notarization.
- Launcher apps do not control windows directly. They call GatherTab's URL scheme and delegate group activation to the main app.
