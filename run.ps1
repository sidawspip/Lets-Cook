<#
.SYNOPSIS
Starts the local Xynk stack and its three clients in order.
.EXAMPLE
.\run.ps1
.EXAMPLE
.\run.ps1 -DryRun
.EXAMPLE
.\run.ps1 -SkipAndroid -SkipWindows
# Local development only. Use scripts/start-public.ps1 after the stack is healthy
# when this laptop should serve xynk.in through the named Cloudflare tunnel.
#>
param(
    [switch]$SkipBuild,
    [switch]$SkipAndroid,
    [switch]$SkipWindows,
    [switch]$SkipBrowser,
    [switch]$Test,
    [switch]$DryRun,
    [string]$AndroidDevice,
    [ValidateRange(30, 600)][int]$StartupTimeoutSeconds = 240
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$compose = Join-Path $root 'compose.yaml'
$apk = Join-Path $root 'mobile/build/app/outputs/flutter-apk/app-debug.apk'
$desktopRoot = Join-Path $root 'xynk-desktop'
$androidPackage = 'world.letscook.lets_cook_mobile'

function Step([int]$Number, [string]$Title) {
    Write-Host "`n[$Number/7] $Title" -ForegroundColor Cyan
}
function Run([string]$Description, [scriptblock]$Action) {
    Write-Host "  $Description"
    if ($DryRun) { return }
    & $Action
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "$Description failed (exit $LASTEXITCODE)." }
}
function Require-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) { throw "Required command missing: $Name" }
}
function Get-Adb {
    $fromPath = Get-Command adb -ErrorAction SilentlyContinue
    if ($fromPath) { return $fromPath.Source }
    $sdkRoots = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, (Join-Path $env:USERPROFILE 'AppData/Local/Android/Sdk'))
    foreach ($sdkRoot in $sdkRoots) {
        if ($sdkRoot) {
            $candidate = Join-Path $sdkRoot 'platform-tools/adb.exe'
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
    }
    throw 'Android SDK platform-tools/adb.exe was not found.'
}
function Wait-Url([string]$Url, [datetime]$Deadline) {
    Write-Host "  Waiting for $Url"
    if ($DryRun) { return }
    while ((Get-Date) -lt $Deadline) {
        try {
            $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 8
            if ($response.StatusCode -eq 200) { Write-Host '  Ready' -ForegroundColor Green; return }
        } catch { }
        Start-Sleep -Seconds 3
    }
    throw "Timed out waiting for $Url. Check: docker compose logs"
}

Step 1 'Check tools and project files'
Run 'Check Docker, Compose, Flutter, and local project files' {
    Require-Command docker
    if (-not $SkipAndroid -or $Test) { Require-Command flutter }
    if (-not $SkipWindows) { Require-Command npm; Require-Command dart }
    if (-not (Test-Path -LiteralPath $compose)) { throw "Missing $compose" }
    & docker compose --project-directory $root -f $compose config --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Compose configuration is invalid.' }
    if (-not $SkipAndroid) { $script:adb = Get-Adb }
}

Step 2 'Start PostgreSQL, Redis, Keycloak, API, and web app'
Run 'docker compose up -d --build' {
    & docker compose --project-directory $root -f $compose up -d --build frontend
}

Step 3 'Wait for local web, auth, and API'
$deadline = (Get-Date).AddSeconds($StartupTimeoutSeconds)
Wait-Url 'http://localhost:4200/' $deadline
Wait-Url 'http://localhost:8180/realms/xynk/.well-known/openid-configuration' $deadline
Wait-Url 'http://localhost:8080/actuator/health' $deadline

Step 4 'Build local Android and Windows clients'
if (-not $SkipAndroid) {
    if ($SkipBuild) {
        Run "Use existing APK: $apk (confirm it was built with local URLs)" {
            if (-not (Test-Path -LiteralPath $apk -PathType Leaf)) { throw "Missing $apk; rerun without -SkipBuild." }
        }
    } else {
        Run 'Build Android debug APK with local URLs' {
            & (Join-Path $root 'mobile/scripts/prod/build.ps1') -Configuration Debug -Local
        }
    }
}
if (-not $SkipWindows) {
    if ($SkipBuild) {
        Run 'Use the newest existing Electron desktop build' {
            $script:windowsExe = Get-ChildItem -LiteralPath $desktopRoot -Directory -Filter 'release-local-*' |
                Sort-Object LastWriteTime -Descending |
                ForEach-Object { Join-Path $_.FullName 'win-unpacked/XYNK.exe' } |
                Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
                Select-Object -First 1
            if (-not $windowsExe) { throw 'No packaged Electron build found; rerun without -SkipBuild.' }
        }
    } else {
        Run 'Build the Electron desktop app against public Xynk URLs' {
            Push-Location $desktopRoot
            try { & npm run build } finally { Pop-Location }
            if ($LASTEXITCODE -ne 0) { throw 'Electron desktop build failed.' }
            $script:windowsExe = Get-ChildItem -LiteralPath $desktopRoot -Directory -Filter 'release-local-*' |
                Sort-Object LastWriteTime -Descending |
                ForEach-Object { Join-Path $_.FullName 'win-unpacked/XYNK.exe' } |
                Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
                Select-Object -First 1
            if (-not $windowsExe) { throw 'Built Electron executable was not found.' }
        }
    }
}

Step 5 'Launch Windows app'
if (-not $SkipWindows) {
    Run 'Open Windows Xynk' {
        Start-Process -FilePath $windowsExe -WorkingDirectory (Split-Path $windowsExe) | Out-Null
    }
}

Step 6 'Install and launch Android app'
if (-not $SkipAndroid) {
    Run 'Find a connected Android device or emulator' {
        $devices = @(& $adb devices | Select-String '^([^\s]+)\s+device$' | ForEach-Object { $_.Matches[0].Groups[1].Value })
        if ($AndroidDevice) {
            if ($AndroidDevice -notin $devices) { throw "Android device $AndroidDevice is not connected." }
            $script:androidTarget = $AndroidDevice
        } elseif ($devices.Count -eq 1) {
            $script:androidTarget = $devices[0]
        } elseif ($devices.Count -eq 0) {
            throw 'No Android device is connected. Start your emulator, then rerun the script.'
        } else {
            throw "Multiple Android devices found: $($devices -join ', '). Rerun with -AndroidDevice <id>."
        }
    }
    Run 'Install current debug APK and open Xynk' {
        & $adb -s $androidTarget install -r $apk
        if ($LASTEXITCODE -ne 0) { throw 'APK installation failed.' }
        & $adb -s $androidTarget shell am force-stop $androidPackage
        & $adb -s $androidTarget shell monkey -p $androidPackage 1 | Out-Null
    }
}

Step 7 'Open web app and optionally run checks'
if (-not $SkipBrowser) { Run 'Open http://localhost:4200/' { Start-Process 'http://localhost:4200/' | Out-Null } }
if ($Test) {
    Run 'Test two-account room flow' { & (Join-Path $root 'backend/scripts/dev/test-core-two-accounts.ps1') -PushObservationSeconds 5 }
    Run 'Test room media permissions' { & (Join-Path $root 'backend/scripts/dev/test-room-role-media.ps1') }
    if (-not $SkipAndroid) { Run 'Run Android Flutter tests' { Push-Location (Join-Path $root 'mobile'); try { & flutter test } finally { Pop-Location } } }
    if (-not $SkipWindows) { Run 'Run Electron desktop type checks' { Push-Location $desktopRoot; try { & npm run type-check } finally { Pop-Location } } }
}
Write-Host "`nXynk startup sequence complete." -ForegroundColor Green
