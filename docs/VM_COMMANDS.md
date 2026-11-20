# Xynk Oracle VM LiveKit commands

These are the deployment and verification commands used or their reproducible equivalents. Earlier Plink sessions were noninteractive, so Bash did not save them in `history`. API key and secret values are intentionally omitted.

## Connect and inspect

In the saved PuTTY window:

```bash
tmux attach -t xynk
history
sudo journalctl -u livekit -n 100 --no-pager
sudo journalctl -u caddy -n 100 --no-pager
sudo dnf history
```

Within tmux, press `Ctrl+B`, then `Page Up` to scroll back. Press `q` to leave scroll mode.

## Software and services

```bash
# LiveKit Server was installed from its official get.livekit.io installer.
curl -fsSL https://get.livekit.io -o /tmp/get-livekit.sh
bash /tmp/get-livekit.sh
sudo dnf -y install redis tmux
sudo dnf -y copr enable @caddy/caddy
sudo dnf -y install caddy
sudo systemctl enable --now redis
sudo systemctl enable --now livekit
sudo systemctl enable --now caddy
```

The LiveKit configuration and systemd unit were installed by [setup-vm-livekit.ps1](../backend/scripts/prod/setup-vm-livekit.ps1) from Windows. It reads or creates `LIVEKIT_VM_API_KEY` and `LIVEKIT_VM_API_SECRET` in the private `%USERPROFILE%\.letscook\secrets\native-google.env` file and sends them to `/etc/livekit/livekit.yaml` on the VM. Do not paste those values into a chat or shell history.

The Caddyfile on the VM is:

```caddyfile
media.xynk.in {
    reverse_proxy 127.0.0.1:7880
}
```

## Network configuration

The following VM firewall commands were run. Matching ingress rules were added in the Oracle Cloud security list; `media.xynk.in` was added as a DNS-only A record in Cloudflare pointing to `130.210.121.117`.

```bash
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --permanent --add-port=7881/tcp
sudo firewall-cmd --permanent --add-port=7882/udp
sudo firewall-cmd --permanent --add-port=3478/udp
sudo firewall-cmd --reload
sudo firewall-cmd --list-ports
```

The UDP buffer setting is in `/etc/sysctl.d/99-livekit.conf`:

```text
net.core.rmem_max = 5000000
net.core.wmem_max = 5000000
```

## Health checks

```bash
systemctl is-active livekit redis caddy
curl -i http://127.0.0.1:7880/
curl -i https://media.xynk.in/
sudo ss -lntup | grep -E ':(80|443|7880|7881|7882|3478)'
sudo journalctl -fu livekit
```

An external Windows LiveKit CLI publisher and subscriber connected to `wss://media.xynk.in` in room `xynk-vm-smoke`; the subscriber reported the publisher's video track. The VM service log recorded UDP WebRTC connections and track forwarding. The CLI processes are test-only and should be stopped after verification.

For the audio test, the Windows LiveKit CLI was given `LIVEKIT_URL=wss://media.xynk.in` plus the VM key and secret from the private secrets file, then ran:

```powershell
lk perf load-test --room xynk-vm-audio-smoke --duration 25s --audio-publishers 1 --subscribers 1 --num-per-second 2
```

Result: the subscriber received the audio track, 1,247 packets at 20.7 kbps, with 0 packet loss and no errors.
