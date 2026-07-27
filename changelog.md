# Changelog

All notable changes to Balalaio are documented here.

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
