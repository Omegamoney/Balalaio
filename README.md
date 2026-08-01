# Balalaio

Balalaio is an offline, in-game control panel for Balatro. It gives you direct
control over run resources, Jokers, consumables, and playing cards through a
native-looking overlay—without editing `Balatro.exe` or distributing any game
files.

The primary release now targets **Balatro on Steam for Windows** through
[Lovely](https://github.com/ethangreen-dev/lovely-injector) and
[Steamodded](https://github.com/Steamodded/smods). The install-ready mod is in
[`Balalaio/`](Balalaio/).

> Balalaio is intended for offline, single-player experimentation. Back up any
> run you care about before using cheats.

## What it can do

- Change current and maximum hands or discards.
- Change money, Joker capacity, and consumable capacity.
- Use the Extras tab to adjust Ante, Round, winning Ante, hand size, physical
  card-selection capacity, separate playable-card and discardable-card limits,
  shop card slots, base reroll cost, interest amount and cap, and Luck.
- Browse and add Jokers through a rarity-filtered, five-card native gallery.
- Browse owned Jokers as their real in-game cards, including editions and
  stickers; hover or briefly press a card for its live Balatro details popup.
- Change Joker editions: Base, Foil, Holographic, Polychrome, and Negative.
- Toggle Eternal, Perishable, and Rental stickers.
- Inspect and adjust numeric values on individual Joker instances with
  per-stat steps derived from each Joker's defaults.
- Browse held Tarot, Planet, and Spectral cards as live, interactive cards;
  add exact consumables by type and edit their edition or safe per-instance
  numeric values. Consumables remain removable through Balatro's normal Sell
  action.
- Browse every playing card in the run, even while cards are split between the
  deck, hand, discard, and play areas.
- Add exact playing cards by suit, remove cards, and edit rank, suit,
  enhancement, edition, and seal through Balatro's native card APIs.
- Enter deck selection mode to pick individual cards, the visible page, or the
  whole deck, then bulk-edit the selected scope.
- Apply a rank, suit, enhancement, edition, or seal directly to every bulk
  target, or remove the batch through a separate confirmation step.
- Hold numeric `-` or `+` controls for a bounded 10-actions-per-second repeat.
- Drag the compact `BALALAIO` launcher to a convenient screen position.
- Save mutations through Balatro's normal run-save path.

## In-game examples

| General run controls | Joker management |
| --- | --- |
| ![Balalaio General tab with controls for hands, discards, money, Jokers, and consumables](docs/screenshots/general-tab.jpeg) | ![Balalaio Jokers tab listing the Jokers in the current run](docs/screenshots/jokers-tab.jpeg) |

| Editing a Negative Blue Joker | Editing Yorick's instance values |
| --- | --- |
| ![Balalaio editor showing a Negative Blue Joker and its numeric values](docs/screenshots/editing-negative-blue-joker.jpeg) | ![Balalaio editor showing Yorick's edition, stickers, and numeric values](docs/screenshots/editing-yorick.jpeg) |

## One-click Windows installation

Requirements:

- Balatro installed through Steam on Windows.
- An internet connection for the first installation.
- Balatro completely closed while the installer runs.

Download and extract this repository, then double-click:

```text
install.bat
```

The installer:

1. Detects Balatro from Steam's registry entries, default folder, and additional
   Steam libraries.
2. Opens a folder picker if it cannot find the game automatically.
3. Downloads the latest published Windows release of Lovely.
4. Downloads the latest published Steamodded release.
5. Installs Balalaio to `%APPDATA%\Balatro\Mods\Balalaio`.
6. Moves any replaced loader or mod folders to
   `%APPDATA%\Balatro\Balalaio Backups` first.

It does **not** touch profiles or saves under `%APPDATA%\Balatro\1`.

To run it from PowerShell instead:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Useful alternatives:

```powershell
# Always choose the folder containing Balatro.exe
.\install.ps1 -ChooseGameFolder

# Supply a non-default Steam library directly
.\install.ps1 -GamePath "D:\SteamLibrary\steamapps\common\Balatro"

# Install only Balalaio when Lovely and Steamodded are already managed separately
.\install.ps1 -SkipDependencies

# Use already-downloaded official release archives
.\install.ps1 -LovelyArchivePath .\lovely-windows.zip `
  -SteamoddedArchivePath .\steamodded.zip
```

If Windows denies access to the Steam game folder, right-click `install.bat` and
choose **Run as administrator**.

### First launch

Launch Balatro normally through Steam. Lovely should open a second console
window, and Steamodded should show Balalaio in its Mods menu. Start or continue
a run; the movable `BALALAIO` launcher appears during active gameplay.

Lovely is an open-source runtime injector, so security software can occasionally
flag it heuristically. The installer never disables antivirus or adds
exclusions. See Steamodded's
[official Windows guide](https://github.com/Steamodded/smods/wiki/Installing-Steamodded-windows)
if `version.dll` is quarantined.

## Manual installation

Use the standard layout documented by
[Lovely](https://github.com/ethangreen-dev/lovely-injector#manual-installation)
and Steamodded:

```text
<Steam library>\steamapps\common\Balatro\
  Balatro.exe
  version.dll

%APPDATA%\Balatro\Mods\
  smods\
    lovely\
    src\
    version.lua
    ...
  Balalaio\
    Balalaio.json
    balalaio.lua
```

1. Put Lovely's Windows x64 `version.dll` beside `Balatro.exe`.
2. Extract Steamodded so its loader files are directly inside `Mods\smods`.
3. Copy this repository's complete [`Balalaio/`](Balalaio/) folder into
   `%APPDATA%\Balatro\Mods`.

Avoid copying the whole repository into `Mods`; only the install-ready
`Balalaio` folder belongs there.

## Compatibility

- Platform: Balatro Steam for Windows.
- Tested game version: `1.0.1o-FULL` (revision `1.0.1o`).
- Mod loader: Steamodded `1.0.0` beta line or newer.
- Runtime injector: Lovely `0.9.0` or newer.

`Balalaio.json` deliberately pins the full tested Balatro version because the panel
uses internal game APIs. If Balatro updates, Steamodded will refuse to load
Balalaio instead of risking a broken save or startup crash until compatibility
is verified.

Steamodded currently supports the Steam release of Balatro on Windows; the
Microsoft Store build is not supported.

## Updating and uninstalling

For a Balalaio-only update, extract the Windows updater package, close Balatro,
and double-click:

```text
update.bat
```

The updater leaves Lovely and Steamodded unchanged, backs up the currently
installed Balalaio folder, and replaces it with the packaged version. Run
`install.bat` instead when you also want to refresh Lovely and Steamodded.
Existing copies are backed up outside `Mods` so Steamodded cannot discover
duplicate loaders.

To remove only Balalaio, delete:

```text
%APPDATA%\Balatro\Mods\Balalaio
```

To remove the mod loader entirely, also delete `version.dll` beside
`Balatro.exe` and the `smods` folder. Other Steamodded mods will stop working.

## Patching an Android APK

Balalaio includes a source-only builder that injects the mod into a compatible
Balatro Android APK, preserves the original application identity and native
libraries, then aligns, signs, and verifies the resulting package. The builder
does not download or distribute Balatro itself.

### Requirements

- Windows PowerShell 5.1 or PowerShell 7+.
- Java available through the `java` command. Confirm with `java -version`.
- A legally obtained, self-contained Balatro Android APK for the supported
  `1.0.1o-FULL [M]` mobile wrapper.
- An internet connection on the first build so the script can download the
  checksum-pinned APK signer. Later builds reuse the copy under `.tools\`.

The input must be a complete APK containing `assets/main.lua` and packaged
native libraries. A Play Store `base.apk` split by itself is incomplete. The
builder also rejects Pairip-protected or encrypted wrappers because Balalaio
does not remove or bypass licensing, integrity, or anti-tamper systems.

### 1. Prepare the input APK

Open the repository root—the folder containing `scripts`, `Balalaio`, and
`package.json`. Create `local-input` if it does not already exist, then place
your APK at:

```text
Balalaio repository
├─ Balalaio\
├─ scripts\
├─ local-input\
│  └─ BalatroLatest.apk
└─ README.md
```

`local-input\`, all APK files, signing material, extracted game files, and
generated packages are excluded by `.gitignore`.

### 2. Build the patched APK

Open PowerShell in the repository root and run:

```powershell
java -version
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build.ps1
```

The default build reads `local-input\BalatroLatest.apk` and writes:

```text
dist\Balalaio.apk
```

During the build, the script:

1. Verifies the package ID, wrapper layout, game script hash, and native
   libraries.
2. Adds `assets/balalaio.lua` and a version marker.
3. Adds Balalaio's startup `require` to `assets/main.lua` once.
4. Preserves the manifest, package name, app name, icons, resources, DEX, and
   native-library identity.
5. Downloads and checksum-verifies `uber-apk-signer` when needed.
6. Zip-aligns, signs, and verifies the APK with v1, v2, and v3 signatures.

A successful build ends with the output path, byte size, SHA-256 digest,
detected game version, native-library count, and signature-verification result.

### 3. Use custom input and output paths

You do not need to rename the source APK. Supply explicit paths instead:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build.ps1 `
  -InputApk "D:\Backups\BalatroLatest.apk" `
  -OutputApk ".\dist\Balalaio-v0.4.0.apk"
```

If a newer game build has been reviewed and confirmed compatible, developers
can pass `-AllowUnknownVersion`. Do not use `-AllowUnsupportedWrapper` to work
around license or integrity protection; obtain a compatible self-contained APK
instead.

### 4. Choose a signing strategy

Without signing options, the builder uses the signer's embedded Android debug
certificate. APK updates require the same package ID **and** signing
certificate, so an APK signed this way cannot update an official installation
or a build signed with another key. Back up any saves you care about before
uninstalling an existing app, because Android normally removes its app data.

For repeatable personal builds, provide your own keystore and keep it safe:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build.ps1 `
  -Keystore "D:\Keys\balalaio-release.jks" `
  -KeystoreAlias "balalaio"
```

The signer may request the keystore credentials. The optional
`-KeystorePassword` and `-KeyPassword` arguments are also supported, but be
aware that command-line passwords can remain in shell history. Losing the
keystore prevents future APKs from updating installations signed with it.

### 5. Install and test

Transfer `dist\Balalaio.apk` to the Android device, allow installation from the
chosen file-manager source, and open the APK. With Android Debug Bridge, the
equivalent update command is:

```powershell
adb install -r .\dist\Balalaio.apk
```

If Android reports a signature conflict, the installed copy was signed with a
different certificate. Back up its data, uninstall it, then install the new
APK. After launch, start or continue a run and confirm that the movable
`BALALAIO 0.4.0` button appears.

### Troubleshooting

| Message or symptom | What to check |
| --- | --- |
| `Input APK was not found` | Confirm the filename is exactly `local-input\BalatroLatest.apk`, or pass `-InputApk`. |
| `Input package is not com.playstack.balatro.android` | The selected file is not the expected Balatro Android package. |
| Missing `assets/main.lua` or native libraries | Obtain the complete standalone APK rather than only a Play split. |
| `Unsupported Android wrapper` | Use a compatible unprotected wrapper; the builder does not bypass Pairip or encrypted assets. |
| Unsupported `assets/main.lua` hash | The game version differs from the tested build. Review compatibility before using `-AllowUnknownVersion`. |
| Java or signer download failure | Check `java -version`, internet access, security-software quarantine, and the `.tools\` directory. |
| Android refuses to update the app | The installed app and new APK were signed by different certificates; back up data before reinstalling. |

Patched APKs contain copyrighted game files and are for the owner's personal
use. Do not commit or redistribute the input or generated APK.

## Development

Requirements:

- Node.js 22 or newer.
- Windows PowerShell 5.1 or PowerShell 7+.

Run the full local suite:

```powershell
npm ci
npm test
```

Build the self-contained Windows updater archive:

```powershell
.\scripts\package-updater.ps1
```

The resulting versioned archive is written to
`dist\Balalaio-Windows-Updater-v0.5.0.zip`. Its version is read from
`Balalaio\Balalaio.json`, so later releases receive the matching filename
automatically.

The suite checks Lua 5.1 parsing, Steamodded metadata, reload safety, isolated
native card previews, mocked Joker/consumable/deck mutations, the real Balatro
input path when user-owned extracted assets are available, a sandboxed
installer fixture, and the legacy APK injection path.

For Android build inputs, signing choices, custom paths, installation, and
troubleshooting, follow [Patching an Android APK](#patching-an-android-apk).

For versioned 0.5.0 release artifacts, keep the updater's generated name and
give the APK an explicit output name:

```powershell
.\scripts\package-updater.ps1
.\scripts\build.ps1 -OutputApk .\dist\Balalaio-v0.5.0.apk
```

The combined download archive is
`dist\Balalaio-v0.5.0-Windows-Android.zip`; it contains those two generated
files: the Windows updater ZIP and `Balalaio-v0.5.0.apk`. For later releases,
substitute the current metadata version in the APK and combined-archive names.

## Project boundaries

This repository contains original Balalaio source, installer/build scripts,
tests, and user-provided screenshots. It does not contain Balatro, extracted
game assets, Lovely or Steamodded binaries, signing keys, or APK files. Balatro
and its assets belong to their respective rights holders.

Balalaio is released under the [MIT License](LICENSE).
