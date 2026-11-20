param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',
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
if ($Local -and $Configuration -eq 'Release') { throw 'Local HTTP endpoints require a Debug Windows build.' }

if (-not $ApiBaseUrl) { $ApiBaseUrl = if ($Local) { 'http://localhost:8080/api' } else { $config.ApiBaseUrl } }
if (-not $AuthBaseUrl) { $AuthBaseUrl = if ($Local) { 'http://localhost:8180' } else { $config.AuthBaseUrl } }
if (-not $AppBaseUrl) { $AppBaseUrl = if ($Local) { 'http://localhost:4200' } else { $config.AppBaseUrl } }

foreach ($url in @($ApiBaseUrl, $AuthBaseUrl, $AppBaseUrl)) {
    $parsed = $null
    if (-not [Uri]::TryCreate($url, [UriKind]::Absolute, [ref]$parsed) -or $parsed.Scheme -notin @('http', 'https')) {
        throw "Expected an absolute HTTP(S) URL: $url"
    }
    if ($Configuration -eq 'Release' -and $parsed.Scheme -ne 'https') {
        throw 'Release builds require HTTPS API, auth, and app URLs.'
    }
}

$buildArgs = @(
    'build', 'windows', "--$($Configuration.ToLowerInvariant())",
    "--dart-define=API_BASE_URL=$ApiBaseUrl",
    "--dart-define=AUTH_BASE_URL=$AuthBaseUrl",
    "--dart-define=APP_BASE_URL=$AppBaseUrl"
)
Write-Output ('flutter ' + ($buildArgs -join ' '))
if ($DryRun) { return }

Push-Location $appRoot
try {
    & flutter @buildArgs
    if ($LASTEXITCODE -ne 0) { throw "Flutter Windows build failed with exit code $LASTEXITCODE" }
    $outputDir = Join-Path $appRoot "build/windows/x64/runner/$Configuration"
    $exe = Get-ChildItem -LiteralPath $outputDir -Filter '*.exe' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $exe) { throw "Windows EXE not found after build in: $outputDir" }
    Write-Output "EXE: $($exe.FullName)"
    Write-Output "Distribute the complete directory: $outputDir"
} finally {
    Pop-Location
}
