param(
    [Parameter(Mandatory = $true)][ValidatePattern('^wss://')][string]$PublicUrl,
    [Parameter(Mandatory = $true)][string]$ApiKey,
    [Parameter(Mandatory = $true)][securestring]$ApiSecret
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$envPath = Join-Path $projectRoot '.env'
$secureEnvPath = if ($env:LETSCOOK_SECURE_ENV) { $env:LETSCOOK_SECURE_ENV } else { Join-Path $env:USERPROFILE '.letscook\secrets\native-google.env' }
$secretPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ApiSecret)
try {
    $plainSecret = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($secretPointer)
    $secureValues = [ordered]@{
        LIVEKIT_SELF_HOSTED_API_KEY = $ApiKey.Trim()
        LIVEKIT_SELF_HOSTED_API_SECRET = $plainSecret
        LIVEKIT_KEYS = "$($ApiKey.Trim()): $plainSecret"
    }
    $secureLines = [Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $secureEnvPath) {
        foreach ($line in (Get-Content -LiteralPath $secureEnvPath)) { $secureLines.Add($line) }
    }
    foreach ($entry in $secureValues.GetEnumerator()) {
        $replacement = "$($entry.Key)=$($entry.Value)"
        $index = -1
        for ($i = 0; $i -lt $secureLines.Count; $i++) {
            if ($secureLines[$i] -match "^\s*$([regex]::Escape($entry.Key))\s*=") { $index = $i; break }
        }
        if ($index -ge 0) { $secureLines[$index] = $replacement } else { $secureLines.Add($replacement) }
    }
    Set-Content -LiteralPath $secureEnvPath -Value $secureLines -Encoding utf8NoBOM
    $principal = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    & icacls.exe $secureEnvPath /inheritance:r /grant:r "${principal}:F" | Out-Null
    $projectLines = [Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $envPath) {
        foreach ($line in (Get-Content -LiteralPath $envPath)) { $projectLines.Add($line) }
    }
    for ($i = $projectLines.Count - 1; $i -ge 0; $i--) {
        if ($projectLines[$i] -match '^\s*LIVEKIT_SELF_HOSTED_API_(KEY|SECRET)\s*=') { $projectLines.RemoveAt($i) }
    }
    foreach ($entry in ([ordered]@{ LIVEKIT_MODE = 'self-hosted'; LIVEKIT_SELF_HOSTED_URL = $PublicUrl.Trim() }).GetEnumerator()) {
        $index = -1
        for ($i = 0; $i -lt $projectLines.Count; $i++) {
            if ($projectLines[$i] -match "^\s*$([regex]::Escape($entry.Key))\s*=") { $index = $i; break }
        }
        $replacement = "$($entry.Key)=$($entry.Value)"
        if ($index -ge 0) { $projectLines[$index] = $replacement } else { $projectLines.Add($replacement) }
    }
    Set-Content -LiteralPath $envPath -Value $projectLines -Encoding utf8NoBOM
} finally {
    if ($secretPointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($secretPointer) }
    $plainSecret = $null
}

Write-Host 'Self-hosted LiveKit mode is configured. Restart the backend to apply it.' -ForegroundColor Green
Write-Host 'The URL must resolve publicly with trusted TLS; the static IP alone is not a client URL.' -ForegroundColor DarkGray
