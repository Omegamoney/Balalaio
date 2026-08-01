# Changelog

All notable changes to Balalaio are documented here.

## 0.5.0 - 2026-08-01

### Added

- Added an Extras tab for editing Ante, Round, winning Ante, hand size,
  physical card-selection capacity, independent playable-card and
  discardable-card limits, shop card slots, base reroll cost, interest amount
  and cap, and Luck during an active run.
- Added deck selection mode with individual-card selection plus page-wide,
  whole-deck, and clear-selection shortcuts.
- Added a bulk deck editor whose scope can be switched among all cards, the
  current page, and the current selection.
- Added direct bulk choices for rank and suit, plus enhancement, edition, and
  seal effects, so a large deck does not need to be cycled card by card.
- Added two-step confirmation before removing every card in a bulk target.

### Changed

- Hand-size, play-limit, discard-limit, shop-size, and reroll-cost mutations
  use the corresponding Balatro or Steamodded update paths when available, so
  the live UI and derived limits can follow the edited values.
- Bulk edits snapshot their target scope and ignore cards that are no longer
  live. Property changes use each card's native setters, while batch removal
  emits one Steamodded removal context; a completed batch is saved once.
- Documented the exact versioned Windows updater filename and the explicit APK
  output path used to prepare matching 0.5.0 release artifacts.

## 0.4.0 - 2026-07-31

### Added

- Replaced the Add Joker name list with a five-card native gallery. Catalog
  cards keep Balatro's normal hover, touch, and controller detail popup, while
  a separate Add button prevents accidental selection.
- Added a Consumables tab for live Tarot, Planet, and Spectral card previews,
  exact type-filtered additions, edition editing, and safe per-instance numeric
  effect editing.
- Added a Deck tab backed by the complete `G.playing_cards` collection, so
  cards remain visible while they are in the draw pile, hand, discard, or
  another live card area.
- Added exact playing-card creation plus native rank, suit, enhancement,
  edition, and seal editing, and playing-card removal with Steamodded context
  notifications.
- Added gallery and CRUD regression coverage for isolated previews,
  consumable config aliases, playing-card IDs, deck capacity, and mod hooks.

### Changed

- Generalized the owned-Joker preview pipeline for live consumables, playing
  cards, and catalog entries without moving or cloning live bookkeeping state.
- Consumable and deck mutations now use Balatro's normal constructors, setters,
  materialization, save path, and Steamodded calculation contexts.
- Collection changes that return no mutation no longer trigger a redundant run
  save.

### Fixed

- Explicitly tear down preview cards when their private CardArea closes;
  Balatro's native CardArea teardown does not remove its contained Cards.
- Suppress custom center `set_ability` hooks only while constructing a preview,
  preventing gallery browsing from changing the live run while restoring the
  hook immediately afterward.
- Restore each center's exact `used_jokers` state after preview construction so
  opening a catalog cannot remove cards from future gameplay pools.
- Reassert display-only gallery behavior after native CardArea insertion, which
  otherwise re-enables dragging for cards in title areas.
- Exclude the shared `ability.consumeable` alias from numeric traversal so
  editing one consumable cannot mutate the global center definition.
- Detach and mirror edited config-origin values into a per-card consumable
  config, keeping both native and Steamodded effect reads functional across
  run saves without changing other copies of the card.
- Protect new playing-card IDs against stale high-water counters and
  synchronize deck capacity immediately after adding or removing a card.
- Reject deck edits and removals for stale, destroyed, area-less, or actively
  scoring playing cards.
- Exclude Negative from playing-card edition choices because Balatro routes
  that edition's capacity effect through Joker/consumable areas.

## 0.3.0 - 2026-07-30

### Added

- Replaced the owned-Joker name list with a five-card native gallery that
  renders the current cards, editions, stickers, debuffs, and other visual
  state.
- Added native hover, touch-hold, and controller detail popups to gallery
  previews, with tooltip values delegated to the live Joker instance.
- Added bounded press-and-hold repeat for numeric `-` and `+` controls using
  Balatro's native 0.30-second delay and a 10-actions-per-second ceiling.
- Added `update.bat` for Balalaio-only upgrades and a reproducible versioned
  Windows updater archive builder.

### Changed

- Numeric Joker modifiers now derive their adjustment step from the card
  center's default: integer defaults retain a step of `1`, while fractional
  defaults such as `0.25`, `0.01`, and `1.5` use that exact step.
- Hold-repeat mutations save once when the hold ends instead of serializing the
  run on every repeated tick.
- The Android builder now defaults to the ignored
  `local-input\BalatroLatest.apk` path for repeatable local builds.

### Fixed

- Rounded repeated fractional edits to the relevant decimal precision so
  values such as `0.1` do not accumulate floating-point display drift.
- Resolved lowercase `x_mult` and custom-edition config paths when deriving
  fractional steps.
- Filtered untouched Steamodded framework numerics from the Joker editor so
  each page stays focused on configured or changed values.
- Let Steamodded own Negative slot accounting when cycling editions, avoiding
  duplicate or missing Joker capacity.
- Kept gallery previews isolated from live Joker areas and deck bookkeeping so
  closing a preview cannot remove a Joker or alter Negative capacity.

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
