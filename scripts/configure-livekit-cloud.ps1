param(
    [string]$LiveKitUrl,
    [string]$LiveKitApiKey,
    [securestring]$LiveKitApiSecret
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $projectRoot '.env'

if (-not $LiveKitUrl) {
    $LiveKitUrl = Read-Host 'LiveKit Cloud Project URL (wss://...livekit.cloud)'
}
if (-not $LiveKitApiKey) {
    $LiveKitApiKey = Read-Host 'LiveKit Cloud API key'
}
if (-not $LiveKitApiSecret) {
    $LiveKitApiSecret = Read-Host 'LiveKit Cloud API secret' -AsSecureString
}

if ($LiveKitUrl -notmatch '^wss://[^/]+(?:/.*)?$') {
    throw 'The LiveKit Project URL must start with wss://.'
}
if ($LiveKitUrl -match '(?i)(localhost|127\.0\.0\.1|192\.168\.|10\.|172\.(1[6-9]|2\d|3[01])\.)') {
    throw 'The LiveKit Project URL must be publicly reachable, not a local or private-network address.'
}
if ([string]::IsNullOrWhiteSpace($LiveKitApiKey) -or $LiveKitApiKey -eq 'devkey') {
    throw 'Enter the API key from your LiveKit Cloud project.'
}

$secretPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($LiveKitApiSecret)
try {
    $plainSecret = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($secretPointer)
    if ([string]::IsNullOrWhiteSpace($plainSecret) -or $plainSecret -eq 'lets-cook-dev-livekit-secret-32-chars') {
        throw 'Enter the API secret from your LiveKit Cloud project.'
    }

    $values = [ordered]@{
        LIVEKIT_PUBLIC_URL = $LiveKitUrl.Trim()
        LIVEKIT_API_KEY = $LiveKitApiKey.Trim()
        LIVEKIT_API_SECRET = $plainSecret
    }

    $lines = if (Test-Path -LiteralPath $envPath) {
        [Collections.Generic.List[string]]@(Get-Content -LiteralPath $envPath)
    } else {
        [Collections.Generic.List[string]]::new()
    }

    foreach ($entry in $values.GetEnumerator()) {
        $replacement = "$($entry.Key)=$($entry.Value)"
        $index = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match "^\s*$([regex]::Escape($entry.Key))\s*=") {
                $index = $i
                break
            }
        }
        if ($index -ge 0) {
            $lines[$index] = $replacement
        } else {
            $lines.Add($replacement)
        }
    }

    Set-Content -LiteralPath $envPath -Value $lines -Encoding utf8
} finally {
    if ($secretPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($secretPointer)
    }
    $plainSecret = $null
}

Write-Host ''
Write-Host 'Global LiveKit media is configured in the local git-ignored .env file.' -ForegroundColor Green
Write-Host 'Start Internet UAT with:' -ForegroundColor DarkGray
Write-Host '  .\scripts\start-global-uat.ps1' -ForegroundColor Cyan

