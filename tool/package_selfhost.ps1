[CmdletBinding()]
param(
  [string]$Version = '0.10.0',
  [string]$OutputDirectory = 'artifacts/release/v0.10.0',
  [string]$Flutter = 'flutter',
  [string]$Dart = 'dart',
  [switch]$SkipWebBuild
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function New-PortableZip {
  param(
    [Parameter(Mandatory = $true)][string]$SourceDirectory,
    [Parameter(Mandatory = $true)][string]$DestinationPath
  )

  $sourceRoot = (Resolve-Path -LiteralPath $SourceDirectory).Path
  $destinationFullPath = [System.IO.Path]::GetFullPath($DestinationPath)
  $fileStream = [System.IO.File]::Open(
    $destinationFullPath,
    [System.IO.FileMode]::CreateNew,
    [System.IO.FileAccess]::Write,
    [System.IO.FileShare]::None
  )
  try {
    $zip = New-Object System.IO.Compression.ZipArchive(
      $fileStream,
      [System.IO.Compression.ZipArchiveMode]::Create,
      $false
    )
    try {
      Get-ChildItem -LiteralPath $sourceRoot -File -Recurse | ForEach-Object {
        $relativePath = $_.FullName.Substring($sourceRoot.Length).TrimStart('\', '/')
        $entryName = 'FinanceCompass-SelfHost/' + ($relativePath -replace '\\', '/')
        $entry = $zip.CreateEntry(
          $entryName,
          [System.IO.Compression.CompressionLevel]::Optimal
        )
        $inputStream = $_.OpenRead()
        $outputStream = $entry.Open()
        try {
          $inputStream.CopyTo($outputStream)
        } finally {
          $outputStream.Dispose()
          $inputStream.Dispose()
        }
      }
    } finally {
      $zip.Dispose()
    }
  } finally {
    $fileStream.Dispose()
  }
}

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
if (-not $SkipWebBuild) {
  & (Join-Path $root 'tool/build_web.ps1') -Flutter $Flutter -Dart $Dart
  if ($LASTEXITCODE -ne 0) { throw 'Web build failed; no self-hosted package was created.' }
}
if (-not (Test-Path -LiteralPath 'build/web/index.html')) {
  throw 'build/web is missing. Run tool/build_web.ps1 or omit -SkipWebBuild.'
}

$staging = Join-Path $env:TEMP "finance-compass-selfhost-$Version"
if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
$bundle = Join-Path $staging 'FinanceCompass-SelfHost'
New-Item -ItemType Directory -Path $bundle | Out-Null
Copy-Item -LiteralPath 'deploy/selfhost/Caddyfile','deploy/selfhost/Caddyfile.reverse-proxy.example','deploy/selfhost/install.sh','deploy/selfhost/install.ps1','deploy/selfhost/install.command' -Destination $bundle
Copy-Item -LiteralPath 'deploy/selfhost/Dockerfile.runtime' -Destination (Join-Path $bundle 'Dockerfile')
Copy-Item -LiteralPath 'deploy/selfhost/compose.runtime.yml' -Destination (Join-Path $bundle 'compose.yml')
Copy-Item -LiteralPath 'build/web' -Destination (Join-Path $bundle 'webroot') -Recurse
Copy-Item -LiteralPath 'docs/SELF_HOSTING.md' -Destination $bundle
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$archives = @(
  (Join-Path $OutputDirectory "FinanceCompass-SelfHost-Windows-v$Version.zip"),
  (Join-Path $OutputDirectory "FinanceCompass-SelfHost-macOS-v$Version.zip"),
  (Join-Path $OutputDirectory "FinanceCompass-SelfHost-Ubuntu-v$Version.zip")
)
foreach ($archive in $archives) {
  if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
  New-PortableZip -SourceDirectory $bundle -DestinationPath $archive
}
Get-FileHash -LiteralPath $archives -Algorithm SHA256
