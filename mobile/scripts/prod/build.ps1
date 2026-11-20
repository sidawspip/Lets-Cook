param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug',
    [string]$ConfigFile,
    [string]$ApiBaseUrl,
    [string]$AuthBaseUrl,
    [string]$AppBaseUrl,
    [switch]$Local,
    [switch]$DryRun
)

$appRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$defaultConfig = Join-Path $appRoot 'build-config.psd1'
$exampleConfig = Join-Path $appRoot 'build-config.example.psd1'
$selectedConfig = if ($ConfigFile) { $ConfigFile } elseif (Test-Path -LiteralPath $defaultConfig) { $defaultConfig } else { $exampleConfig }
if (-not (Test-Path -LiteralPath $selectedConfig -PathType Leaf)) { throw "Build config not found: $selectedConfig" }
$config = Import-PowerShellDataFile -LiteralPath $selectedConfig
if ($Local -and $Configuration -eq 'Release') { throw 'Local HTTP endpoints require a Debug APK.' }

if (-not $ApiBaseUrl) { $ApiBaseUrl = if ($Local) { 'http://10.0.2.2:8080/api' } else { $config.ApiBaseUrl } }
if (-not $AuthBaseUrl) { $AuthBaseUrl = if ($Local) { 'http://10.0.2.2:8180' } else { $config.AuthBaseUrl } }
if (-not $AppBaseUrl) { $AppBaseUrl = if ($Local) { 'http://10.0.2.2:4200' } else { $config.AppBaseUrl } }

foreach ($url in @($ApiBaseUrl, $AuthBaseUrl, $AppBaseUrl)) {
    $parsed = $null
    if (-not [Uri]::TryCreate($url, [UriKind]::Absolute, [ref]$parsed) -or $parsed.Scheme -notin @('http', 'https')) {
        throw "Expected an absolute HTTP(S) URL: $url"
    }
    if ($Configuration -eq 'Release' -and $parsed.Scheme -ne 'https') {
        throw 'Release builds require HTTPS API, auth, and app URLs.'
    }
}

if ($Configuration -eq 'Release' -and -not $DryRun) {
    $signingProperties = if ($env:LETSCOOK_SIGNING_PROPERTIES) { $env:LETSCOOK_SIGNING_PROPERTIES } else { Join-Path $env:USERPROFILE '.letscook/secrets/android-signing.properties' }
    if (-not (Test-Path -LiteralPath $signingProperties -PathType Leaf)) {
        throw 'Android release signing properties are missing. Set LETSCOOK_SIGNING_PROPERTIES or configure the private signing file.'
    }
}

$buildArgs = @(
    'build', 'apk', "--$($Configuration.ToLowerInvariant())",
    "--dart-define=API_BASE_URL=$ApiBaseUrl",
    "--dart-define=AUTH_BASE_URL=$AuthBaseUrl",
    "--dart-define=APP_BASE_URL=$AppBaseUrl"
)
Write-Output ('flutter ' + ($buildArgs -join ' '))
if ($DryRun) { return }

Push-Location $appRoot
try {
    & flutter @buildArgs
    if ($LASTEXITCODE -ne 0) { throw "Flutter APK build failed with exit code $LASTEXITCODE" }
    $apk = Join-Path $appRoot "build/app/outputs/flutter-apk/app-$($Configuration.ToLowerInvariant()).apk"
    if (-not (Test-Path -LiteralPath $apk -PathType Leaf)) { throw "APK not found after build: $apk" }
    Write-Output "APK: $apk"
} finally {
    Pop-Location
}
