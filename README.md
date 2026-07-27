# Balalaio

Balalaio is an offline, in-game cheat panel for a user-supplied Android build of
Balatro. It adds a movable button and a native-looking modal with General and
Jokers tools.

This repository contains only original Balalaio source code, build scripts, and
tests. It does **not** contain Balatro, extracted game assets, signing keys, or
APK files.

## Current compatibility

The first pass targets a self-contained, unprotected mobile build with:

- Game version: `1.0.1o-FULL [M]`
- Android wrapper version: `12.5.6`
- Package ID: `com.playstack.balatro.android`
- Android version: `1.8` (`versionCode` 47)
- Native ABIs: `arm64-v8a`, `armeabi-v7a`
- Expected `assets/main.lua` SHA-256:
  `362cc16e08841d527dff3c1fa5a3feedb7107df408fe4e2e680e1b4906e10f4c`
- Verified universal input APK SHA-256:
  `2122333ae94e048b4c3fdfd7279aac52a388917a98e652fe6335e8f24bd5c9e0`

The build script stops on an unknown game script by default so it cannot silently
produce a broken APK. It also rejects Play base-split APKs without native
libraries and wrappers containing Pairip signature protection. Balalaio does
not remove or bypass license or anti-tamper components.

## Features

- Movable, edge-clamped `BALALAIO` button rendered in Balatro's native popup
  layer so it remains touchable above cards and the first-run tutorial.
- General controls for current/max hands, current/max discards, occupied/max
  Joker slots, money, and occupied/max consumable slots.
- Joker browser with add, remove, edition, Eternal, Perishable, and Rental
  controls.
- Advanced per-instance numeric modifier editor with `-1` and `+1` controls.
- Paginated layouts designed for a landscape phone screen.

## Build

Requirements:

- Windows PowerShell 5.1 or PowerShell 7+
- Java/JDK 8 or newer
- A legally obtained, compatible APK placed outside Git
- Internet access on the first build to download the pinned APK signing tool

From the repository root:

```powershell
.\scripts\build.ps1 -InputApk .\Balatro-v1.8.apk
```

The signed output is written to `dist\Balalaio.apk`. The script prints its
SHA-256 after signing and verification. It also fails the build if the compiled
manifest, package identity, display-name resources, icon resources, Android
resources, native libraries, or DEX files differ from the input.

To use a custom signing keystore:

```powershell
.\scripts\build.ps1 `
  -InputApk .\Balatro-v1.8.apk `
  -Keystore C:\secure\balalaio.jks `
  -KeystoreAlias balalaio
```

Never commit the source APK, generated APK, or signing key. All of those paths
are ignored by this repository.

## Installing the test build

The package ID is intentionally unchanged, so Balalaio cannot coexist with an
official Balatro installation. Android also refuses to update an app when the
new APK is signed by a different certificate.

For the first test install:

1. Back up any local saves you care about.
2. Uninstall the existing `com.playstack.balatro.android` package.
3. Install `dist\Balalaio.apk`.

For repeatable in-place updates, supply the same private keystore on every
build. The default signer is suitable for local testing, but it is not a private
release identity.

The build verifies ZIP alignment and Android v1, v2, and v3 signatures before
returning an APK. It does not remove or bypass license, Play Integrity, or
anti-tamper components. An upstream Play-protected APK can therefore still show
its own license or installer-source prompt after launch even when Android's
package verification succeeds.

## Development checks

```powershell
npm install
npm test
```

The test suite parses the Lua source as Lua 5.1, exercises mutations in a mocked
Balatro runtime, validates tap/drag behavior through the extracted game's real
input classes when a user-owned APK has been decoded locally, and validates the
unsigned ZIP injection path against a synthetic APK-shaped fixture.

## Notes

- The application ID (`com.playstack.balatro.android`), app name, package
  version, and icon remain those of the supplied APK.
- Android clean-install testing found and informed the `0.1.1` launcher
  touch-layer fix. Automated checks still run without a connected device.
- Cheats are intended for offline, single-player use.
- Balatro and its assets are owned by their respective rights holders and are
  not distributed here.
