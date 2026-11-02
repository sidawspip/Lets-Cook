param([string]$Address)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $projectRoot 'infra\livekit\livekit.yaml'

if (-not $Address) {
    $Address = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
        Where-Object {
            $_.IPAddress -notmatch '^(127\.|169\.254\.|172\.(1[6-9]|2\d|3[01])\.)' -and
            $_.InterfaceAlias -notmatch 'vEthernet|Loopback|Docker|WSL'
        } |
        Sort-Object InterfaceMetric |
        Select-Object -First 1 -ExpandProperty IPAddress
}
if ($Address -notmatch '^(?:\d{1,3}\.){3}\d{1,3}$') {
    throw 'Could not determine a valid LAN IPv4 address. Pass one with -Address.'
}

$content = Get-Content -LiteralPath $configPath -Raw
$updated = $content -replace '(?m)^\s*node_ip:\s*.*$', "  node_ip: $Address"
if ($updated -eq $content -and $content -notmatch '(?m)^\s*node_ip:') {
    throw 'node_ip was not found in infra/livekit/livekit.yaml.'
}
Set-Content -LiteralPath $configPath -Value $updated -Encoding utf8
Write-Host "LiveKit LAN candidate set to $Address. Restarting LiveKit..." -ForegroundColor Green
docker compose -f (Join-Path $projectRoot 'compose.yaml') up -d --force-recreate livekit
