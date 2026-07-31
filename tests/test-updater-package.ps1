#Requires -Version 5.1

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

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$packager = Join-Path $repoRoot "scripts\package-updater.ps1"
$metadataPath = Join-Path $repoRoot "Balalaio\Balalaio.json"
$metadata = Get-Content -Raw -Encoding UTF8 -LiteralPath $metadataPath |
    ConvertFrom-Json
$version = ([string]$metadata.version).Trim()
$packageName = "Balalaio-Windows-Updater-v$version"
$testRoot = Join-Path (
    [System.IO.Path]::GetTempPath()
) ("balalaio-updater-test-" + [guid]::NewGuid().ToString("N"))

New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
    $firstResult = & $packager -OutputDirectory $testRoot
    $archivePath = Join-Path $testRoot "$packageName.zip"

    Assert-True `
        -Condition (Test-Path -LiteralPath $archivePath -PathType Leaf) `
        -Message "The updater package was not created."
    Assert-True `
        -Condition ($firstResult.Path -eq $archivePath) `
        -Message "The packager returned an unexpected output path."

    $firstHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
    $secondResult = & $packager -OutputDirectory $testRoot
    $secondHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
    Assert-True `
        -Condition ($firstHash -eq $secondHash) `
        -Message "Repeated updater builds are not deterministic."
    Assert-True `
        -Condition ($secondResult.Version -eq $version) `
        -Message "The packager returned an unexpected version."

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $expectedEntries = @(
        "$packageName/update.bat",
        "$packageName/install.bat",
        "$packageName/install.ps1",
        "$packageName/Balalaio/Balalaio.json",
        "$packageName/Balalaio/balalaio.lua"
    )

    $archive = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        $actualEntries = @($archive.Entries | ForEach-Object { $_.FullName })
        Assert-True `
            -Condition ($actualEntries.Count -eq $expectedEntries.Count) `
            -Message "The updater package contains an unexpected entry count."

        for ($index = 0; $index -lt $expectedEntries.Count; $index++) {
            Assert-True `
                -Condition (
                    $actualEntries[$index] -eq $expectedEntries[$index]
                ) `
                -Message (
                    "Unexpected updater entry at index {0}: '{1}'." -f
                    $index,
                    $actualEntries[$index]
                )
        }
    }
    finally {
        $archive.Dispose()
    }

    Write-Host "Updater package tests passed." -ForegroundColor Green
}
finally {
    $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
    $resolvedTempRoot = [System.IO.Path]::GetFullPath(
        [System.IO.Path]::GetTempPath()
    ).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    if (
        $resolvedTestRoot.StartsWith(
            $resolvedTempRoot + [System.IO.Path]::DirectorySeparatorChar,
            [System.StringComparison]::OrdinalIgnoreCase
        ) -and
        (Split-Path -Leaf $resolvedTestRoot).StartsWith(
            "balalaio-updater-test-",
            [System.StringComparison]::OrdinalIgnoreCase
        ) -and
        (Test-Path -LiteralPath $resolvedTestRoot -PathType Container)
    ) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
