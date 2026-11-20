param(
    [string]$SecureDirectory = (Join-Path $env:USERPROFILE '.letscook\secrets'),
    [string]$Alias = 'letscook',
    [string]$DistinguishedName = 'CN=XYNK, OU=Mobile, O=XYNK, L=Delhi, ST=Delhi, C=IN'
)

$ErrorActionPreference = 'Stop'
$keystorePath = Join-Path $SecureDirectory 'android-release.p12'
$propertiesPath = Join-Path $SecureDirectory 'android-signing.properties'

if ((Test-Path $keystorePath) -or (Test-Path $propertiesPath)) {
    throw "Production signing material already exists in $SecureDirectory. Refusing to overwrite it."
}

New-Item -ItemType Directory -Path $SecureDirectory -Force | Out-Null

$principal = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
& icacls.exe $SecureDirectory /inheritance:r /grant:r "${principal}:(OI)(CI)F" | Out-Null

$bytes = New-Object byte[] 32
[System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
$password = [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')

$keytool = (Get-Command keytool.exe -ErrorAction Stop).Source
& $keytool -genkeypair -noprompt `
    -alias $Alias `
    -keyalg RSA `
    -keysize 4096 `
    -validity 10000 `
    -storetype PKCS12 `
    -keystore $keystorePath `
    -storepass $password `
    -keypass $password `
    -dname $DistinguishedName | Out-Null

$portablePath = $keystorePath.Replace('\', '/')
@(
    "storeFile=$portablePath"
    "storePassword=$password"
    "keyAlias=$Alias"
    "keyPassword=$password"
) | Set-Content -LiteralPath $propertiesPath -Encoding utf8NoBOM

& icacls.exe $keystorePath /inheritance:r /grant:r "${principal}:F" | Out-Null
& icacls.exe $propertiesPath /inheritance:r /grant:r "${principal}:F" | Out-Null

Write-Output "Created protected Android production signing material in $SecureDirectory"
& $keytool -list -v -keystore $keystorePath -storepass $password -alias $Alias |
    Select-String -Pattern '^\s*SHA1:|^\s*SHA256:'
