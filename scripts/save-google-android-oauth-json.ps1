param(
    [string]$SecureDirectory = (Join-Path $env:USERPROFILE '.letscook\secrets'),
    [string]$ClientId = '964609721877-aoj08ifhb1i3usckbm1095q4bmusak52.apps.googleusercontent.com',
    [string]$ProjectId = 'letscook-510611'
)

$ErrorActionPreference = 'Stop'
$outputPath = Join-Path $SecureDirectory 'google-android-production.oauth.json'

if (Test-Path -LiteralPath $outputPath) {
    throw "OAuth metadata already exists at $outputPath. Refusing to overwrite it."
}

New-Item -ItemType Directory -Path $SecureDirectory -Force | Out-Null
$principal = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
& icacls.exe $SecureDirectory /inheritance:r /grant:r "${principal}:(OI)(CI)F" | Out-Null

$oauthMetadata = [ordered]@{
    installed = [ordered]@{
        client_id = $ClientId
        project_id = $ProjectId
        auth_uri = 'https://accounts.google.com/o/oauth2/auth'
        token_uri = 'https://oauth2.googleapis.com/token'
        auth_provider_x509_cert_url = 'https://www.googleapis.com/oauth2/v1/certs'
    }
}

$oauthMetadata |
    ConvertTo-Json -Depth 3 |
    Set-Content -LiteralPath $outputPath -Encoding utf8NoBOM

& icacls.exe $outputPath /inheritance:r /grant:r "${principal}:F" | Out-Null
Write-Output "Created protected Android OAuth metadata at $outputPath"
