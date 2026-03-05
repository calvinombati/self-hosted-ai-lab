# 06 - OpenClaw

OpenClaw AI gateway: single-instance setup and multi-instance provisioning. Runs as a native Node.js application with systemd, accessed via SSH tunnel only.

## Placeholders

| Placeholder | Description | Example |
|---|---|---|
| `<USER>` | Server admin username | `deploy` |
| `<IP_ADDRESS>` | Server IPv4 | `203.0.113.10` |
| `<OC_NAME>` | Instance short name | `acme` |
| `<OC_PORT>` | Instance port (*789 pattern) | `18789` |

## Architecture

```
Internet --> SSH Tunnel --> localhost:<OC_PORT> --> OpenClaw Gateway
                                               └-> systemd service
                                               └-> User oc-<OC_NAME> (limited permissions)
```

Security model:
- Bound to `127.0.0.1` only - not exposed on any public interface
- Access exclusively via SSH tunnel from your client
- Dedicated system user per instance with permissions limited to its home directory
- API keys protected with `600` permissions
- No firewall ports to open (not on UFW, not on provider firewall)

> Note: OpenClaw is installed natively (Node.js + systemd) instead of Docker. The application requires an interactive onboarding wizard (`openclaw onboard`) and stores config in `~/.openclaw/config.json`. Containerization would add complexity without real benefit for a single-user gateway.

## Part A - Single instance

### Step 1 - Create dedicated user

```bash
sudo useradd -r -s /bin/bash -d /srv/oc-<OC_NAME> -m oc-<OC_NAME>
```

Verify:

```bash
ls -la /srv/ | grep oc-<OC_NAME>
```

Verify: directory exists, owned by `oc-<OC_NAME>`.

### Step 2 - Install nvm + Node.js

```bash
sudo su - oc-<OC_NAME> << 'SETUP'
# Install nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.2/install.sh | bash

# Load nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Install Node.js 22 LTS
nvm install 22
echo "Node.js: $(node --version)"
SETUP
```

Verify:

```bash
sudo su - oc-<OC_NAME> -c "node --version"
```

Verify: output is `v22.x.x`.

> Note: nvm URL contains an explicit version (`v0.40.2`) that does not auto-update. Check [nvm releases](https://github.com/nvm-sh/nvm/releases) before a new provisioning.

### Step 3 - Install OpenClaw

```bash
sudo su - oc-<OC_NAME> -c "npm install -g openclaw@latest"
```

Verify:

```bash
sudo su - oc-<OC_NAME> -c "openclaw --version && which openclaw"
```

Verify: version string and path like `/srv/oc-<OC_NAME>/.nvm/versions/node/v22.x.x/bin/openclaw`.

Save the full path from `which openclaw` - you need it for the systemd service.

### Step 4 - Onboarding (interactive)

```bash
sudo su - oc-<OC_NAME>
cd /srv/oc-<OC_NAME>
openclaw onboard
# Follow the wizard: select provider, enter API key
exit
```

Verify config permissions:

```bash
sudo ls -la /srv/oc-<OC_NAME>/.openclaw/config.json
```

Verify: permissions are `-rw-------` (600). If not:

```bash
sudo chmod 600 /srv/oc-<OC_NAME>/.openclaw/config.json
```

### Step 5 - Create systemd service

Replace `<OPENCLAW_BIN_PATH>` with the full path from Step 3.

```bash
sudo tee /etc/systemd/system/oc-<OC_NAME>-gateway.service > /dev/null << EOF
[Unit]
Description=OpenClaw Gateway (oc-<OC_NAME>)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=oc-<OC_NAME>
WorkingDirectory=/srv/oc-<OC_NAME>
ExecStart=<OPENCLAW_BIN_PATH> gateway --port <OC_PORT>
Environment=HOME=/srv/oc-<OC_NAME>
Environment=NODE_ENV=production
StandardOutput=journal
StandardError=journal
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

### Step 6 - Enable and start

```bash
sudo systemctl daemon-reload
sudo systemctl enable oc-<OC_NAME>-gateway
sudo systemctl start oc-<OC_NAME>-gateway
```

Verify:

```bash
sudo systemctl status oc-<OC_NAME>-gateway
```

Verify: `active (running)`.

```bash
ss -tulpn | grep <OC_PORT>
```

Verify: listening on `127.0.0.1:<OC_PORT>`. If it shows `0.0.0.0:<OC_PORT>`, the service is publicly exposed - stop it immediately and investigate.

### Step 7 - Access via SSH tunnel

From your local machine:

```bash
ssh -L <OC_PORT>:localhost:<OC_PORT> <USER>@<IP_ADDRESS> -N
```

Open `http://localhost:<OC_PORT>` in your browser.

### Alternative: Tailscale (zero public ports)

Instead of SSH tunnels, you can use [Tailscale](https://tailscale.com/) for a persistent mesh VPN:

```bash
# On the server
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

Then access OpenClaw directly via the Tailscale IP (e.g., `http://100.x.y.z:<OC_PORT>`) from any device on your tailnet. No tunnel to manage, works from mobile, survives SSH disconnects.

> Note: Tailscale is free for personal use (up to 100 devices). If you use Tailscale, OpenClaw still binds to `127.0.0.1` - configure it to bind to `0.0.0.0` or the Tailscale interface instead, and restrict access via Tailscale ACLs. This is a more advanced setup covered in detail by [community guides](https://dev.to/nunc/self-hosting-openclaw-ai-assistant-on-a-vps-with-tailscale-vpn-zero-public-ports-35fn).

## Part B - Multi-instance provisioning

For multiple independent OpenClaw instances (per project, per client, per API key).

### Conventions

| Convention | Pattern | Example |
|---|---|---|
| Username | `oc-<name>` | `oc-acme`, `oc-beta` |
| Home directory | `/srv/oc-<name>/` | `/srv/oc-acme/` |
| Port | `N*1000+789` | 18789, 19789, 20789 |
| Service | `oc-<name>-gateway.service` | `oc-acme-gateway.service` |

The last 3 digits (`789`) are a "signature" to instantly recognize OpenClaw ports in `ss -tulpn` or logs.

### Instance registry

Create `/srv/openclaw-instances.conf`:

```bash
sudo tee /srv/openclaw-instances.conf > /dev/null << 'EOF'
# OpenClaw instance registry
# Format: USERNAME PORT  # optional comment
oc-acme  18789   # Acme Corp
oc-beta  19789   # Beta Inc
EOF
```

### Provisioning script

Copy `templates/openclaw-provision.sh` to the server:

```bash
sudo tee /usr/local/bin/openclaw-provision.sh > /dev/null < templates/openclaw-provision.sh
sudo chmod +x /usr/local/bin/openclaw-provision.sh
```

The script has two phases:

- **Phase 1 (setup):** creates user, installs nvm/Node.js/OpenClaw. Stops for manual onboarding.
- **Phase 2 (service):** creates systemd service, enables, starts, verifies binding.

### Batch provisioning workflow

```bash
# Phase 1: setup all instances
sudo openclaw-provision.sh batch /srv/openclaw-instances.conf setup

# Manual onboarding for each instance
sudo su - oc-acme
cd /srv/oc-acme && openclaw onboard
exit

sudo su - oc-beta
cd /srv/oc-beta && openclaw onboard
exit

# Phase 2: create services and start
sudo openclaw-provision.sh batch /srv/openclaw-instances.conf service

# Verify all instances
sudo openclaw-provision.sh status
```

### Multi-instance SSH tunnel

```bash
ssh -L 18789:localhost:18789 \
    -L 19789:localhost:19789 \
    <USER>@<IP_ADDRESS> -N
```

Or add to `~/.ssh/config`:

```
Host oc-tunnel
    HostName <IP_ADDRESS>
    User <USER>
    LocalForward 18789 127.0.0.1:18789    # oc-acme
    LocalForward 19789 127.0.0.1:19789    # oc-beta
```

Then: `ssh -N oc-tunnel`

## Management commands

```bash
# Status
sudo systemctl status oc-<OC_NAME>-gateway

# Live logs
sudo journalctl -u oc-<OC_NAME>-gateway -f

# Restart
sudo systemctl restart oc-<OC_NAME>-gateway

# Update OpenClaw
sudo su - oc-<OC_NAME> -c "npm update -g openclaw"
sudo systemctl restart oc-<OC_NAME>-gateway

# Modify API keys
sudo su - oc-<OC_NAME>
openclaw configure
exit
sudo systemctl restart oc-<OC_NAME>-gateway

# All instances status
sudo openclaw-provision.sh status
```

## Troubleshooting

| Problem | Diagnosis | Fix |
|---|---|---|
| Service won't start | `sudo systemctl status oc-<OC_NAME>-gateway -l` | Verify ExecStart path: `sudo su - oc-<OC_NAME> -c "which openclaw"` |
| Port already in use | `ss -tulpn \| grep <OC_PORT>` | Kill the process: `sudo kill $(sudo lsof -t -i :<OC_PORT>)` |
| `openclaw: command not found` in service | Wrong nvm path in ExecStart | Update path with correct Node.js version |
| SSH tunnel won't connect | `ssh -v -L <OC_PORT>:localhost:<OC_PORT> <USER>@<IP_ADDRESS>` | Check service is running, port 22 is accessible |
| Empty journalctl output | Service active but no logs | Add `StandardOutput=journal` to service file, reload, restart |

## Checklist (per instance)

- [ ] Dedicated user created with home in `/srv/oc-<OC_NAME>/`
- [ ] nvm installed
- [ ] Node.js 22+ installed via nvm
- [ ] OpenClaw installed
- [ ] Onboarding completed, API keys configured
- [ ] config.json permissions are `600`
- [ ] systemd service created with correct ExecStart path
- [ ] Service enabled and running
- [ ] Listening on `127.0.0.1:<OC_PORT>` (verified with `ss`)
- [ ] SSH tunnel works from local machine
- [ ] Web access on `http://localhost:<OC_PORT>` works
- [ ] (Multi-instance) `/srv/openclaw-instances.conf` updated
- [ ] (Multi-instance) SSH config updated with all `LocalForward` entries

## Next

Proceed to [07-monitoring.md](07-monitoring.md).
