[CmdletBinding()]
param(
    [Parameter()]
    [string]$InputApk = ".\Balatro-v1.8.apk",

    [Parameter()]
    [string]$OutputApk = ".\dist\Balalaio.apk",

    [Parameter()]
    [string]$SignerJar,

    [Parameter()]
    [string]$Java = "java",

    [Parameter()]
    [string]$Keystore,

    [Parameter()]
    [string]$KeystoreAlias,

    [Parameter()]
    [string]$KeystorePassword,

    [Parameter()]
    [string]$KeyPassword,

    [Parameter()]
    [switch]$AllowUnknownVersion,

    [Parameter()]
    [switch]$AllowUnsupportedWrapper,

    [Parameter()]
    [switch]$SkipSign,

    [Parameter()]
    [switch]$KeepWork
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$SignerVersion = "1.3.0"
$SignerSha256 = "E1299FD6FCF4DA527DD53735B56127E8EA922A321128123B9C32D619BBA1D835"
$SignerUrl = "https://github.com/patrickfav/uber-apk-signer/releases/download/v1.3.0/uber-apk-signer-1.3.0.jar"
$ExpectedPackageId = "com.playstack.balatro.android"
$SupportedMainSha256 = @(
    "362CC16E08841D527DFF3C1FA5A3FEEDB7107DF408FE4E2E680E1B4906E10F4C"
)

function Resolve-ExistingFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label was not found: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Resolve-OutputFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath(
        (Join-Path (Get-Location).Path $Path)
    )
}

function Read-ZipText {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Compression.ZipArchiveEntry]$Entry
    )

    $entryStream = $Entry.Open()
    try {
        $reader = New-Object System.IO.StreamReader(
            $entryStream,
            (New-Object System.Text.UTF8Encoding($false)),
            $true
        )
        try {
            return $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        $entryStream.Dispose()
    }
}

function Get-ZipEntrySha256 {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Compression.ZipArchiveEntry]$Entry
    )

    $entryStream = $Entry.Open()
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return (($sha.ComputeHash($entryStream) | ForEach-Object {
            $_.ToString("X2")
        }) -join "")
    }
    finally {
        $sha.Dispose()
        $entryStream.Dispose()
    }
}

function Test-ZipEntryContainsAscii {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Compression.ZipArchiveEntry]$Entry,

        [Parameter(Mandatory = $true)]
        [string]$Needle
    )

    $entryStream = $Entry.Open()
    $memory = New-Object System.IO.MemoryStream
    try {
        $entryStream.CopyTo($memory)
        $bytes = $memory.ToArray()
        $asciiText = [System.Text.Encoding]::ASCII.GetString($bytes)
        if ($asciiText.IndexOf(
            $Needle,
            [System.StringComparison]::Ordinal
        ) -ge 0) {
            return $true
        }
        $unicodeText = [System.Text.Encoding]::Unicode.GetString($bytes)
        return $unicodeText.IndexOf(
            $Needle,
            [System.StringComparison]::Ordinal
        ) -ge 0
    }
    finally {
        $memory.Dispose()
        $entryStream.Dispose()
    }
}

function Test-ZipEntryIsPairipAsset {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Compression.ZipArchiveEntry]$Entry
    )

    if ($Entry.Length -lt 4) {
        return $false
    }

    $entryStream = $Entry.Open()
    try {
        $header = New-Object byte[] 4
        if ($entryStream.Read($header, 0, 4) -ne 4) {
            return $false
        }
        return $header[0] -eq 0x00 -and
            $header[1] -eq 0x49 -and
            $header[2] -eq 0x41 -and
            $header[3] -eq 0x50
    }
    finally {
        $entryStream.Dispose()
    }
}

function Get-ApkIdentityHashes {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ApkPath
    )

    $hashes = @{}
    $identityArchive = [System.IO.Compression.ZipFile]::OpenRead($ApkPath)
    try {
        foreach ($entry in $identityArchive.Entries) {
            $isIdentityEntry =
                $entry.FullName -eq "AndroidManifest.xml" -or
                $entry.FullName -eq "resources.arsc" -or
                $entry.FullName -match '^classes\d*\.dex$' -or
                $entry.FullName -match '^res/' -or
                $entry.FullName -match '^lib/'
            if ($isIdentityEntry) {
                $hashes[$entry.FullName] = Get-ZipEntrySha256 -Entry $entry
            }
        }
    }
    finally {
        $identityArchive.Dispose()
    }
    return $hashes
}

function Assert-ApkIdentityPreserved {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Expected,

        [Parameter(Mandatory = $true)]
        [string]$ActualApk
    )

    $actual = Get-ApkIdentityHashes -ApkPath $ActualApk
    if ($Expected.Count -ne $actual.Count) {
        throw "APK identity entry count changed from $($Expected.Count) to $($actual.Count)."
    }
    foreach ($name in $Expected.Keys) {
        if (-not $actual.ContainsKey($name)) {
            throw "APK identity entry is missing after build: $name"
        }
        if ($Expected[$name] -ne $actual[$name]) {
            throw "APK identity entry changed after build: $name"
        }
    }
}

function Write-ZipText {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Compression.ZipArchive]$Archive,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $existing = $Archive.GetEntry($Name)
    if ($null -ne $existing) {
        $existing.Delete()
    }

    $entry = $Archive.CreateEntry(
        $Name,
        [System.IO.Compression.CompressionLevel]::Optimal
    )
    $entryStream = $entry.Open()
    try {
        $writer = New-Object System.IO.StreamWriter(
            $entryStream,
            (New-Object System.Text.UTF8Encoding($false))
        )
        try {
            $writer.Write($Text)
            $writer.Flush()
        }
        finally {
            $writer.Dispose()
        }
    }
    finally {
        $entryStream.Dispose()
    }
}

function Get-SignerJar {
    param(
        [string]$RequestedPath,
        [string]$DefaultPath
    )

    if ($RequestedPath) {
        $resolved = Resolve-ExistingFile -Path $RequestedPath -Label "Signer JAR"
    }
    else {
        $resolved = $DefaultPath
        if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
            $parent = Split-Path -Parent $resolved
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
            Write-Host "Downloading uber-apk-signer $SignerVersion..."
            Invoke-WebRequest -UseBasicParsing -Uri $SignerUrl -OutFile $resolved
        }
    }

    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolved).Hash
    if ($actualHash -ne $SignerSha256) {
        throw "Signer checksum mismatch. Expected $SignerSha256, got $actualHash."
    }
    return $resolved
}

function Get-BundledWindowsZipAlign {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VerifiedSignerJar,

        [Parameter(Mandatory = $true)]
        [string]$ToolsRoot
    )

    $zipAlignDirectory = Join-Path $ToolsRoot "zipalign-33.0.2"
    $zipAlignPath = Join-Path $zipAlignDirectory "zipalign.exe"
    $runtimeLibraryPath = Join-Path $zipAlignDirectory "libwinpthread-1.dll"
    if ((Test-Path -LiteralPath $zipAlignPath -PathType Leaf) -and
        (Test-Path -LiteralPath $runtimeLibraryPath -PathType Leaf)) {
        return $zipAlignPath
    }

    New-Item -ItemType Directory -Path $zipAlignDirectory -Force | Out-Null
    $jarArchive = [System.IO.Compression.ZipFile]::OpenRead($VerifiedSignerJar)
    try {
        $mappings = @(
            @("win-zipalign_33_0_2.exe", $zipAlignPath),
            @(
                "binary-lib/windows-33_0_2/libwinpthread-1.dll",
                $runtimeLibraryPath
            )
        )
        foreach ($mapping in $mappings) {
            $entry = $jarArchive.GetEntry($mapping[0])
            if ($null -eq $entry) {
                throw "Pinned signer does not contain $($mapping[0])."
            }
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile(
                $entry,
                $mapping[1],
                $true
            )
        }
    }
    finally {
        $jarArchive.Dispose()
    }
    return $zipAlignPath
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$sourceModule = Resolve-ExistingFile `
    -Path (Join-Path $repoRoot "src\balalaio.lua") `
    -Label "Balalaio module"
$inputPath = Resolve-ExistingFile -Path $InputApk -Label "Input APK"
$outputPath = Resolve-OutputFile -Path $OutputApk

if ($inputPath -eq $outputPath) {
    throw "InputApk and OutputApk must be different files."
}

$outputDirectory = Split-Path -Parent $outputPath
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$identityHashes = Get-ApkIdentityHashes -ApkPath $inputPath

$inspectionArchive = [System.IO.Compression.ZipFile]::OpenRead($inputPath)
try {
    $manifestEntry = $inspectionArchive.GetEntry("AndroidManifest.xml")
    $mainEntry = $inspectionArchive.GetEntry("assets/main.lua")
    if ($null -eq $mainEntry) {
        throw "The APK does not contain assets/main.lua."
    }
    if ($null -eq $manifestEntry) {
        throw "The APK does not contain AndroidManifest.xml."
    }
    $versionEntry = $inspectionArchive.GetEntry("assets/version.jkr")
    $classesEntry = $inspectionArchive.GetEntry("classes.dex")
    $mainHash = Get-ZipEntrySha256 -Entry $mainEntry
    $mainSource = Read-ZipText -Entry $mainEntry
    $gameVersion = if ($null -ne $versionEntry) {
        (Read-ZipText -Entry $versionEntry).Trim()
    }
    else {
        "unknown"
    }

    $packageMatches = Test-ZipEntryContainsAscii `
        -Entry $manifestEntry `
        -Needle $ExpectedPackageId
    $nativeLibraryCount = @($inspectionArchive.Entries | Where-Object {
        $_.FullName -match '^lib/[^/]+/.+\.so$'
    }).Count
    $hasSplitMetadata =
        $null -ne $inspectionArchive.GetEntry("res/xml/splits0.xml")
    $hasPairipCode = $null -ne $classesEntry -and (
        (Test-ZipEntryContainsAscii `
            -Entry $classesEntry `
            -Needle "com/pairip/SignatureCheck") -or
        (Test-ZipEntryContainsAscii `
            -Entry $classesEntry `
            -Needle "com/pairip/application/Application")
    )
    $pairipAssetCount = @($inspectionArchive.Entries | Where-Object {
        $_.FullName -match '^assets/[^./]+$' -and
        (Test-ZipEntryIsPairipAsset -Entry $_)
    }).Count
}
finally {
    $inspectionArchive.Dispose()
}

if (-not $packageMatches) {
    throw "Input package is not $ExpectedPackageId."
}

$unsupportedReasons = @()
if ($hasSplitMetadata -and $nativeLibraryCount -eq 0) {
    $unsupportedReasons +=
        "it is a Play base split with no packaged native libraries"
}
if ($hasPairipCode -or $pairipAssetCount -gt 0) {
    $unsupportedReasons +=
        "it contains Pairip signature protection or encrypted IAP assets"
}
if ($unsupportedReasons.Count -gt 0) {
    $unsupportedMessage =
        "Unsupported Android wrapper: " + ($unsupportedReasons -join "; ")
    if (-not $AllowUnsupportedWrapper) {
        throw "$unsupportedMessage. Use a self-contained, unprotected APK. " +
            "Balalaio does not bypass license or anti-tamper protection."
    }
    Write-Warning $unsupportedMessage
}

if ($SupportedMainSha256 -notcontains $mainHash) {
    $message = "Unsupported assets/main.lua SHA-256: $mainHash (game: $gameVersion)"
    if (-not $AllowUnknownVersion) {
        throw "$message. Pass -AllowUnknownVersion only after reviewing compatibility."
    }
    Write-Warning $message
}

$newline = if ($mainSource.Contains("`r`n")) { "`r`n" } else { "`n" }
if ($mainSource -notmatch '(?m)^\s*require\s+["'']balalaio["'']\s*$') {
    $anchors = @(
        'require "challenges"',
        "require 'challenges'"
    )
    $anchor = $null
    foreach ($candidate in $anchors) {
        if ($mainSource.Contains($candidate)) {
            $anchor = $candidate
            break
        }
    }
    if ($null -eq $anchor) {
        throw 'Could not find the expected require "challenges" startup anchor.'
    }
    $anchorIndex = $mainSource.IndexOf(
        $anchor,
        [System.StringComparison]::Ordinal
    )
    $insertAt = $anchorIndex + $anchor.Length
    $mainSource = $mainSource.Insert(
        $insertAt,
        $newline + 'require "balalaio"'
    )
}

$workRoot = Join-Path $repoRoot "build"
New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
$workDirectory = Join-Path $workRoot ("run-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $workDirectory -Force | Out-Null
$unsignedPath = Join-Path $workDirectory "balalaio-unsigned.apk"
$signedDirectory = Join-Path $workDirectory "signed"

try {
    [System.IO.File]::Copy($inputPath, $unsignedPath, $true)

    $fileStream = [System.IO.File]::Open(
        $unsignedPath,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None
    )
    try {
        $archive = New-Object System.IO.Compression.ZipArchive(
            $fileStream,
            [System.IO.Compression.ZipArchiveMode]::Update,
            $false
        )
        try {
            $signatureEntries = @($archive.Entries | Where-Object {
                $_.FullName -match '^META-INF/.*\.(RSA|DSA|EC|SF|MF)$'
            })
            foreach ($entry in $signatureEntries) {
                $entry.Delete()
            }

            Write-ZipText `
                -Archive $archive `
                -Name "assets/main.lua" `
                -Text $mainSource
            Write-ZipText `
                -Archive $archive `
                -Name "assets/balalaio.lua" `
                -Text ([System.IO.File]::ReadAllText(
                    $sourceModule,
                    (New-Object System.Text.UTF8Encoding($false))
                ))
            Write-ZipText `
                -Archive $archive `
                -Name "assets/balalaio.version" `
                -Text ("version=0.1.1" + $newline)
        }
        finally {
            $archive.Dispose()
        }
    }
    finally {
        $fileStream.Dispose()
    }

    if ($SkipSign) {
        [System.IO.File]::Copy($unsignedPath, $outputPath, $true)
        Write-Warning "Created an unsigned test artifact because -SkipSign was used."
    }
    else {
        if ($Keystore -and -not $KeystoreAlias) {
            throw "KeystoreAlias is required when Keystore is provided."
        }
        if ($KeystoreAlias -and -not $Keystore) {
            throw "Keystore is required when KeystoreAlias is provided."
        }

        $defaultSigner = Join-Path `
            $repoRoot `
            ".tools\uber-apk-signer-$SignerVersion.jar"
        $signerPath = Get-SignerJar `
            -RequestedPath $SignerJar `
            -DefaultPath $defaultSigner

        $previousErrorPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        & $Java -version
        $javaExitCode = $LASTEXITCODE
        $ErrorActionPreference = $previousErrorPreference
        if ($javaExitCode -ne 0) {
            throw "Java could not be started using '$Java'."
        }

        New-Item -ItemType Directory -Path $signedDirectory -Force | Out-Null
        $signArguments = @(
            "-jar",
            $signerPath,
            "--apks",
            $unsignedPath,
            "--out",
            $signedDirectory,
            "--allowResign"
        )

        if ($env:OS -eq "Windows_NT") {
            $zipAlignPath = Get-BundledWindowsZipAlign `
                -VerifiedSignerJar $signerPath `
                -ToolsRoot (Join-Path $repoRoot ".tools")
            $signArguments += @("--zipAlignPath", $zipAlignPath)
        }

        if ($Keystore) {
            $resolvedKeystore = Resolve-ExistingFile `
                -Path $Keystore `
                -Label "Keystore"
            $signArguments += @("--ks", $resolvedKeystore)
            $signArguments += @("--ksAlias", $KeystoreAlias)
            if ($KeystorePassword) {
                $signArguments += @("--ksPass", $KeystorePassword)
            }
            if ($KeyPassword) {
                $signArguments += @("--ksKeyPass", $KeyPassword)
            }
        }

        & $Java @signArguments
        if ($LASTEXITCODE -ne 0) {
            throw "APK signing failed with exit code $LASTEXITCODE."
        }

        $signedApks = @(Get-ChildItem `
            -LiteralPath $signedDirectory `
            -Filter "*.apk" `
            -File)
        if ($signedApks.Count -ne 1) {
            throw "Expected one signed APK, found $($signedApks.Count)."
        }
        [System.IO.File]::Copy($signedApks[0].FullName, $outputPath, $true)

        $verifyArguments = @(
            "-jar",
            $signerPath,
            "--apks",
            $outputPath,
            "--onlyVerify"
        )
        if ($env:OS -eq "Windows_NT") {
            $verifyArguments += @("--zipAlignPath", $zipAlignPath)
        }
        & $Java @verifyArguments
        if ($LASTEXITCODE -ne 0) {
            throw "Final APK verification failed with exit code $LASTEXITCODE."
        }
    }

    Assert-ApkIdentityPreserved `
        -Expected $identityHashes `
        -ActualApk $outputPath

    $outputHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $outputPath).Hash
    $outputSize = (Get-Item -LiteralPath $outputPath).Length
    Write-Host ""
    Write-Host "Balalaio build complete."
    Write-Host "Game version : $gameVersion"
    Write-Host "Output       : $outputPath"
    Write-Host "Bytes        : $outputSize"
    Write-Host "SHA-256      : $outputHash"
    Write-Host "Native libs  : $nativeLibraryCount"
    Write-Host "Identity     : manifest, package, name, icons, resources, native libraries, and DEX preserved"
}
finally {
    if ($KeepWork) {
        Write-Host "Kept build workspace: $workDirectory"
    }
    elseif (Test-Path -LiteralPath $workDirectory) {
        $resolvedWork = (Resolve-Path -LiteralPath $workDirectory).Path
        $resolvedRoot = (Resolve-Path -LiteralPath $workRoot).Path
        if ($resolvedWork.StartsWith(
            $resolvedRoot + [System.IO.Path]::DirectorySeparatorChar,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            Remove-Item -LiteralPath $resolvedWork -Recurse -Force
        }
    }
}
