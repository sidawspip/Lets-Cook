param(
    [string]$KeycloakAdmin = 'admin',
    [string]$KeycloakPassword = 'admin',
    [string[]]$AllowedMail = @(),
    [ValidateRange(0, 8)]
    [int]$OpenIncognitoSessions = 0,
    [ValidateSet('Chrome', 'Edge')]
    [string]$TestBrowser = 'Chrome'
)

$ErrorActionPreference = 'Stop'

& "$PSScriptRoot\start-cloudflare-uat.ps1" `
    -KeycloakAdmin $KeycloakAdmin `
    -KeycloakPassword $KeycloakPassword `
    -AllowedMail $AllowedMail `
    -RequireGlobalMedia `
    -OpenIncognitoSessions $OpenIncognitoSessions `
    -TestBrowser $TestBrowser

