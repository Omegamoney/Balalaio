# Changelog

All notable changes to Balalaio are documented here.

## 0.2.0 - 2026-07-27

### Added

- Added an install-ready Steamodded JSON package for Balatro's current Steam
  revision.
- Added a Windows installer that detects default and alternate Steam libraries,
  supports explicit or interactive folder selection, installs the current
  Lovely and Steamodded releases, preserves replaced files outside `Mods`, and
  rolls back earlier steps if a later installation step fails.
- Added Steam package, dependency metadata, installer fixture, and module reload
  regression tests, including staged dependency archives and rollback coverage.
- Added four in-game screenshots covering General controls, Joker management,
  editions, stickers, and per-instance values.

### Changed

- Reworked the README around the Steam one-click install, manual layout,
  compatibility boundary, usage, troubleshooting, and uninstall flow.
- Made the `Balalaio` folder the source of truth and directly copyable into the
  Steamodded `Mods` directory.
- Centralized the displayed and APK-injected version around the package metadata.

### Fixed

- Made the `Game.update` integration resolve the active global module so a
  Steamodded development reload cannot leave the launcher tied to stale state.
- Made loading the same Balalaio version idempotent.
- Pinned Steamodded compatibility to Balatro's full loader-visible
  `1.0.1o-FULL` version string.
- Updated the real input-path harness for the current Steam controller event
  manager and verified tap/drag behavior against the supplied Steam build.

## 0.1.1 - 2026-07-27

### Fixed

- Put the launcher in Balatro's native popup draw layer so card areas and the
  clean-install tutorial overlay can no longer steal its touch target.
- Hide the launcher during pause menus and brief controller input locks instead
  of leaving a visible but inactive control.
- Resynchronize the launcher's child transforms while dragging so the visible
  button follows its saved, edge-clamped position.
- Added a regression harness using Balatro's real Controller, UIBox, UIElement,
  Node, and Moveable input path from a locally extracted user-owned APK.
- Run the archive-injection test directly in PowerShell Core on GitHub Actions
  while retaining the Windows PowerShell-compatible local test command.

## 0.1.0 - 2026-07-27

### Added

- Movable in-game Balalaio launcher.
- Touch hit-testing for tapping and dragging the floating launcher and modal
  controls.
- General tab with nine live run values and `-1` / `+1` controls.
- Joker tab with add, remove, edition, sticker, and numeric modifier editing.
- Save-state and used-card-pool bookkeeping for mutations made from the modal.
- Source-only APK injection and signing workflow.
- Preflight rejection for incomplete split APKs and Pairip-protected wrappers.
- Compatibility guard for the supplied `1.0.1o-FULL [M]` game script.
- Byte-level package-name, app-name, icon, resource, native-library, and DEX
  identity guard.
- Lua parse, mocked runtime mutation, and synthetic archive build tests.
