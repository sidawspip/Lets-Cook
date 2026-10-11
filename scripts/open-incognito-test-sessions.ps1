param(
    [ValidateRange(1, 8)]
    [int]$Sessions = 2,
    [string]$Url = '',
    [ValidateSet('Chrome', 'Edge')]
    [string]$Browser = 'Chrome'
)

$ErrorActionPreference = 'Stop'

function Get-UatUrl {
    if ($Url.Trim()) { return $Url.Trim() }

    $containerName = 'lets-cook-cloudflare-uat'
    $running = docker ps --filter "name=^/$containerName$" --format '{{.Names}}' 2>$null
    if ($running -eq $containerName) {
        $logs = docker logs $containerName 2>&1 | Out-String
        $match = [regex]::Match($logs, 'https://[a-z0-9-]+\.trycloudflare\.com')
        if ($match.Success) { return $match.Value }
    }

    return 'http://localhost:4200'
}

function Find-BrowserExecutable {
    $candidates = if ($Browser -eq 'Chrome') {
        @(
            "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
            "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
            "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
        )
    } else {
        @(
            "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
            "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
            "$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe"
        )
    }

    $match = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if (-not $match) { throw "$Browser was not found. Install it or run with -Browser Edge." }
    return $match
}

$targetUrl = Get-UatUrl
$browserPath = Find-BrowserExecutable
$runId = [guid]::NewGuid().ToString('N')
$profileRoot = Join-Path $env:TEMP "lets-cook-uat-$runId"
New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null

Write-Host "Opening $Sessions isolated $Browser test sessions:" -ForegroundColor Green
Write-Host $targetUrl -ForegroundColor Cyan

for ($index = 1; $index -le $Sessions; $index++) {
    $profilePath = Join-Path $profileRoot "user-$index"
    New-Item -ItemType Directory -Path $profilePath -Force | Out-Null

    $privateFlag = if ($Browser -eq 'Chrome') { '--incognito' } else { '--inprivate' }
    $arguments = @(
        $privateFlag,
        '--new-window',
        '--no-first-run',
        "--user-data-dir=$profilePath",
        $targetUrl
    )
    Start-Process -FilePath $browserPath -ArgumentList $arguments
    Write-Host "  Session $index opened with an independent login profile."
}

Write-Host ''
Write-Host 'Use a different account in each window. Closing the windows ends their private sessions.'
Write-Host "Temporary profiles: $profileRoot" -ForegroundColor DarkGray
