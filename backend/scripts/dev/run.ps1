# Start the backend and its required local services from any working directory.
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
& docker compose --project-directory $repoRoot -f (Join-Path $repoRoot 'compose.yaml') up -d --build backend
exit $LASTEXITCODE
