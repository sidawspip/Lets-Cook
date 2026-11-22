$ErrorActionPreference = 'Stop'
Set-Location (Resolve-Path (Join-Path $PSScriptRoot '..'))

$dart = (Get-Command dart -ErrorAction SilentlyContinue).Source
if (-not $dart) { throw 'Dart SDK is required to build the YouTube media resolver.' }
$resolverProject = Join-Path (Get-Location) 'media_resolver'
$resolverExe = Join-Path (Get-Location) 'resources\xynk-youtube-resolver.exe'
if (-not (Test-Path $resolverExe) -or
    (Get-Item (Join-Path $resolverProject 'bin\resolve_youtube.dart')).LastWriteTime -gt (Get-Item $resolverExe).LastWriteTime) {
  Push-Location $resolverProject
  try {
    if (-not (Test-Path '.dart_tool\package_config.json')) {
      & $dart pub get
      if ($LASTEXITCODE -ne 0) { throw 'Could not restore the YouTube media resolver dependencies.' }
    }
    & $dart compile exe 'bin\resolve_youtube.dart' -o $resolverExe
    if ($LASTEXITCODE -ne 0) { throw 'Could not compile the YouTube media resolver.' }
  } finally { Pop-Location }
}

& npm run type-check
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& npm run build:main
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& npx vite build
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$buildOutput = 'release-local-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
& npx electron-builder --config electron-builder.json "--config.directories.output=$buildOutput" '--config.win.signAndEditExecutable=false' --win dir --x64
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "Built Windows app: $(Join-Path (Get-Location) "$buildOutput\win-unpacked\XYNK.exe")"
