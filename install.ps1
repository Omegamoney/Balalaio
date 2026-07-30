#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
param(
    [string]$GamePath,
    [string]$ModsPath = "$env:APPDATA\Balatro\Mods",
    [switch]$ChooseGameFolder,
    [switch]$SkipDependencies,
    [switch]$NoPrompt,
    [string]$LovelyArchivePath,
    [string]$SteamoddedArchivePath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$script:GitHubHeaders = @{
    Accept = "application/vnd.github+json"
    "User-Agent" = "Balalaio-Installer"
}

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Test-BalatroDirectory {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    try {
        $fullPath = [System.IO.Path]::GetFullPath(
            [Environment]::ExpandEnvironmentVariables($Path)
        )
    }
    catch {
        return $false
    }

    return Test-Path -LiteralPath (Join-Path $fullPath "Balatro.exe") -PathType Leaf
}

function Select-BalatroDirectory {
    param([string]$InitialPath)

    try {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = "Select the folder containing Balatro.exe"
        $dialog.ShowNewFolderButton = $false
        if (Test-Path -LiteralPath $InitialPath -PathType Container) {
            $dialog.SelectedPath = $InitialPath
        }

        try {
            if (
                $dialog.ShowDialog() -eq
                [System.Windows.Forms.DialogResult]::OK
            ) {
                return $dialog.SelectedPath
            }
        }
        finally {
            $dialog.Dispose()
        }
    }
    catch {
        throw "Could not open the folder picker. Pass -GamePath 'C:\path\to\Balatro' instead. $($_.Exception.Message)"
    }

    throw "No Balatro folder was selected."
}

function Get-DetectedBalatroDirectories {
    $candidates = New-Object System.Collections.Generic.List[string]
    $steamRoots = New-Object System.Collections.Generic.List[string]

    $uninstallKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 2379780",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 2379780"
    )
    foreach ($key in $uninstallKeys) {
        try {
            $location = (Get-ItemProperty -LiteralPath $key).InstallLocation
            if (-not [string]::IsNullOrWhiteSpace($location)) {
                $candidates.Add([string]$location)
            }
        }
        catch {
            # Steam does not always create an uninstall entry.
        }
    }

    $steamKeys = @(
        @{ Path = "HKCU:\Software\Valve\Steam"; Name = "SteamPath" },
        @{ Path = "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam"; Name = "InstallPath" },
        @{ Path = "HKLM:\SOFTWARE\Valve\Steam"; Name = "InstallPath" }
    )
    foreach ($entry in $steamKeys) {
        try {
            $root = (Get-ItemProperty -LiteralPath $entry.Path).($entry.Name)
            if (
                -not [string]::IsNullOrWhiteSpace($root) -and
                -not $steamRoots.Contains([string]$root)
            ) {
                $steamRoots.Add([string]$root)
            }
        }
        catch {
            # Try the remaining registry and filesystem locations.
        }
    }

    foreach ($root in @(
        "${env:ProgramFiles(x86)}\Steam",
        "$env:ProgramFiles\Steam"
    )) {
        if (
            -not [string]::IsNullOrWhiteSpace($root) -and
            -not $steamRoots.Contains($root)
        ) {
            $steamRoots.Add($root)
        }
    }

    foreach ($steamRoot in @($steamRoots)) {
        $libraryFile = Join-Path $steamRoot "steamapps\libraryfolders.vdf"
        if (-not (Test-Path -LiteralPath $libraryFile -PathType Leaf)) {
            continue
        }

        try {
            $libraryText = Get-Content -Raw -LiteralPath $libraryFile
            foreach (
                $match in [regex]::Matches(
                    $libraryText,
                    '"path"\s+"([^"]+)"'
                )
            ) {
                $libraryRoot = $match.Groups[1].Value.Replace("\\", "\")
                if (
                    -not [string]::IsNullOrWhiteSpace($libraryRoot) -and
                    -not $steamRoots.Contains($libraryRoot)
                ) {
                    $steamRoots.Add($libraryRoot)
                }
            }
        }
        catch {
            Write-Warning "Could not read Steam library list at '$libraryFile'."
        }
    }

    foreach ($steamRoot in $steamRoots) {
        $installDirectoryName = "Balatro"
        $manifestPath = Join-Path $steamRoot "steamapps\appmanifest_2379780.acf"
        if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
            try {
                $manifestText = Get-Content -Raw -LiteralPath $manifestPath
                $installMatch = [regex]::Match(
                    $manifestText,
                    '"installdir"\s+"([^"]+)"'
                )
                if ($installMatch.Success) {
                    $installDirectoryName = $installMatch.Groups[1].Value
                }
            }
            catch {
                Write-Warning "Could not read '$manifestPath'."
            }
        }

        $commonPath = Join-Path $steamRoot "steamapps\common"
        $candidates.Add((Join-Path $commonPath $installDirectoryName))
    }

    $seen = @{}
    foreach ($candidate in $candidates) {
        try {
            $fullPath = [System.IO.Path]::GetFullPath(
                [Environment]::ExpandEnvironmentVariables($candidate)
            )
        }
        catch {
            continue
        }

        if (-not $seen.ContainsKey($fullPath)) {
            $seen[$fullPath] = $true
            if (Test-BalatroDirectory -Path $fullPath) {
                $fullPath
            }
        }
    }
}

function Resolve-BalatroDirectory {
    param(
        [string]$RequestedPath,
        [bool]$AlwaysChoose,
        [bool]$DisablePrompt
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        if (-not (Test-BalatroDirectory -Path $RequestedPath)) {
            throw "The selected game folder does not contain Balatro.exe: '$RequestedPath'."
        }
        return [System.IO.Path]::GetFullPath($RequestedPath)
    }

    $defaultPath = "${env:ProgramFiles(x86)}\Steam\steamapps\common\Balatro"
    if ($AlwaysChoose) {
        if ($DisablePrompt) {
            throw "-ChooseGameFolder cannot be combined with -NoPrompt."
        }
        $selected = Select-BalatroDirectory -InitialPath $defaultPath
        if (-not (Test-BalatroDirectory -Path $selected)) {
            throw "The selected folder does not contain Balatro.exe: '$selected'."
        }
        return [System.IO.Path]::GetFullPath($selected)
    }

    $detected = @(Get-DetectedBalatroDirectories)
    if ($detected.Count -gt 0) {
        return $detected[0]
    }

    if ($DisablePrompt) {
        throw "Balatro was not detected. Rerun with -GamePath 'C:\path\to\Balatro'."
    }

    $selected = Select-BalatroDirectory -InitialPath $defaultPath
    if (-not (Test-BalatroDirectory -Path $selected)) {
        throw "The selected folder does not contain Balatro.exe: '$selected'."
    }
    return [System.IO.Path]::GetFullPath($selected)
}

function Get-LatestPublishedRelease {
    param(
        [string]$Owner,
        [string]$Repository
    )

    $uri = "https://api.github.com/repos/$Owner/$Repository/releases/latest"
    try {
        $release = Invoke-RestMethod -Uri $uri -Headers $script:GitHubHeaders
    }
    catch {
        throw "Could not query releases for $Owner/$Repository. Check your internet connection. $($_.Exception.Message)"
    }

    if ($null -eq $release -or $release.draft) {
        throw "No published release was found for $Owner/$Repository."
    }
    return $release
}

function Download-File {
    param(
        [string]$Uri,
        [string]$Destination,
        [string]$Label
    )

    Write-Host "Downloading $Label..."
    try {
        Invoke-WebRequest `
            -UseBasicParsing `
            -Uri $Uri `
            -Headers $script:GitHubHeaders `
            -OutFile $Destination
    }
    catch {
        throw "Could not download $Label. Check your internet connection. $($_.Exception.Message)"
    }

    if (
        -not (Test-Path -LiteralPath $Destination -PathType Leaf) -or
        (Get-Item -LiteralPath $Destination).Length -eq 0
    ) {
        throw "The $Label download was empty."
    }
}

function Assert-SafeModDestination {
    param(
        [string]$Destination,
        [string]$ModsRoot,
        [string]$ExpectedLeaf
    )

    $fullDestination = [System.IO.Path]::GetFullPath($Destination)
    $fullModsRoot = [System.IO.Path]::GetFullPath($ModsRoot).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar
    )
    $requiredPrefix = $fullModsRoot + [System.IO.Path]::DirectorySeparatorChar

    if (
        -not $fullDestination.StartsWith(
            $requiredPrefix,
            [System.StringComparison]::OrdinalIgnoreCase
        ) -or
        (Split-Path -Leaf $fullDestination) -ne $ExpectedLeaf
    ) {
        throw "Refusing unsafe mod destination '$fullDestination'."
    }
}

function Copy-DirectoryContents {
    param(
        [string]$Source,
        [string]$Destination
    )

    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Copy-Item `
        -Path (Join-Path $Source "*") `
        -Destination $Destination `
        -Recurse `
        -Force
}

function Replace-DirectoryWithBackup {
    param(
        [string]$Source,
        [string]$Destination,
        [string]$ExistingPath,
        [string]$BackupPath
    )

    $hadExisting = -not [string]::IsNullOrWhiteSpace($ExistingPath) -and
        (Test-Path -LiteralPath $ExistingPath -PathType Container)

    if ($hadExisting) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $BackupPath) |
            Out-Null
        Move-Item -LiteralPath $ExistingPath -Destination $BackupPath
    }

    try {
        Copy-DirectoryContents -Source $Source -Destination $Destination
    }
    catch {
        if (Test-Path -LiteralPath $Destination -PathType Container) {
            Remove-Item -LiteralPath $Destination -Recurse -Force
        }
        if ($hadExisting -and (Test-Path -LiteralPath $BackupPath)) {
            Move-Item -LiteralPath $BackupPath -Destination $ExistingPath
        }
        throw
    }
}

function Restore-DirectoryReplacement {
    param(
        [string]$Destination,
        [string]$ExistingPath,
        [string]$BackupPath
    )

    if (Test-Path -LiteralPath $Destination -PathType Container) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    if (
        -not [string]::IsNullOrWhiteSpace($ExistingPath) -and
        (Test-Path -LiteralPath $BackupPath -PathType Container)
    ) {
        New-Item `
            -ItemType Directory `
            -Force `
            -Path (Split-Path -Parent $ExistingPath) |
            Out-Null
        Move-Item -LiteralPath $BackupPath -Destination $ExistingPath
    }
}

function Find-SteamoddedDirectories {
    param([string]$Root)

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        return
    }

    foreach (
        $directory in Get-ChildItem -LiteralPath $Root -Directory -Force
    ) {
        if (
            (Test-Path -LiteralPath (Join-Path $directory.FullName "src\core.lua")) -and
            (Test-Path -LiteralPath (Join-Path $directory.FullName "lovely") -PathType Container)
        ) {
            $directory.FullName
        }
    }
}

$sourceModDirectory = Join-Path $PSScriptRoot "Balalaio"
$metadataPath = Join-Path $sourceModDirectory "Balalaio.json"
$sourceLuaPath = Join-Path $sourceModDirectory "balalaio.lua"
if (
    -not (Test-Path -LiteralPath $metadataPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $sourceLuaPath -PathType Leaf)
) {
    throw "The installer must stay beside the repository's Balalaio folder."
}
if (
    $SkipDependencies -and
    (
        -not [string]::IsNullOrWhiteSpace($LovelyArchivePath) -or
        -not [string]::IsNullOrWhiteSpace($SteamoddedArchivePath)
    )
) {
    throw "Dependency archive paths cannot be combined with -SkipDependencies."
}

$resolvedGamePath = Resolve-BalatroDirectory `
    -RequestedPath $GamePath `
    -AlwaysChoose $ChooseGameFolder.IsPresent `
    -DisablePrompt $NoPrompt.IsPresent

if ([string]::IsNullOrWhiteSpace($ModsPath)) {
    throw "Could not resolve the Balatro Mods path. Pass -ModsPath explicitly."
}
$resolvedModsPath = [System.IO.Path]::GetFullPath(
    [Environment]::ExpandEnvironmentVariables($ModsPath)
)
$balalaioDestination = Join-Path $resolvedModsPath "Balalaio"
$steamoddedDestination = Join-Path $resolvedModsPath "smods"
Assert-SafeModDestination `
    -Destination $balalaioDestination `
    -ModsRoot $resolvedModsPath `
    -ExpectedLeaf "Balalaio"
Assert-SafeModDestination `
    -Destination $steamoddedDestination `
    -ModsRoot $resolvedModsPath `
    -ExpectedLeaf "smods"

Write-Host "Balatro : $resolvedGamePath"
Write-Host "Mods    : $resolvedModsPath"

$installAction = if ($SkipDependencies) {
    "Install Balalaio"
}
else {
    "Install Lovely, Steamodded, and Balalaio"
}
if (
    -not $PSCmdlet.ShouldProcess(
        "$resolvedGamePath and $resolvedModsPath",
        $installAction
    )
) {
    return
}

if (Get-Process -Name "Balatro" -ErrorAction SilentlyContinue) {
    throw "Balatro is running. Close the game, then run the installer again."
}

[Net.ServicePointManager]::SecurityProtocol =
    [Net.ServicePointManager]::SecurityProtocol -bor
    [Net.SecurityProtocolType]::Tls12

$tempBase = [System.IO.Path]::GetTempPath()
$tempRoot = Join-Path $tempBase ("Balalaio-" + [guid]::NewGuid().ToString("N"))
$backupSuffix = (Get-Date -Format "yyyyMMdd-HHmmss-fff") +
    "-" + [guid]::NewGuid().ToString("N").Substring(0, 8)
$backupRoot = Join-Path (
    Split-Path -Parent $resolvedModsPath
) "Balalaio Backups\$backupSuffix"
$madeBackup = $false
$lovelyDestination = Join-Path $resolvedGamePath "version.dll"
$lovelyBackupPath = Join-Path $backupRoot "version.dll"
$lovelyTouched = $false
$lovelyHadExisting = $false
$steamoddedInstalled = $false
$existingSteamoddedPath = $null
$balalaioInstalled = $false
$existingBalalaio = $null

New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

try {
    $lovelyDll = $null
    $steamoddedSource = $null

    if (-not $SkipDependencies) {
        Write-Step "Preparing Lovely"
        $lovelyZip = Join-Path $tempRoot "lovely.zip"
        $lovelyExtract = Join-Path $tempRoot "lovely"
        if (-not [string]::IsNullOrWhiteSpace($LovelyArchivePath)) {
            if (
                -not (Test-Path -LiteralPath $LovelyArchivePath -PathType Leaf)
            ) {
                throw "Lovely archive not found: '$LovelyArchivePath'."
            }
            Copy-Item `
                -LiteralPath $LovelyArchivePath `
                -Destination $lovelyZip `
                -Force
        }
        else {
            $lovelyRelease = Get-LatestPublishedRelease `
                -Owner "ethangreen-dev" `
                -Repository "lovely-injector"
            $lovelyAsset = @($lovelyRelease.assets) |
                Where-Object {
                    $_.name -eq "lovely-x86_64-pc-windows-msvc.zip"
                } |
                Select-Object -First 1
            if ($null -eq $lovelyAsset) {
                throw "Lovely release '$($lovelyRelease.tag_name)' has no Windows x64 archive."
            }
            Download-File `
                -Uri $lovelyAsset.browser_download_url `
                -Destination $lovelyZip `
                -Label "Lovely $($lovelyRelease.tag_name)"
        }
        Expand-Archive `
            -LiteralPath $lovelyZip `
            -DestinationPath $lovelyExtract `
            -Force
        $lovelyDll = Get-ChildItem `
            -LiteralPath $lovelyExtract `
            -Filter "version.dll" `
            -File `
            -Recurse |
            Select-Object -First 1
        if ($null -eq $lovelyDll) {
            throw "The Lovely archive did not contain version.dll."
        }

        Write-Step "Preparing Steamodded"
        $steamoddedZip = Join-Path $tempRoot "steamodded.zip"
        $steamoddedExtract = Join-Path $tempRoot "steamodded"
        if (-not [string]::IsNullOrWhiteSpace($SteamoddedArchivePath)) {
            if (
                -not (
                    Test-Path `
                        -LiteralPath $SteamoddedArchivePath `
                        -PathType Leaf
                )
            ) {
                throw "Steamodded archive not found: '$SteamoddedArchivePath'."
            }
            Copy-Item `
                -LiteralPath $SteamoddedArchivePath `
                -Destination $steamoddedZip `
                -Force
        }
        else {
            $steamoddedRelease = Get-LatestPublishedRelease `
                -Owner "Steamodded" `
                -Repository "smods"
            Download-File `
                -Uri $steamoddedRelease.zipball_url `
                -Destination $steamoddedZip `
                -Label "Steamodded $($steamoddedRelease.tag_name)"
        }
        Expand-Archive `
            -LiteralPath $steamoddedZip `
            -DestinationPath $steamoddedExtract `
            -Force
        $steamoddedSource = Get-ChildItem `
            -LiteralPath $steamoddedExtract `
            -Directory |
            Where-Object {
                (Test-Path -LiteralPath (Join-Path $_.FullName "src\core.lua")) -and
                (Test-Path -LiteralPath (Join-Path $_.FullName "lovely") -PathType Container) -and
                (Test-Path -LiteralPath (Join-Path $_.FullName "version.lua") -PathType Leaf)
            } |
            Select-Object -First 1
        if ($null -eq $steamoddedSource) {
            throw "The Steamodded archive did not contain the expected loader files."
        }
    }

    New-Item -ItemType Directory -Force -Path $resolvedModsPath | Out-Null

    if (-not $SkipDependencies) {
        Write-Step "Installing Lovely"
        $lovelyHadExisting =
            Test-Path -LiteralPath $lovelyDestination -PathType Leaf
        if ($lovelyHadExisting) {
            New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
            Copy-Item `
                -LiteralPath $lovelyDestination `
                -Destination $lovelyBackupPath `
                -Force
            $madeBackup = $true
        }
        $lovelyTouched = $true
        try {
            Copy-Item `
                -LiteralPath $lovelyDll.FullName `
                -Destination $lovelyDestination `
                -Force
        }
        catch [System.UnauthorizedAccessException] {
            throw "Windows denied access to '$resolvedGamePath'. Rerun install.bat as administrator."
        }
        if (
            -not (Test-Path -LiteralPath $lovelyDestination -PathType Leaf) -or
            (Get-FileHash -Algorithm SHA256 -LiteralPath $lovelyDestination).Hash -ne
            (Get-FileHash -Algorithm SHA256 -LiteralPath $lovelyDll.FullName).Hash
        ) {
            throw "Lovely's version.dll could not be verified after installation."
        }

        Write-Step "Installing Steamodded"
        $existingSteamodded = @(Find-SteamoddedDirectories -Root $resolvedModsPath)
        if ($existingSteamodded.Count -gt 1) {
            throw "Multiple Steamodded installations were found in '$resolvedModsPath'. Keep one loader folder and rerun the installer."
        }
        if (Test-Path -LiteralPath $steamoddedDestination) {
            $recognizedDestination = $existingSteamodded.Count -eq 1 -and
                [System.IO.Path]::GetFullPath($existingSteamodded[0]) -eq
                [System.IO.Path]::GetFullPath($steamoddedDestination)
            if (-not $recognizedDestination) {
                throw "The '$steamoddedDestination' folder exists but is not the detected Steamodded installation."
            }
        }

        $existingSteamoddedPath = if ($existingSteamodded.Count -eq 1) {
            $existingSteamodded[0]
        }
        else {
            $null
        }
        if ($null -ne $existingSteamoddedPath) {
            $madeBackup = $true
        }
        Replace-DirectoryWithBackup `
            -Source $steamoddedSource.FullName `
            -Destination $steamoddedDestination `
            -ExistingPath $existingSteamoddedPath `
            -BackupPath (Join-Path $backupRoot "smods")
        $steamoddedInstalled = $true
    }

    Write-Step "Installing Balalaio"
    $existingBalalaio = if (
        Test-Path -LiteralPath $balalaioDestination -PathType Container
    ) {
        $madeBackup = $true
        $balalaioDestination
    }
    else {
        $null
    }
    Replace-DirectoryWithBackup `
        -Source $sourceModDirectory `
        -Destination $balalaioDestination `
        -ExistingPath $existingBalalaio `
        -BackupPath (Join-Path $backupRoot "Balalaio")
    $balalaioInstalled = $true

    if (
        -not (Test-Path -LiteralPath (
            Join-Path $balalaioDestination "Balalaio.json"
        ) -PathType Leaf) -or
        -not (Test-Path -LiteralPath (
            Join-Path $balalaioDestination "balalaio.lua"
        ) -PathType Leaf)
    ) {
        throw "Balalaio could not be verified after installation."
    }

    Write-Host "`nBalalaio installation complete." -ForegroundColor Green
    if (-not $SkipDependencies) {
        Write-Host "Lovely     : $(Join-Path $resolvedGamePath 'version.dll')"
        Write-Host "Steamodded : $steamoddedDestination"
    }
    Write-Host "Balalaio   : $balalaioDestination"
    if ($madeBackup) {
        Write-Host "Backups    : $backupRoot"
    }
    Write-Host "`nLaunch Balatro through Steam. Steamodded should list Balalaio in its Mods menu."
}
catch {
    $installationError = $_
    Write-Warning "Installation failed; restoring the previous setup."

    if ($balalaioInstalled) {
        try {
            Restore-DirectoryReplacement `
                -Destination $balalaioDestination `
                -ExistingPath $existingBalalaio `
                -BackupPath (Join-Path $backupRoot "Balalaio")
        }
        catch {
            Write-Warning "Could not roll back Balalaio: $($_.Exception.Message)"
        }
    }

    if ($steamoddedInstalled) {
        try {
            Restore-DirectoryReplacement `
                -Destination $steamoddedDestination `
                -ExistingPath $existingSteamoddedPath `
                -BackupPath (Join-Path $backupRoot "smods")
        }
        catch {
            Write-Warning "Could not roll back Steamodded: $($_.Exception.Message)"
        }
    }

    if ($lovelyTouched) {
        try {
            if (
                $lovelyHadExisting -and
                (Test-Path -LiteralPath $lovelyBackupPath -PathType Leaf)
            ) {
                Copy-Item `
                    -LiteralPath $lovelyBackupPath `
                    -Destination $lovelyDestination `
                    -Force
            }
            elseif (Test-Path -LiteralPath $lovelyDestination -PathType Leaf) {
                Remove-Item -LiteralPath $lovelyDestination -Force
            }
        }
        catch {
            Write-Warning "Could not roll back Lovely: $($_.Exception.Message)"
        }
    }

    throw $installationError
}
finally {
    $fullTempRoot = [System.IO.Path]::GetFullPath($tempRoot)
    $fullTempBase = [System.IO.Path]::GetFullPath($tempBase)
    if (
        $fullTempRoot.StartsWith(
            $fullTempBase,
            [System.StringComparison]::OrdinalIgnoreCase
        ) -and
        (Test-Path -LiteralPath $fullTempRoot)
    ) {
        Remove-Item -LiteralPath $fullTempRoot -Recurse -Force
    }
}
