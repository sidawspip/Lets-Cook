param(
    [Parameter(Mandatory = $true)][ValidatePattern('^wss://')][string]$PublicUrl,
    [Parameter(Mandatory = $true)][string]$ApiKey,
    [Parameter(Mandatory = $true)][securestring]$ApiSecret
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $projectRoot '.env'
$secretPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ApiSecret)
try {
    $plainSecret = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($secretPointer)
    $values = [ordered]@{
        LIVEKIT_MODE = 'self-hosted'
        LIVEKIT_SELF_HOSTED_URL = $PublicUrl.Trim()
        LIVEKIT_SELF_HOSTED_API_KEY = $ApiKey.Trim()
        LIVEKIT_SELF_HOSTED_API_SECRET = $plainSecret
    }
    $lines = if (Test-Path -LiteralPath $envPath) {
        [Collections.Generic.List[string]]@(Get-Content -LiteralPath $envPath)
    } else { [Collections.Generic.List[string]]::new() }
    foreach ($entry in $values.GetEnumerator()) {
        $replacement = "$($entry.Key)=$($entry.Value)"
        $index = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match "^\s*$([regex]::Escape($entry.Key))\s*=") { $index = $i; break }
        }
        if ($index -ge 0) { $lines[$index] = $replacement } else { $lines.Add($replacement) }
    }
    Set-Content -LiteralPath $envPath -Value $lines -Encoding utf8
} finally {
    if ($secretPointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($secretPointer) }
    $plainSecret = $null
}

Write-Host 'Self-hosted LiveKit mode is configured. Restart the backend to apply it.' -ForegroundColor Green
Write-Host 'The URL must resolve publicly with trusted TLS; the static IP alone is not a client URL.' -ForegroundColor DarkGray
