# GatherApps Launcher Apps

GatherApps can generate one small macOS `.app` launcher per group. Each generated launcher is a regular foreground macOS app so it can remain visible in the Command-Tab application switcher. The launcher delegates the actual group activation work back to the main GatherApps app through the custom URL scheme.

Generated launcher behavior:

- Bundle location: `~/Applications/GatherApps Launchers/`
- Executable: a copied AppKit runtime in `Contents/MacOS/GatherAppsLauncher`
- Activation bridge: `/usr/bin/open gatherapps://activate-group/<GROUP_UUID>?showWindow=false`
- Group identity: stored in `Info.plist` as `GatherAppsGroupID`
- GatherApps window policy: stored in `Info.plist` as `GatherAppsShowsGatherAppsWindow`
- GatherApps app path: stored in `Info.plist` as `GatherAppsApplicationPath`
- Launcher artifact metadata: stored in `Info.plist` as `GatherAppsLauncherSchemaVersion` and `GatherAppsLauncherRuntimeVersion`
- Icon: generated from the group's PNG representative icon and converted to `GroupIcon.icns`
- UI control: the group detail header exposes a `Show GatherApps window when launcher runs` toggle above the launcher generation button.
- Update behavior: when GatherApps starts after an app update, it checks known generated launcher bundles for stale metadata, stale app paths, stale window policy, or a runtime executable mismatch. Stale launchers are regenerated through the normal launcher generation path. If a stale launcher is already running, GatherApps terminates it before replacing the bundle and relaunches it after regeneration; launchers that were not running stay closed.

Command-Tab behavior:

- Generated launchers do not set `LSUIElement` or `LSBackgroundOnly`.
- The runtime calls `NSApp.setActivationPolicy(.regular)` and stays alive with the normal AppKit application run loop.
- Launching, reopening, or selecting the launcher app opens `gatherapps://activate-group/<GROUP_UUID>?showWindow=false`.
- When `GatherAppsApplicationPath` points to an existing app bundle, the runtime asks `NSWorkspace` to open the activation URL with that specific GatherApps app instead of relying only on the system-wide URL scheme handler.
- GatherApps remains responsible for raising the stored apps' windows through `AppActivationService` and `GatherAppsWindowHelper`.
- Launcher-triggered activation asks GatherApps to avoid presenting its own main window after the group activation command.
- If the user enables the GatherApps window toggle for a group, the stored policy is applied to generated launchers and the runtime omits the `showWindow=false` query so GatherApps may present its main window as part of activation.

Security and distribution notes:

- Development launchers are unsigned. This is acceptable for local development but may trigger macOS warnings depending on where the bundle is moved and how it is launched.
- Gatekeeper primarily applies quarantine checks to downloaded or transferred apps. A locally generated unsigned app may run locally, but it is not suitable for distribution.
- For distribution, sign each generated launcher bundle after creation:

```sh
codesign --force --sign "Developer ID Application: <Team Name>" "/path/to/GatherApps - Dev.app"
```

- If launchers are distributed outside the developer machine, notarize the signed app bundle and staple the ticket.
- The launcher app does not request Accessibility permissions, does not control windows, and does not auto-launch target apps. It only asks GatherApps to activate a stored group.
- Generated launchers remain running until the user quits them. This is required for macOS to keep them in Command-Tab.
