# Changelog

All notable changes to GatherApps will be documented in this file.

This project follows the spirit of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and uses semantic versioning for public releases when practical.

## [Unreleased]

### Added

- GitLab-focused project governance files, including contribution guidelines,
  code of conduct, license, and changelog.
- GitLab Free-compatible CI improvements for merge request pipelines, SwiftLint
  Code Quality reports, JUnit test reports, SAST, Secret Detection, and
  non-blocking launcher integration test coverage.

### Notes

- GitLab is configured as the primary collaboration remote, with GitHub kept as
  a public mirror and release fallback.
- The GitLab pipeline uses a self-hosted macOS runner tagged `macos`.

## [1.0.0] - 2026-05-17

### Added

- Initial SwiftUI macOS app for grouping running apps by workflow.
- Group creation, deletion, persistence, and icon generation.
- App activation flow for bringing grouped app windows forward together.
- Floating group switcher opened from the toolbar.
- Command-Tab launcher app generation for individual groups.
- Launcher runtime support using the
  `gatherapps://activate-group/<GROUP_UUID>` URL scheme.
- Login-item window helper activation flow for more reliable window raising.
- Localized UI strings for English, Korean, and Japanese.
- Sparkle-based in-app update support with GitLab appcast priority and GitHub
  fallback.
- Launcher refresh behavior for stale generated launchers after app updates.
- GitHub Actions CI for macOS build and test coverage.
- GitLab CI/CD pipeline support for build and unit tests on a self-hosted
  macOS runner.

### Changed

- Renamed the app from GatherTab to GatherApps.
- Centered README branding and synchronized multilingual README content.
- Adjusted CI to run tests sequentially on macOS and use an x86_64 test
  destination where needed.
- Pinned GitHub Actions CI to Xcode 26.4.1.
- Updated GitLab CI to use the `macos` runner tag.

### Fixed

- Safer group deletion flow, including generated launcher cleanup.
- Launcher test stability by using executable and binary runtime fixtures.
- CI deployment-target and hosted-runner limitations around launcher
  integration tests.

## [0.1.0] - 2026-05-12

### Added

- Initial repository setup.
