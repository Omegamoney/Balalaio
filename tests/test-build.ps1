$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$tempBase = [System.IO.Path]::GetTempPath()
$tempDirectory = Join-Path `
    $tempBase `
    ("balalaio-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempDirectory -Force | Out-Null

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Add-FixtureEntry {
    param(
        [System.IO.Compression.ZipArchive]$Archive,
        [string]$Name,
        [string]$Text
    )

    $entry = $Archive.CreateEntry($Name)
    $stream = $entry.Open()
    try {
        $writer = New-Object System.IO.StreamWriter(
            $stream,
            (New-Object System.Text.UTF8Encoding($false))
        )
        try {
            $writer.Write($Text)
        }
        finally {
            $writer.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

try {
    $fixture = Join-Path $tempDirectory "fixture.apk"
    $output = Join-Path $tempDirectory "output.apk"
    $archive = [System.IO.Compression.ZipFile]::Open(
        $fixture,
        [System.IO.Compression.ZipArchiveMode]::Create
    )
    try {
        Add-FixtureEntry `
            -Archive $archive `
            -Name "assets/main.lua" `
            -Text ("require `"game`"`nrequire `"challenges`"`n")
        Add-FixtureEntry `
            -Archive $archive `
            -Name "assets/version.jkr" `
            -Text "synthetic-test"
        Add-FixtureEntry `
            -Archive $archive `
            -Name "AndroidManifest.xml" `
            -Text "synthetic manifest com.playstack.balatro.android"
        Add-FixtureEntry `
            -Archive $archive `
            -Name "resources.arsc" `
            -Text "synthetic resources"
        Add-FixtureEntry `
            -Archive $archive `
            -Name "res/mipmap-hdpi/app_icon.png" `
            -Text "synthetic icon"
        Add-FixtureEntry `
            -Archive $archive `
            -Name "META-INF/MANIFEST.MF" `
            -Text "Signature-Version: 1.0"
        Add-FixtureEntry `
            -Archive $archive `
            -Name "META-INF/OLD.SF" `
            -Text "old signature"
        Add-FixtureEntry `
            -Archive $archive `
            -Name "classes.dex" `
            -Text "synthetic"
        Add-FixtureEntry `
            -Archive $archive `
            -Name "lib/arm64-v8a/liblove.so" `
            -Text "synthetic native library"
    }
    finally {
        $archive.Dispose()
    }

    $inputHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $fixture).Hash

    & (Join-Path $repoRoot "scripts\build.ps1") `
        -InputApk $fixture `
        -OutputApk $output `
        -AllowUnknownVersion `
        -SkipSign
    if (-not $?) {
        throw "Synthetic build failed."
    }

    if (-not (Test-Path -LiteralPath $output -PathType Leaf)) {
        throw "Synthetic build did not create the output."
    }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $fixture).Hash -ne $inputHash) {
        throw "The build modified its input APK."
    }

    $result = [System.IO.Compression.ZipFile]::OpenRead($output)
    try {
        $mainEntry = $result.GetEntry("assets/main.lua")
        $moduleEntry = $result.GetEntry("assets/balalaio.lua")
        $versionEntry = $result.GetEntry("assets/balalaio.version")
        if ($null -eq $mainEntry -or $null -eq $moduleEntry -or $null -eq $versionEntry) {
            throw "One or more Balalaio entries are missing."
        }
        if ($null -ne $result.GetEntry("META-INF/MANIFEST.MF")) {
            throw "Old JAR signature manifest was not removed."
        }
        if ($null -ne $result.GetEntry("META-INF/OLD.SF")) {
            throw "Old JAR signature file was not removed."
        }
        if ($null -eq $result.GetEntry("lib/arm64-v8a/liblove.so")) {
            throw "Native library was not preserved."
        }

        $stream = $mainEntry.Open()
        try {
            $reader = New-Object System.IO.StreamReader($stream)
            try {
                $patchedMain = $reader.ReadToEnd()
            }
            finally {
                $reader.Dispose()
            }
        }
        finally {
            $stream.Dispose()
        }

        if ($patchedMain -notmatch 'require\s+["'']balalaio["'']') {
            throw "Startup hook was not injected."
        }
    }
    finally {
        $result.Dispose()
    }

    $protectedFixture = Join-Path $tempDirectory "protected-fixture.apk"
    $protectedOutput = Join-Path $tempDirectory "protected-output.apk"
    [System.IO.File]::Copy($fixture, $protectedFixture, $true)
    $protectedArchive = [System.IO.Compression.ZipFile]::Open(
        $protectedFixture,
        [System.IO.Compression.ZipArchiveMode]::Update
    )
    try {
        $oldDex = $protectedArchive.GetEntry("classes.dex")
        if ($null -ne $oldDex) {
            $oldDex.Delete()
        }
        Add-FixtureEntry `
            -Archive $protectedArchive `
            -Name "classes.dex" `
            -Text "synthetic com/pairip/SignatureCheck"
    }
    finally {
        $protectedArchive.Dispose()
    }

    $protectionRejected = $false
    try {
        & (Join-Path $repoRoot "scripts\build.ps1") `
            -InputApk $protectedFixture `
            -OutputApk $protectedOutput `
            -AllowUnknownVersion `
            -SkipSign
    }
    catch {
        $protectionRejected =
            $_.Exception.Message -match "Unsupported Android wrapper"
    }
    if (-not $protectionRejected) {
        throw "Pairip-protected fixture was not rejected."
    }
    if (Test-Path -LiteralPath $protectedOutput) {
        throw "Rejected protected fixture produced an output APK."
    }

    Write-Host "Synthetic APK injection test passed."
}
finally {
    if (Test-Path -LiteralPath $tempDirectory) {
        $resolvedTemp = (Resolve-Path -LiteralPath $tempDirectory).Path
        $resolvedBase = [System.IO.Path]::GetFullPath($tempBase).TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar
        )
        if ($resolvedTemp.StartsWith(
            $resolvedBase + [System.IO.Path]::DirectorySeparatorChar,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
        }
    }
}
