param(
    [switch]$Local,
    [string]$Device,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$FlutterArgs
)

$runArgs = @('run')
$appRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ($Device) { $runArgs += @('-d', $Device) }
if ($Local) {
    $runArgs += @(
        '--dart-define=API_BASE_URL=http://10.0.2.2:8080/api',
        '--dart-define=AUTH_BASE_URL=http://10.0.2.2:8180',
        '--dart-define=APP_BASE_URL=http://10.0.2.2:4200'
    )
}
if ($FlutterArgs) { $runArgs += $FlutterArgs }

Push-Location $appRoot
try {
    & flutter @runArgs
    $runExitCode = $LASTEXITCODE
} finally {
    Pop-Location
}
exit $runExitCode
