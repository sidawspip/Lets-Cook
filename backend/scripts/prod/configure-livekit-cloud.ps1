param(
    [string]$LiveKitUrl,
    [string]$LiveKitApiKey,
    [securestring]$LiveKitApiSecret
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$envPath = Join-Path $projectRoot '.env'
$examplePath = Join-Path $projectRoot '.env.example'
$secureEnvPath = if ($env:LETSCOOK_SECURE_ENV) {
    $env:LETSCOOK_SECURE_ENV
} else {
    Join-Path $env:USERPROFILE '.letscook\secrets\native-google.env'
}

$exampleLines = [Collections.Generic.List[string]]::new()
if (Test-Path -LiteralPath $examplePath) {
    foreach ($line in (Get-Content -LiteralPath $examplePath)) { $exampleLines.Add($line) }
}
function Get-ExampleValue([string]$name) {
    foreach ($line in $exampleLines) {
        if ($line -match "^\s*$([regex]::Escape($name))\s*=(.*)$") {
            return $Matches[1].Trim()
        }
    }
    return ''
}

if (-not $LiveKitUrl) { $LiveKitUrl = Get-ExampleValue 'LIVEKIT_CLOUD_URL' }
if (-not $LiveKitApiKey) { $LiveKitApiKey = Get-ExampleValue 'LIVEKIT_CLOUD_API_KEY' }
if (-not $LiveKitApiSecret) {
    $exampleSecret = Get-ExampleValue 'LIVEKIT_CLOUD_API_SECRET'
    if ($exampleSecret) {
        $LiveKitApiSecret = ConvertTo-SecureString $exampleSecret -AsPlainText -Force
    }
    $exampleSecret = $null
}

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
        LIVEKIT_CLOUD_URL = $LiveKitUrl.Trim()
        LIVEKIT_CLOUD_API_KEY = $LiveKitApiKey.Trim()
        LIVEKIT_CLOUD_API_SECRET = $plainSecret
    }

    $secureDirectory = Split-Path -Parent $secureEnvPath
    New-Item -ItemType Directory -Path $secureDirectory -Force | Out-Null
    $lines = [Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $secureEnvPath) {
        foreach ($line in (Get-Content -LiteralPath $secureEnvPath)) { $lines.Add($line) }
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

    Set-Content -LiteralPath $secureEnvPath -Value $lines -Encoding utf8NoBOM
    $principal = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    & icacls.exe $secureEnvPath /inheritance:r /grant:r "${principal}:F" | Out-Null

    $projectLines = [Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $envPath) {
        foreach ($line in (Get-Content -LiteralPath $envPath)) { $projectLines.Add($line) }
    }
    for ($i = $projectLines.Count - 1; $i -ge 0; $i--) {
        if ($projectLines[$i] -match '^\s*LIVEKIT_CLOUD_(URL|API_KEY|API_SECRET)\s*=') {
            $projectLines.RemoveAt($i)
        }
    }
    $modeIndex = -1
    for ($i = 0; $i -lt $projectLines.Count; $i++) {
        if ($projectLines[$i] -match '^\s*LIVEKIT_MODE\s*=') { $modeIndex = $i; break }
    }
    if ($modeIndex -ge 0) {
        $projectLines[$modeIndex] = 'LIVEKIT_MODE=cloud'
    } else {
        $projectLines.Add('LIVEKIT_MODE=cloud')
    }
    Set-Content -LiteralPath $envPath -Value $projectLines -Encoding utf8

    for ($i = 0; $i -lt $exampleLines.Count; $i++) {
        if ($exampleLines[$i] -match '^\s*(LIVEKIT_CLOUD_(URL|API_KEY|API_SECRET))\s*=') {
            $exampleLines[$i] = "$($Matches[1])="
        }
    }
    Set-Content -LiteralPath $examplePath -Value $exampleLines -Encoding utf8
} finally {
    if ($secretPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($secretPointer)
    }
    $plainSecret = $null
}

Write-Host ''
Write-Host 'Global LiveKit media is configured. Credentials are in the private user secrets file; .env contains only the mode switch.' -ForegroundColor Green
Write-Host 'Start Internet UAT with:' -ForegroundColor DarkGray
Write-Host '  .\infra\scripts\dev\start-global-uat.ps1' -ForegroundColor Cyan
