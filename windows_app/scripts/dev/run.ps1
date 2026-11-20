param(
    [switch]$Local,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$FlutterArgs
)

$runArgs = @('run', '-d', 'windows')
$appRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ($Local) {
    $runArgs += @(
        '--dart-define=API_BASE_URL=http://localhost:8080/api',
        '--dart-define=AUTH_BASE_URL=http://localhost:8180',
        '--dart-define=APP_BASE_URL=http://localhost:4200'
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
