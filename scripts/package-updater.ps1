#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter()]
    [string]$RepositoryRoot,

    [Parameter()]
    [string]$OutputDirectory
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

function Resolve-FullPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$BasePath
    )

    $expandedPath = [Environment]::ExpandEnvironmentVariables($Path)
    if ([System.IO.Path]::IsPathRooted($expandedPath)) {
        return [System.IO.Path]::GetFullPath($expandedPath)
    }

    return [System.IO.Path]::GetFullPath(
        (Join-Path $BasePath $expandedPath)
    )
}

function Get-StreamSha256 {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Stream]$Stream
    )

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha256.ComputeHash($Stream)
        return (
            ($hashBytes | ForEach-Object { $_.ToString("x2") }) -join ""
        )
    }
    finally {
        $sha256.Dispose()
    }
}

function Get-FileSha256 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        return Get-StreamSha256 -Stream $stream
    }
    finally {
        $stream.Dispose()
    }
}

function Test-UpdaterArchive {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ArchivePath,

        [Parameter(Mandatory = $true)]
        [object[]]$Files
    )

    if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
        throw "Updater archive was not created: '$ArchivePath'."
    }
    if ((Get-Item -LiteralPath $ArchivePath).Length -le 0) {
        throw "Updater archive is empty: '$ArchivePath'."
    }

    $stream = [System.IO.File]::Open(
        $ArchivePath,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::Read
    )
    $archive = $null
    try {
        $archive = New-Object System.IO.Compression.ZipArchive(
            $stream,
            [System.IO.Compression.ZipArchiveMode]::Read,
            $false
        )

        if ($archive.Entries.Count -ne $Files.Count) {
            throw (
                "Updater archive has {0} entries; expected {1}." -f
                $archive.Entries.Count,
                $Files.Count
            )
        }

        foreach ($file in $Files) {
            $entry = $archive.GetEntry($file.ArchivePath)
            if ($null -eq $entry) {
                throw (
                    "Updater archive is missing '{0}'." -f
                    $file.ArchivePath
                )
            }
            if ($entry.Length -ne $file.Length) {
                throw (
                    "Size mismatch for '{0}' in updater archive." -f
                    $file.ArchivePath
                )
            }

            $entryStream = $entry.Open()
            try {
                $entryHash = Get-StreamSha256 -Stream $entryStream
            }
            finally {
                $entryStream.Dispose()
            }
            if ($entryHash -ne $file.Sha256) {
                throw (
                    "Content mismatch for '{0}' in updater archive." -f
                    $file.ArchivePath
                )
            }
        }
    }
    finally {
        if ($null -ne $archive) {
            $archive.Dispose()
        }
        $stream.Dispose()
    }
}

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Join-Path $PSScriptRoot ".."
}
$repositoryPath = Resolve-FullPath `
    -Path $RepositoryRoot `
    -BasePath (Get-Location).Path
if (-not (Test-Path -LiteralPath $repositoryPath -PathType Container)) {
    throw "Repository root was not found: '$repositoryPath'."
}
$repositoryPath = (Resolve-Path -LiteralPath $repositoryPath).Path

$metadataPath = Join-Path $repositoryPath "Balalaio\Balalaio.json"
if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
    throw "Balalaio metadata was not found: '$metadataPath'."
}

try {
    $metadata = Get-Content -Raw -Encoding UTF8 -LiteralPath $metadataPath |
        ConvertFrom-Json
}
catch {
    throw (
        "Could not read Balalaio metadata at '{0}': {1}" -f
        $metadataPath,
        $_.Exception.Message
    )
}

$version = [string]$metadata.version
if ([string]::IsNullOrWhiteSpace($version)) {
    throw "Balalaio metadata does not contain a version."
}
$version = $version.Trim()
if (
    $version -notmatch
    '^[0-9]+(?:\.[0-9]+){2}(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$'
) {
    throw "Balalaio version '$version' is not a valid semantic version."
}

$packageName = "Balalaio-Windows-Updater-v$version"
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $outputPathRoot = Join-Path $repositoryPath "dist"
}
else {
    $outputPathRoot = Resolve-FullPath `
        -Path $OutputDirectory `
        -BasePath (Get-Location).Path
}
New-Item -ItemType Directory -Force -Path $outputPathRoot | Out-Null
$outputPathRoot = (Resolve-Path -LiteralPath $outputPathRoot).Path
$outputPath = Join-Path $outputPathRoot "$packageName.zip"

$sourceDefinitions = @(
    @{ Source = "update.bat"; Archive = "update.bat" },
    @{ Source = "install.bat"; Archive = "install.bat" },
    @{ Source = "install.ps1"; Archive = "install.ps1" },
    @{
        Source = "Balalaio\Balalaio.json"
        Archive = "Balalaio/Balalaio.json"
    },
    @{
        Source = "Balalaio\balalaio.lua"
        Archive = "Balalaio/balalaio.lua"
    }
)

$files = @()
foreach ($definition in $sourceDefinitions) {
    $sourcePath = Join-Path $repositoryPath $definition.Source
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Updater source file was not found: '$sourcePath'."
    }

    $sourceItem = Get-Item -LiteralPath $sourcePath
    if ($sourceItem.Length -le 0) {
        throw "Updater source file is empty: '$sourcePath'."
    }

    $files += [pscustomobject]@{
        SourcePath = $sourceItem.FullName
        ArchivePath = "$packageName/$($definition.Archive)"
        Length = $sourceItem.Length
        Sha256 = Get-FileSha256 -Path $sourceItem.FullName
    }
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$temporaryPath = Join-Path (
    [System.IO.Path]::GetTempPath()
) ("balalaio-updater-" + [guid]::NewGuid().ToString("N") + ".zip")
$zipTimestamp = [DateTimeOffset]::Parse(
    "2000-01-01T00:00:00+00:00",
    [Globalization.CultureInfo]::InvariantCulture
)

try {
    $stream = [System.IO.File]::Open(
        $temporaryPath,
        [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None
    )
    $archive = $null
    try {
        $archive = New-Object System.IO.Compression.ZipArchive(
            $stream,
            [System.IO.Compression.ZipArchiveMode]::Create,
            $false
        )

        foreach ($file in $files) {
            $entry = $archive.CreateEntry(
                $file.ArchivePath,
                [System.IO.Compression.CompressionLevel]::Optimal
            )
            $entry.LastWriteTime = $zipTimestamp

            $sourceStream = [System.IO.File]::OpenRead($file.SourcePath)
            $entryStream = $entry.Open()
            try {
                $sourceStream.CopyTo($entryStream)
            }
            finally {
                $entryStream.Dispose()
                $sourceStream.Dispose()
            }
        }
    }
    finally {
        if ($null -ne $archive) {
            $archive.Dispose()
        }
        else {
            $stream.Dispose()
        }
    }

    Test-UpdaterArchive -ArchivePath $temporaryPath -Files $files

    if (Test-Path -LiteralPath $outputPath) {
        Remove-Item -LiteralPath $outputPath -Force
    }
    Move-Item -LiteralPath $temporaryPath -Destination $outputPath
    Test-UpdaterArchive -ArchivePath $outputPath -Files $files
}
finally {
    if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
        Remove-Item -LiteralPath $temporaryPath -Force
    }
}

$outputItem = Get-Item -LiteralPath $outputPath
$outputHash = Get-FileSha256 -Path $outputPath
Write-Host "Created Balalaio Windows updater package." -ForegroundColor Green
Write-Host "Version : $version"
Write-Host "Path    : $($outputItem.FullName)"
Write-Host "Size    : $($outputItem.Length) bytes"
Write-Host "SHA-256 : $outputHash"

[pscustomobject]@{
    Version = $version
    Path = $outputItem.FullName
    Length = $outputItem.Length
    Sha256 = $outputHash
}
