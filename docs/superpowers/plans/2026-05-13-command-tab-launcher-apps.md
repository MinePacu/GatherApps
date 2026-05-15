# Command-Tab Launcher Apps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make generated GatherApps launcher `.app` bundles appear in the macOS Command-Tab switcher and activate their stored app group when selected.

**Architecture:** Replace the generated shell-script launcher executable with a reusable foreground AppKit launcher runtime. The main app copies that runtime into each generated launcher bundle, while the runtime reads `GatherAppsGroupID` from its host bundle and opens the existing `gatherapps://activate-group/<UUID>` URL whenever launched, reopened, or selected.

**Tech Stack:** Swift, AppKit, Xcode macOS targets, XCTest, existing GatherApps URL scheme and activation service.

---

### Task 1: Lock Launcher Generation Contract

**Files:**
- Modify: `GatherAppsTests/GatherAppsTests.swift`
- Modify: `GatherApps/Services/LauncherAppGeneratorService.swift`

- [x] **Step 1: Write the failing test**

Add a launcher generation test that creates a fake runtime executable, injects it into `LauncherAppGeneratorService`, and verifies the generated `.app` executable is copied from that runtime instead of being a short shell script.

- [x] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project GatherApps.xcodeproj -scheme GatherApps -only-testing:GatherAppsTests/GatherAppsTests/testLauncherGeneratorCopiesRuntimeExecutableForCommandTabVisibility`

Expected: FAIL because `LauncherAppGeneratorService` has no runtime executable injection and still writes a shell script.

- [x] **Step 3: Write minimal implementation**

Add an initializer to `LauncherAppGeneratorService` that accepts an optional launcher runtime executable URL. Change executable generation to copy that executable into `Contents/MacOS/GatherAppsLauncher` and mark it executable.

- [x] **Step 4: Run test to verify it passes**

Run the same focused XCTest command.

Expected: PASS.

### Task 2: Add Foreground Launcher Runtime

**Files:**
- Create: `GatherAppsLauncherRuntime/main.swift`
- Modify: `GatherApps.xcodeproj/project.pbxproj`

- [x] **Step 1: Add runtime source**

Create a small AppKit executable that sets regular activation policy, stays alive with `NSApplication.shared.run()`, and opens the GatherApps activation URL on launch, reopen, and active selection.

- [x] **Step 2: Add Xcode target**

Add a macOS command-line tool target named `GatherAppsLauncherRuntime` and make the main `GatherApps` app depend on it.

- [x] **Step 3: Copy runtime into main app resources**

Add a copy files build phase that places the built `GatherAppsLauncherRuntime` executable under `Contents/Resources/LauncherRuntime/`.

- [x] **Step 4: Build**

Run: `xcodebuild build -project GatherApps.xcodeproj -scheme GatherApps`

Expected: PASS and the built GatherApps app contains `Contents/Resources/LauncherRuntime/GatherAppsLauncherRuntime`.

### Task 3: Wire Runtime Lookup and Documentation

**Files:**
- Modify: `GatherApps/Services/LauncherAppGeneratorService.swift`
- Modify: `docs/launcher-apps.md`

- [x] **Step 1: Add default runtime lookup**

Resolve the bundled runtime at `Bundle.main.resourceURL/LauncherRuntime/GatherAppsLauncherRuntime` for production generator calls.

- [x] **Step 2: Preserve foreground app metadata**

Keep `CFBundlePackageType = APPL`, keep a unique `CFBundleIdentifier`, and do not add `LSUIElement` or `LSBackgroundOnly`.

- [x] **Step 3: Update docs**

Document that generated launchers are regular foreground apps, remain running for Command-Tab visibility, and delegate activation to GatherApps through the URL scheme.

- [ ] **Step 4: Run full verification**

Run: `xcodebuild test -project GatherApps.xcodeproj -scheme GatherApps`

Expected: PASS.
