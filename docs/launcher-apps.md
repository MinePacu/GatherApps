# GatherTab Launcher Apps

GatherTab can generate one small macOS `.app` launcher per group. Each generated launcher is a regular foreground macOS app so it can remain visible in the Command-Tab application switcher. The launcher delegates the actual group activation work back to the main GatherTab app through the custom URL scheme.

Generated launcher behavior:

- Bundle location: `~/Applications/GatherTab Launchers/`
- Executable: a copied AppKit runtime in `Contents/MacOS/GatherTabLauncher`
- Activation bridge: `/usr/bin/open gathertab://activate-group/<GROUP_UUID>?showWindow=false`
- Group identity: stored in `Info.plist` as `GatherTabGroupID`
- GatherTab window policy: stored in `Info.plist` as `GatherTabShowsGatherTabWindow`
- GatherTab app path: stored in `Info.plist` as `GatherTabApplicationPath`
- Launcher artifact metadata: stored in `Info.plist` as `GatherTabLauncherSchemaVersion` and `GatherTabLauncherRuntimeVersion`
- Icon: generated from the group's PNG representative icon and converted to `GroupIcon.icns`
- UI control: the group detail header exposes a `Show GatherTab window when launcher runs` toggle above the launcher generation button.
- Update behavior: when GatherTab starts after an app update, it checks known generated launcher bundles for stale metadata, stale app paths, stale window policy, or a runtime executable mismatch. Stale launchers are regenerated through the normal launcher generation path. If a stale launcher is already running, GatherTab terminates it before replacing the bundle and relaunches it after regeneration; launchers that were not running stay closed.

Command-Tab behavior:

- Generated launchers do not set `LSUIElement` or `LSBackgroundOnly`.
- The runtime calls `NSApp.setActivationPolicy(.regular)` and stays alive with the normal AppKit application run loop.
- Launching, reopening, or selecting the launcher app opens `gathertab://activate-group/<GROUP_UUID>?showWindow=false`.
- When `GatherTabApplicationPath` points to an existing app bundle, the runtime asks `NSWorkspace` to open the activation URL with that specific GatherTab app instead of relying only on the system-wide URL scheme handler.
- GatherTab remains responsible for raising the stored apps' windows through `AppActivationService` and `GatherTabWindowHelper`.
- Launcher-triggered activation asks GatherTab to avoid presenting its own main window after the group activation command.
- If the user enables the GatherTab window toggle for a group, the stored policy is applied to generated launchers and the runtime omits the `showWindow=false` query so GatherTab may present its main window as part of activation.

Security and distribution notes:

- Development launchers are unsigned. This is acceptable for local development but may trigger macOS warnings depending on where the bundle is moved and how it is launched.
- Gatekeeper primarily applies quarantine checks to downloaded or transferred apps. A locally generated unsigned app may run locally, but it is not suitable for distribution.
- For distribution, sign each generated launcher bundle after creation:

```sh
codesign --force --sign "Developer ID Application: <Team Name>" "/path/to/GatherTab - Dev.app"
```

- If launchers are distributed outside the developer machine, notarize the signed app bundle and staple the ticket.
- The launcher app does not request Accessibility permissions, does not control windows, and does not auto-launch target apps. It only asks GatherTab to activate a stored group.
- Generated launchers remain running until the user quits them. This is required for macOS to keep them in Command-Tab.
