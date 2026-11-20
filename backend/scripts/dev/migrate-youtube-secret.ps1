param(
    [string]$SecureEnvironmentFile = $(if ($env:LETSCOOK_SECURE_ENV) { $env:LETSCOOK_SECURE_ENV } else { Join-Path $env:USERPROFILE '.letscook\secrets\native-google.env' })
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$sources = @(
    (Join-Path $projectRoot 'infra\.env'),
    (Join-Path $projectRoot '.env'),
    (Join-Path $projectRoot '.env.example')
)
$secureLines = [Collections.Generic.List[string]]@(Get-Content -LiteralPath $SecureEnvironmentFile)
$stored = $secureLines | Where-Object { $_ -match '^\s*YOUTUBE_API_KEY\s*=\s*\S+' } | Select-Object -First 1
$key = if ($stored) { ($stored -split '=', 2)[1].Trim() } else { '' }

if (-not $key) {
    foreach ($source in $sources) {
        if (-not (Test-Path -LiteralPath $source)) { continue }
        foreach ($line in (Get-Content -LiteralPath $source)) {
            if ($line -match '^\s*YOUTUBE_API_KEY\s*=(.+)$') {
                $key = $Matches[1].Trim()
                if ($key) { break }
            }
        }
        if ($key) { break }
    }
    if (-not $key) { throw 'No YouTube API key found in the private file or local configuration.' }
    $secureLines.Add("YOUTUBE_API_KEY=$key")
    Set-Content -LiteralPath $SecureEnvironmentFile -Value $secureLines -Encoding utf8NoBOM
}

foreach ($source in $sources) {
    if (-not (Test-Path -LiteralPath $source)) { continue }
    $lines = [Collections.Generic.List[string]]@(Get-Content -LiteralPath $source)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*YOUTUBE_API_KEY\s*=') { $lines[$i] = 'YOUTUBE_API_KEY=' }
    }
    Set-Content -LiteralPath $source -Value $lines -Encoding utf8NoBOM
}

$principal = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
& icacls.exe $SecureEnvironmentFile /inheritance:r /grant:r "${principal}:F" | Out-Null
$key = $null
Write-Output 'YouTube API key is in the protected user secrets file; local configuration copies are cleared.'
