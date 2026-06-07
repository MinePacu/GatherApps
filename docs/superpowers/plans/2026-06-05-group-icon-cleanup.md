# Group Icon Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically remove generated group icon PNG files that are no longer referenced by any stored group.

**Architecture:** Add a dedicated cleanup service that scans the icons directory and removes orphaned PNG files based on the persisted `iconFileName` values. Keep cleanup trigger decisions in `AppGroupStore`, and inject icon services so tests can run against temporary directories without touching the real app support folder.

**Tech Stack:** Swift, XCTest, AppKit, Foundation

---

### Task 1: Add failing tests for orphan cleanup behavior

**Files:**
- Create: `GatherAppsTests/GroupIconCleanupServiceTests.swift`
- Modify: `GatherAppsTests/AppGroupStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
func testCleanupRemovesOnlyUnreferencedPNGFiles() throws
func testStoreInitializationCleansUpOrphanedIcons() throws
func testRegeneratingGroupIconTriggersOrphanCleanup() throws
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project GatherApps.xcodeproj -scheme GatherApps -destination 'platform=macOS' -only-testing:GatherAppsTests/GroupIconCleanupServiceTests -only-testing:GatherAppsTests/AppGroupStoreTests`
Expected: FAIL because cleanup service and injected cleanup flow do not exist yet.

### Task 2: Implement cleanup service and injection points

**Files:**
- Create: `GatherApps/Services/GroupIconCleanupService.swift`
- Modify: `GatherApps/Services/GroupIconService.swift`
- Modify: `GatherApps/Stores/AppGroupStore.swift`

- [ ] **Step 1: Add minimal cleanup implementation**

```swift
@MainActor
struct GroupIconCleanupService {
    func cleanup(referencedFileNames: Set<String>) throws
}
```

- [ ] **Step 2: Add directory injection to icon services**

```swift
init(iconsDirectoryURL: URL? = nil)
```

- [ ] **Step 3: Wire cleanup triggers into `AppGroupStore`**

```swift
cleanupOrphanedIcons()
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project GatherApps.xcodeproj -scheme GatherApps -destination 'platform=macOS' -only-testing:GatherAppsTests/GroupIconCleanupServiceTests -only-testing:GatherAppsTests/AppGroupStoreTests`
Expected: PASS

### Task 3: Verify broader regression surface

**Files:**
- Test: `GatherAppsTests/AppGroupStoreTests.swift`

- [ ] **Step 1: Run focused regression tests**

Run: `xcodebuild test -project GatherApps.xcodeproj -scheme GatherApps -destination 'platform=macOS' -only-testing:GatherAppsTests/AppGroupStoreTests`
Expected: PASS

- [ ] **Step 2: Run full test suite if practical**

Run: `xcodebuild test -project GatherApps.xcodeproj -scheme GatherApps -destination 'platform=macOS'`
Expected: PASS
