[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$SshHost = 'homelab',

    [ValidatePattern('^[A-Za-z0-9._-]{1,64}$')]
    [string]$Username = 'lawpowen'
)

$ErrorActionPreference = 'Stop'
$sshOptions = @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=8')
& ssh @sshOptions $SshHost 'curl --fail --silent --show-error http://127.0.0.1:18765/api/sync/v1/health >/dev/null'
if ($LASTEXITCODE -ne 0) {
    throw 'Finance Compass is not reachable through this Homelab SSH alias.'
}

Write-Host "Finance Compass account: $Username"
Write-Host 'Setting the password signs out this account on other devices.'

function ConvertTo-PasswordText {
    param([Security.SecureString]$Value)

    $buffer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($buffer)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($buffer)
    }
}

$encodingBefore = $OutputEncoding
$first = $null
$second = $null
try {
    $first = Read-Host 'New password (12–256 UTF-8 bytes)' -AsSecureString
    $second = Read-Host 'Repeat the password' -AsSecureString
    $password = ConvertTo-PasswordText $first
    $confirmation = ConvertTo-PasswordText $second
    if (-not [string]::Equals($password, $confirmation, [StringComparison]::Ordinal)) {
        throw 'The passwords do not match.'
    }
    $byteCount = [Text.Encoding]::UTF8.GetByteCount($password)
    if ($password -match '[\r\n]' -or $byteCount -lt 12 -or $byteCount -gt 256) {
        throw 'Use 12–256 UTF-8 bytes on a single line.'
    }

    $OutputEncoding = [Text.UTF8Encoding]::new($false)
    $password | & ssh @sshOptions $SshHost "sudo -n docker exec -i finance-compass-sync-1 node server/provision.mjs '$Username'"
    if ($LASTEXITCODE -ne 0) {
        throw 'Homelab did not confirm the password update.'
    }
} finally {
    $OutputEncoding = $encodingBefore
    if ($null -ne $first) { $first.Dispose() }
    if ($null -ne $second) { $second.Dispose() }
    $password = $null
    $confirmation = $null
}
