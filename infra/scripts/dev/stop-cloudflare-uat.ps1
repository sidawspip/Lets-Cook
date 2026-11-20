$ErrorActionPreference = 'Stop'
$containerName = 'xynk-cloudflare-uat'
$existing = docker ps -a --filter "name=^/$containerName$" --format '{{.Names}}'

if ($existing -eq $containerName) {
    docker rm -f $containerName | Out-Null
    Write-Host 'Cloudflare UAT tunnel stopped and removed.'
} else {
    Write-Host 'No Cloudflare UAT tunnel is running.'
}
