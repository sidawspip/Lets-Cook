param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('ClientId', 'ClientSecret')]
    [string]$Kind,
    [string]$SecureDirectory = (Join-Path $env:USERPROFILE '.letscook\secrets')
)

$ErrorActionPreference = 'Stop'
$value = (Get-Clipboard -Raw).Trim()
if (-not $value -or $value.Length -lt 8 -or $value -match '[\r\n]') {
    throw 'The clipboard does not contain one valid OAuth credential.'
}

$path = Join-Path $SecureDirectory 'x-oauth.env'
$settings = [ordered]@{}
if (Test-Path -LiteralPath $path) {
    Get-Content -LiteralPath $path | ForEach-Object {
        if ($_ -match '^([^#=]+)=(.*)$') { $settings[$matches[1]] = $matches[2] }
    }
}
$name = if ($Kind -eq 'ClientId') { 'X_CLIENT_ID' } else { 'X_CLIENT_SECRET' }
$settings[$name] = $value

New-Item -ItemType Directory -Path $SecureDirectory -Force | Out-Null
$principal = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
& icacls.exe $SecureDirectory /inheritance:r /grant:r "${principal}:(OI)(CI)F" | Out-Null
$settings.GetEnumerator() |
    ForEach-Object { "$($_.Key)=$($_.Value)" } |
    Set-Content -LiteralPath $path -Encoding utf8NoBOM
& icacls.exe $path /inheritance:r /grant:r "${principal}:F" | Out-Null
Set-Clipboard -Value ''
Write-Output "Stored $name in the protected X OAuth configuration and cleared the clipboard."
