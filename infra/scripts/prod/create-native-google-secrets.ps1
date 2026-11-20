param(
    [string]$SecureDirectory = (Join-Path $env:USERPROFILE '.letscook\secrets'),
    [string]$GoogleWebClientId = '964609721877-vne7f4q1uu6lb7oalj55h67irqm8hva5.apps.googleusercontent.com',
    [string]$GoogleAndroidClientId = '964609721877-aoj08ifhb1i3usckbm1095q4bmusak52.apps.googleusercontent.com',
    [string]$KeycloakClientId = 'lets-cook-native-google',
    [string]$GoogleClientSecret
)

$ErrorActionPreference = 'Stop'
$secretsPath = Join-Path $SecureDirectory 'native-google.env'
if (Test-Path $secretsPath) {
    throw "Native Google secrets already exist at $secretsPath. Refusing to overwrite them."
}

$googleClientSecret = if ($GoogleClientSecret) {
    $GoogleClientSecret.Trim()
} else {
    (Get-Clipboard -Raw).Trim()
}
if (-not $googleClientSecret.StartsWith('GOCSPX-')) {
    throw 'The clipboard does not contain the expected Google OAuth client secret.'
}

$bytes = New-Object byte[] 48
[System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
$keycloakClientSecret = [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')

New-Item -ItemType Directory -Path $SecureDirectory -Force | Out-Null
$principal = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
& icacls.exe $SecureDirectory /inheritance:r /grant:r "${principal}:(OI)(CI)F" | Out-Null

@(
    "GOOGLE_WEB_CLIENT_ID=$GoogleWebClientId"
    "GOOGLE_ANDROID_CLIENT_ID=$GoogleAndroidClientId"
    "GOOGLE_CLIENT_ID=$GoogleWebClientId"
    "GOOGLE_CLIENT_SECRET=$googleClientSecret"
    "KEYCLOAK_NATIVE_AUTH_CLIENT_ID=$KeycloakClientId"
    "KEYCLOAK_NATIVE_AUTH_CLIENT_SECRET=$keycloakClientSecret"
) | Set-Content -LiteralPath $secretsPath -Encoding utf8NoBOM

& icacls.exe $secretsPath /inheritance:r /grant:r "${principal}:F" | Out-Null
Set-Clipboard -Value ''
Write-Output "Created protected native Google configuration at $secretsPath and cleared the clipboard."
