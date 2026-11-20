param(
    [ValidateSet('Production', 'Development')]
    [string]$Configuration = 'Production',
    [switch]$InstallDependencies,
    [switch]$DryRun
)

$appRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$command = if ($Configuration -eq 'Production') { 'build' } else { 'check' }
if ($InstallDependencies) { Write-Output 'npm ci' }
Write-Output "npm run $command"
if ($DryRun) { return }

Push-Location $appRoot
try {
    if ($InstallDependencies) {
        & npm ci
        if ($LASTEXITCODE -ne 0) { throw "npm ci failed with exit code $LASTEXITCODE" }
    }
    & npm run $command
    if ($LASTEXITCODE -ne 0) { throw "Web build failed with exit code $LASTEXITCODE" }
    $outputDir = Join-Path $appRoot 'dist/xynk-web/browser'
    if (-not (Test-Path -LiteralPath (Join-Path $outputDir 'index.html') -PathType Leaf)) {
        throw "Web build output not found: $outputDir"
    }
    Write-Output "Web build: $outputDir"
} finally {
    Pop-Location
}
