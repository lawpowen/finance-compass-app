[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  throw 'Docker Desktop (with Docker Compose) is required.'
}
& docker compose version
if ($LASTEXITCODE -ne 0) { throw 'Docker Compose is unavailable.' }
& docker compose up -d --build
if ($LASTEXITCODE -ne 0) { throw 'Self-hosted service failed to start.' }
Write-Host 'Finance Compass listens only on http://127.0.0.1:8080 by default.'
Write-Host 'Configure HTTPS plus authentication before exposing it beyond this host.'
