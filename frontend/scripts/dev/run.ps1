# Start the web app, backend, and their required local services.
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
& docker compose --project-directory $repoRoot -f (Join-Path $repoRoot 'compose.yaml') up -d --build frontend
exit $LASTEXITCODE
