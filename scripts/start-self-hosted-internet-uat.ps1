param(
    [switch]$RouterPortsForwarded,
    [string]$KeycloakAdmin = 'admin',
    [string]$KeycloakPassword = 'admin',
    [string[]]$AllowedMail = @(),
    [ValidateRange(0, 8)]
    [int]$OpenIncognitoSessions = 0,
    [ValidateSet('Chrome', 'Edge')]
    [string]$TestBrowser = 'Chrome'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

if (-not $RouterPortsForwarded) {
    throw @'
Before starting laptop-hosted Internet media, configure your router to forward
these ports to this laptop's LAN address:
  TCP 7881
  UDP 7882
  UDP 3478

Also allow the same inbound ports in the host firewall. Then rerun with:
  .\scripts\start-self-hosted-internet-uat.ps1 -RouterPortsForwarded

If your ISP uses CGNAT and does not provide a public IPv4 address, router port
forwarding cannot work; use LiveKit Cloud or a public VPS instead.
'@
}

$oldComposeFile = $env:COMPOSE_FILE
try {
    $env:COMPOSE_FILE = (Join-Path $projectRoot 'compose.yaml') + ';' + (Join-Path $projectRoot 'compose.self-hosted-media.yaml')
    & "$PSScriptRoot\start-cloudflare-uat.ps1" `
        -KeycloakAdmin $KeycloakAdmin `
        -KeycloakPassword $KeycloakPassword `
        -AllowedMail $AllowedMail `
        -SelfHostedInternetMedia `
        -OpenIncognitoSessions $OpenIncognitoSessions `
        -TestBrowser $TestBrowser
} finally {
    $env:COMPOSE_FILE = $oldComposeFile
}

