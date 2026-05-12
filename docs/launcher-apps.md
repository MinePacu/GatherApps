# GatherTab Launcher Apps

GatherTab can generate one small macOS `.app` launcher per group. The first implementation uses a custom URL Scheme because it is the simplest durable bridge between an independently launched app bundle and the main GatherTab app.

Generated launcher behavior:

- Bundle location: `Application Support/GatherTab/Launchers/`
- Executable: a small shell script in `Contents/MacOS/GatherTabLauncher`
- Activation bridge: `/usr/bin/open gathertab://activate-group/<GROUP_UUID>`
- Group identity: stored in `Info.plist` as `GatherTabGroupID`
- Icon: generated from the group's PNG representative icon and converted to `GroupIcon.icns`

Security and distribution notes:

- Development launchers are unsigned. This is acceptable for local development but may trigger macOS warnings depending on where the bundle is moved and how it is launched.
- Gatekeeper primarily applies quarantine checks to downloaded or transferred apps. A locally generated unsigned app may run locally, but it is not suitable for distribution.
- For distribution, sign each generated launcher bundle after creation:

```sh
codesign --force --sign "Developer ID Application: <Team Name>" "/path/to/GatherTab - Dev.app"
```

- If launchers are distributed outside the developer machine, notarize the signed app bundle and staple the ticket.
- The launcher app does not request Accessibility permissions, does not control windows, and does not auto-launch target apps. It only asks GatherTab to activate a stored group.
