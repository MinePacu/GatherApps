# Contributing to GatherApps

Thank you for taking the time to improve GatherApps. This project is a SwiftUI
macOS app, and contributions are expected to keep the desktop workflow focused,
reliable, and easy to maintain.

## Project Hosting

The primary Git remote for collaboration is GitLab:

- GitLab: `https://gitlab.com/minepacu-group/GatherApps`
- GitHub mirror: `https://github.com/MinePacu/GatherApps`

Use GitLab issues and merge requests when possible. GitHub issues may still be
used while the project is mirrored there, especially for existing public feature
requests and release assets.

## Before You Start

1. Check the existing issues before opening a new one.
2. For behavior changes, open an issue or describe the motivation clearly in the
   merge request.
3. Keep changes focused. Separate unrelated refactors, UI changes, CI changes,
   and release work into different branches.
4. Use branch names that describe the work, for example
   `feature/status-bar-controller`, `fix/launcher-refresh`, or
   `ci/gitlab-runner`.

Current open product areas include app ordering in the switcher, status bar
activation, update support, and generated launcher maintenance.

## Development Setup

Requirements:

- macOS 14.0 or later
- Xcode 15 or later for local development
- Xcode 26.4.1 or the project-selected Xcode when reproducing CI behavior
- Accessibility permission may be needed when testing window activation

To run the app:

1. Open `GatherApps.xcodeproj` in Xcode.
2. Select the `GatherApps` scheme.
3. Build and run the app.

The main app stores user data in:

- `~/Library/Application Support/GatherApps/groups.json`
- `~/Library/Application Support/GatherApps/Icons/`
- `~/Library/Application Support/GatherApps/window-helper-diagnostics.txt`

Generated launcher apps are written to:

- `~/Applications/GatherApps Launchers/`

## Testing

Run the test suite from Xcode, or use:

```sh
xcodebuild test -project GatherApps.xcodeproj -scheme GatherApps
```

The GitHub Actions workflow builds on macOS and runs tests with code signing
disabled. The GitLab pipeline uses a self-hosted macOS runner tagged `macos`,
runs merge request pipelines, publishes JUnit test reports, publishes SwiftLint
Code Quality reports, and includes GitLab SAST and Secret Detection templates.
Some launcher integration tests run in a separate non-blocking GitLab job
because they require local macOS app bundle behavior.

Before opening a merge request, run the tests that are relevant to the files you
changed. For launcher, update, activation, persistence, or URL-scheme changes,
also test the affected user flow manually.

## Coding Guidelines

- Follow the existing Swift and SwiftUI style in the repository.
- Prefer small, focused types and clear data flow over broad view-model or
  service changes.
- Keep localization keys in sync across `en`, `ko`, and `ja` string files.
- Do not introduce a new dependency unless it removes meaningful complexity and
  is appropriate for a macOS desktop app.
- Keep generated launcher behavior compatible with existing launchers whenever
  possible. If compatibility changes, document the migration path.
- Treat window activation, Accessibility permission handling, and update
  installation as user-trust-sensitive flows.

## Commit Messages

Use short, imperative commit messages, consistent with the existing history:

- `Add GitLab migration support`
- `Refresh stale launcher apps after updates`
- `Add Command-Tab launcher runtime support`
- `Fix CI test deployment target for macOS runners`

## Merge Request Checklist

Include the following in your merge request:

- What changed and why
- Screenshots or recordings for visible UI changes
- Manual testing notes for app activation, launcher generation, or updates
- Any skipped tests and why they were skipped
- Any follow-up work that should be tracked separately

CI must pass before merge unless the failure is clearly unrelated and documented
in the merge request.

## Releases and Updates

GatherApps uses Sparkle for non-App-Store updates. Release work should publish
matching appcast and archive assets to GitLab releases and GitHub releases while
both hosts are supported.

Before publishing an update:

1. Build an archived GatherApps app.
2. Sign and notarize the app bundle.
3. Generate the Sparkle signature.
4. Generate or update `appcast.xml`.
5. Attach the archive and appcast to GitLab and GitHub releases.
6. Verify updating from the previous public release preserves groups and
   refreshes stale generated launchers.

## Reporting Security Issues

Do not open a public issue for a vulnerability. Contact the maintainer privately
with enough detail to reproduce and assess the issue. Public disclosure should
wait until a fix is available or the maintainer has agreed on a disclosure plan.
