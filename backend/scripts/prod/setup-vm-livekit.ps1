$ErrorActionPreference = 'Stop'
$plink = 'C:\Program Files\PuTTY\plink.exe'
$hostKey = 'SHA256:gZM7HbLlmhBBNnKNSYXr3X5RlU4vJ3Bs019dXhizTAY'
$secretFile = Join-Path $env:USERPROFILE '.letscook\secrets\native-google.env'

if (-not (Test-Path -LiteralPath $plink)) { throw 'PuTTY Plink is not installed.' }
if (-not (Test-Path -LiteralPath $secretFile)) { throw 'Private secrets file is missing.' }

$lines = [Collections.Generic.List[string]]::new()
foreach ($line in Get-Content -LiteralPath $secretFile) { $lines.Add($line) }
function Get-SecretValue([string]$name) {
    foreach ($line in $lines) {
        if ($line.StartsWith("$name=")) { return $line.Substring($name.Length + 1) }
    }
    return $null
}
function Set-SecretValue([string]$name, [string]$value) {
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].StartsWith("$name=")) {
            $lines[$i] = "$name=$value"
            return
        }
    }
    $lines.Add("$name=$value")
}

$apiKey = Get-SecretValue 'LIVEKIT_VM_API_KEY'
$apiSecret = Get-SecretValue 'LIVEKIT_VM_API_SECRET'
if (-not $apiKey -or -not $apiSecret) {
    $apiKey = 'xynkvm_' + [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(8)).ToLowerInvariant()
    $apiSecret = [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).ToLowerInvariant()
    Set-SecretValue 'LIVEKIT_VM_API_KEY' $apiKey
    Set-SecretValue 'LIVEKIT_VM_API_SECRET' $apiSecret
    Set-Content -LiteralPath $secretFile -Value $lines -Encoding utf8NoBOM
    $principal = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    & icacls.exe $secretFile /inheritance:r /grant:r "${principal}:F" | Out-Null
}

function Invoke-Vm([string]$command, [string]$inputText) {
    if ($null -eq $inputText) {
        & $plink -batch -load 'Xynk Oracle VM' -hostkey $hostKey $command
    } else {
        $inputText | & $plink -batch -load 'Xynk Oracle VM' -hostkey $hostKey $command
    }
    if ($LASTEXITCODE -ne 0) { throw "VM command failed (exit $LASTEXITCODE)." }
}

$config = @"
port: 7880
rtc:
  tcp_port: 7881
  udp_port: 7882
  use_external_ip: true
turn:
  enabled: true
  udp_port: 3478
redis:
  address: 127.0.0.1:6379
keys:
  ${apiKey}: $apiSecret
logging:
  level: info
"@

Invoke-Vm 'id livekit >/dev/null 2>&1 || sudo useradd --system --no-create-home --shell /sbin/nologin livekit; sudo install -d -o livekit -g livekit -m 750 /etc/livekit; sudo tee /etc/livekit/livekit.yaml >/dev/null; sudo chown livekit:livekit /etc/livekit/livekit.yaml; sudo chmod 640 /etc/livekit/livekit.yaml' $config

$unit = @'
[Unit]
Description=Xynk LiveKit media server
After=network-online.target redis.service
Wants=network-online.target
Requires=redis.service

[Service]
Type=simple
User=livekit
Group=livekit
ExecStart=/usr/local/bin/livekit-server --config /etc/livekit/livekit.yaml
Restart=on-failure
RestartSec=5
LimitNOFILE=65535
NoNewPrivileges=true
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
'@

Invoke-Vm 'sudo tee /etc/systemd/system/livekit.service >/dev/null; sudo systemctl daemon-reload; sudo systemctl enable --now livekit.service; systemctl is-active livekit.service' $unit
Invoke-Vm 'for i in $(seq 1 15); do if curl -fsS --max-time 2 http://127.0.0.1:7880/ >/dev/null; then echo "LiveKit signaling responds on loopback"; exit 0; fi; sleep 2; done; exit 1' $null
Write-Output 'VM LiveKit service installed and responding. Credentials are stored only in the private user secrets file and on the VM.'
