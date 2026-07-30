$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        throw $Message
    }
}

function Set-TestFile {
    param(
        [string]$Path,
        [string]$Value
    )

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) |
        Out-Null
    Set-Content -LiteralPath $Path -Value $Value -Encoding Ascii
}

function New-SyntheticDependencyArchives {
    param([string]$Root)

    $lovelyPayload = Join-Path $Root "lovely-payload"
    $lovelyZip = Join-Path $Root "lovely.zip"
    Set-TestFile `
        -Path (Join-Path $lovelyPayload "version.dll") `
        -Value "synthetic lovely 0.9.0"
    Compress-Archive `
        -Path (Join-Path $lovelyPayload "*") `
        -DestinationPath $lovelyZip `
        -Force

    $steamoddedParent = Join-Path $Root "steamodded-payload"
    $steamoddedPayload = Join-Path $steamoddedParent "Steamodded-smods-test"
    Set-TestFile `
        -Path (Join-Path $steamoddedPayload "src\core.lua") `
        -Value "synthetic current Steamodded core"
    Set-TestFile `
        -Path (Join-Path $steamoddedPayload "lovely\core.toml") `
        -Value "[manifest]"
    Set-TestFile `
        -Path (Join-Path $steamoddedPayload "version.lua") `
        -Value 'return "1.0.0~BETA-TEST"'
    $steamoddedZip = Join-Path $Root "steamodded.zip"
    Compress-Archive `
        -Path (Join-Path $steamoddedParent "*") `
        -DestinationPath $steamoddedZip `
        -Force

    return @{
        Lovely = $lovelyZip
        Steamodded = $steamoddedZip
    }
}

function New-OldSteamodded {
    param(
        [string]$Path,
        [string]$Marker
    )

    Set-TestFile `
        -Path (Join-Path $Path "src\core.lua") `
        -Value "$Marker core"
    Set-TestFile `
        -Path (Join-Path $Path "lovely\core.toml") `
        -Value "[manifest]"
    Set-TestFile `
        -Path (Join-Path $Path "version.lua") `
        -Value "return '$Marker'"
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$installer = Join-Path $repoRoot "install.ps1"
$testRoot = Join-Path (
    [System.IO.Path]::GetTempPath()
) ("balalaio-installer-test-" + [guid]::NewGuid().ToString("N"))
$gamePath = Join-Path $testRoot "Steam\steamapps\common\Balatro"
$modsPath = Join-Path $testRoot "AppData\Balatro\Mods"
$whatIfModsPath = Join-Path $testRoot "WhatIf\Mods"

try {
    $archives = New-SyntheticDependencyArchives `
        -Root (Join-Path $testRoot "Dependencies")

    Set-TestFile `
        -Path (Join-Path $gamePath "Balatro.exe") `
        -Value "synthetic test executable"

    & $installer `
        -GamePath $gamePath `
        -ModsPath $whatIfModsPath `
        -SkipDependencies `
        -NoPrompt `
        -WhatIf
    Assert-True `
        -Condition (-not (Test-Path -LiteralPath $whatIfModsPath)) `
        -Message "The installer wrote files during -WhatIf."

    Set-TestFile `
        -Path (Join-Path $gamePath "version.dll") `
        -Value "previous lovely"
    New-OldSteamodded `
        -Path (Join-Path $modsPath "smods") `
        -Marker "previous Steamodded"
    Set-TestFile `
        -Path (Join-Path $modsPath "Balalaio\balalaio.lua") `
        -Value "previous Balalaio"
    Set-TestFile `
        -Path (Join-Path $modsPath "Balalaio\Balalaio.json") `
        -Value "{}"

    & $installer `
        -GamePath $gamePath `
        -ModsPath $modsPath `
        -LovelyArchivePath $archives.Lovely `
        -SteamoddedArchivePath $archives.Steamodded `
        -NoPrompt

    $installedDirectory = Join-Path $modsPath "Balalaio"
    $installedMetadata = Join-Path $installedDirectory "Balalaio.json"
    $installedLua = Join-Path $installedDirectory "balalaio.lua"
    Assert-True `
        -Condition (Test-Path -LiteralPath $installedMetadata -PathType Leaf) `
        -Message "Balalaio.json was not installed."
    Assert-True `
        -Condition (Test-Path -LiteralPath $installedLua -PathType Leaf) `
        -Message "balalaio.lua was not installed."
    Assert-True `
        -Condition (
            (Get-Content -Raw -LiteralPath (
                Join-Path $gamePath "version.dll"
            )) -match "synthetic lovely 0.9.0"
        ) `
        -Message "Lovely was not installed from the staged archive."
    Assert-True `
        -Condition (
            (Get-Content -Raw -LiteralPath (
                Join-Path $modsPath "smods\src\core.lua"
            )) -match "synthetic current Steamodded core"
        ) `
        -Message "Steamodded was not installed from the staged archive."

    $metadata = Get-Content -Raw -LiteralPath $installedMetadata |
        ConvertFrom-Json
    Assert-True `
        -Condition ($metadata.main_file -eq "balalaio.lua") `
        -Message "Installed metadata points at the wrong entry file."

    $backupRoot = Join-Path (Split-Path -Parent $modsPath) "Balalaio Backups"
    foreach ($expectedBackupText in @(
        "previous lovely",
        "previous Steamodded core",
        "previous Balalaio"
    )) {
        $matchingBackup = Get-ChildItem `
            -LiteralPath $backupRoot `
            -File `
            -Recurse |
            Where-Object {
                (Get-Content -Raw -LiteralPath $_.FullName) -match
                [regex]::Escape($expectedBackupText)
            } |
            Select-Object -First 1
        Assert-True `
            -Condition ($null -ne $matchingBackup) `
            -Message "Missing backup containing '$expectedBackupText'."
    }

    Set-Content -LiteralPath $installedLua -Value "stale install"
    & $installer `
        -GamePath $gamePath `
        -ModsPath $modsPath `
        -SkipDependencies `
        -NoPrompt
    Assert-True `
        -Condition (
            (Get-Content -Raw -LiteralPath $installedLua) -match
            "local Balalaio"
        ) `
        -Message "A repeat installation did not refresh Balalaio."

    $backupLua = Get-ChildItem `
        -LiteralPath $backupRoot `
        -Filter "balalaio.lua" `
        -File `
        -Recurse |
        Where-Object {
            (Get-Content -Raw -LiteralPath $_.FullName) -match "stale install"
        } |
        Select-Object -First 1
    Assert-True `
        -Condition ($null -ne $backupLua) `
        -Message "A repeat installation did not back up the previous mod."

    $rollbackRoot = Join-Path $testRoot "Rollback"
    $rollbackGame = Join-Path $rollbackRoot "Game"
    $rollbackMods = Join-Path $rollbackRoot "Mods"
    Set-TestFile `
        -Path (Join-Path $rollbackGame "Balatro.exe") `
        -Value "synthetic test executable"
    Set-TestFile `
        -Path (Join-Path $rollbackGame "version.dll") `
        -Value "rollback lovely"
    New-OldSteamodded `
        -Path (Join-Path $rollbackMods "SteamoddedOld") `
        -Marker "rollback Steamodded"
    Set-TestFile `
        -Path (Join-Path $rollbackMods "smods\keep.txt") `
        -Value "unrelated smods contents"

    $rollbackFailedAsExpected = $false
    try {
        & $installer `
            -GamePath $rollbackGame `
            -ModsPath $rollbackMods `
            -LovelyArchivePath $archives.Lovely `
            -SteamoddedArchivePath $archives.Steamodded `
            -NoPrompt
    }
    catch {
        $rollbackFailedAsExpected = $true
    }
    Assert-True `
        -Condition $rollbackFailedAsExpected `
        -Message "The installer accepted an unrelated occupied smods folder."
    Assert-True `
        -Condition (
            (Get-Content -Raw -LiteralPath (
                Join-Path $rollbackGame "version.dll"
            )) -match "rollback lovely"
        ) `
        -Message "Lovely was not restored after a later install failure."
    Assert-True `
        -Condition (
            Test-Path -LiteralPath (
                Join-Path $rollbackMods "SteamoddedOld\src\core.lua"
            ) -PathType Leaf
        ) `
        -Message "The previous Steamodded directory was not preserved."
    Assert-True `
        -Condition (
            (Get-Content -Raw -LiteralPath (
                Join-Path $rollbackMods "smods\keep.txt"
            )) -match "unrelated smods contents"
        ) `
        -Message "The unrelated smods folder was modified."

    Write-Host "Steam installer tests passed."
}
finally {
    $fullTestRoot = [System.IO.Path]::GetFullPath($testRoot)
    $fullTempRoot = [System.IO.Path]::GetFullPath(
        [System.IO.Path]::GetTempPath()
    )
    if (
        $fullTestRoot.StartsWith(
            $fullTempRoot,
            [System.StringComparison]::OrdinalIgnoreCase
        ) -and
        (Test-Path -LiteralPath $fullTestRoot)
    ) {
        Remove-Item -LiteralPath $fullTestRoot -Recurse -Force
    }
}
