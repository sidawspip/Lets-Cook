param([switch]$DryRun)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$tunnelConfig = Join-Path $root '.cloudflared/config.yml'

Write-Host '1/3 Start and rebuild the Docker application stack'
if (-not $DryRun) {
    & docker compose --project-directory $root -f (Join-Path $root 'compose.yaml') up -d --build frontend
    if ($LASTEXITCODE -ne 0) { throw 'Docker Compose startup failed.' }
}

Write-Host '2/3 Verify web, API, and authentication health'
foreach ($url in @(
    'http://localhost:4200/',
    'http://localhost:8080/actuator/health',
    'http://localhost:8180/realms/xynk/.well-known/openid-configuration'
)) {
    Write-Host "  $url"
    if (-not $DryRun) {
        $ready = $false
        for ($attempt = 0; $attempt -lt 40; $attempt++) {
            try {
                $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5
                if ($response.StatusCode -eq 200) { $ready = $true; break }
            } catch { }
            Start-Sleep -Seconds 3
        }
        if (-not $ready) { throw "Service did not become ready: $url" }
    }
}

Write-Host '3/3 Start the named Cloudflare tunnel (leave this window open)'
Write-Host "  cloudflared --config `"$tunnelConfig`" tunnel run"
if (-not $DryRun) {
    & cloudflared --config $tunnelConfig tunnel run
    if ($LASTEXITCODE -ne 0) { throw 'Cloudflare tunnel stopped with an error.' }
}
