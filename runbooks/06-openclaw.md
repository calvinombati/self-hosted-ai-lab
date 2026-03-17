# 06 - OpenClaw

OpenClaw AI gateway: single-instance setup and multi-instance provisioning. Runs as a native Node.js application with systemd, accessed via SSH tunnel only.

## Placeholders

| Placeholder | Description | Example |
|---|---|---|
| `<USER>` | Server admin username | `deploy` |
| `<IP_ADDRESS>` | Server IPv4 | `203.0.113.10` |
| `<OC_NAME>` | Instance short name | `work` |
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

> Note: OpenClaw is installed natively (Node.js + systemd) instead of Docker. The application requires an interactive onboarding wizard (`openclaw onboard`) and stores config in `~/.openclaw/openclaw.json`. Containerization would add complexity without real benefit for a single-user gateway.

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

### Step 2 - Install Node.js (system, once per server)

Node.js is installed at the system level via NodeSource. This step runs **once per server** as your admin user — not repeated for each instance. All `oc-*` instances share the same system binary (`/usr/bin/node`).

```bash
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs
```

Verify:

```bash
node --version
npm --version
```

Verify: output is `v22.x.x`. Skip this step if Node.js 22+ is already installed.

> Note: the system Node.js path (`/usr/bin/node`) is stable and does not change with upgrades. This makes the systemd service file reliable — the entrypoint path written by `openclaw gateway install` stays valid after Node.js upgrades.

### Step 3 - Install OpenClaw

Configure the per-user npm prefix and install OpenClaw. The prefix `~/.local` keeps binaries in `~/.local/bin` without requiring root.

```bash
sudo -u oc-<OC_NAME> bash -l << 'SETUP'
mkdir -p "$HOME/.local/bin"
npm config set prefix "$HOME/.local"

if ! grep -q '.local/bin' "$HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi

PATH="$HOME/.local/bin:$PATH" npm install -g openclaw@latest
echo "OpenClaw: $(PATH="$HOME/.local/bin:$PATH" openclaw --version)"
SETUP
```

Verify:

```bash
sudo su - oc-<OC_NAME> -c "openclaw --version && which openclaw"
```

Verify: version string and path like `/srv/oc-<OC_NAME>/.local/bin/openclaw`.

### Step 4 - Onboarding (interactive)

SSH directly as the instance user (same session you'll continue using in Step 7):

```bash
ssh oc-<OC_NAME>@<IP_ADDRESS>
openclaw onboard
# Follow the wizard: select provider, enter API key
```

Stay in this SSH session to continue with the steps below.

Verify config permissions (still in the SSH session as oc-<OC_NAME>):

```bash
ls -la ~/.openclaw/openclaw.json
```

Verify: permissions are `-rw-------` (600). If not:

```bash
chmod 600 ~/.openclaw/openclaw.json
```

### Step 5 - Install skill dependencies

During onboarding the wizard lets you enable skills and hooks. The recommended minimum set is:

**Skills:** `openai-whisper`, `nano-pdf`, `summarize`, `github`
**Hooks:** `boot-md`, `bootstrap-extra-files`, `command-logger`, `session-memory`

These skills require external dependencies. Some are shared system packages (install once as admin), others are per-user (install for each `oc-*` user).

> Note: if you enable additional skills beyond this set, check their dependencies with `openclaw doctor` and apply the same global/local criteria described here.

#### Global dependencies (once, as admin)

These are system-wide packages shared by all `oc-*` instances. Run as your admin user:

```bash
# ffmpeg - audio/video processing (whisper, media skills)
sudo apt install -y ffmpeg

# gh - GitHub CLI (github skill)
sudo apt install -y gh

# uv - Python package manager (Python-based skills: whisper, nano-pdf)
curl -LsSf https://astral.sh/uv/install.sh | sh
sudo cp ~/.local/bin/uv ~/.local/bin/uvx /usr/local/bin/
```

Verify:

```bash
ffmpeg -version | head -1
gh --version
uv --version
```

#### Per-user dependencies (for each oc-* user)

```bash
sudo -u oc-<OC_NAME> bash -c '
  export HOME=/srv/oc-<OC_NAME>
  export PATH=/srv/oc-<OC_NAME>/.local/bin:$PATH

  # @steipete/summarize - web/document summarization (summarize skill)
  npm install -g @steipete/summarize
'
```

Verify all dependencies are detected:

```bash
sudo -u oc-<OC_NAME> bash -c '
  export HOME=/srv/oc-<OC_NAME>
  export PATH=/srv/oc-<OC_NAME>/.local/bin:$PATH
  openclaw doctor
'
```

The "Skills status" section should show no missing requirements for the enabled skills. Warnings about linger not being enabled and the gateway service not yet being installed are expected — they are resolved in Steps 6 and 7.

#### Memory search (optional but recommended)

The `session-memory` hook uses semantic search (vector embeddings) to recall previous conversations. This requires an embedding provider with an API key. If you authenticated the main agent via OAuth (e.g., OpenAI Pro subscription), the OAuth token does not cover the embedding API - you need a separate API key.

The API key is used **only** for embeddings. The main agent continues to use OAuth for conversations - no API credits are consumed for chat.

You do not need to configure the provider explicitly. When no provider is set, openclaw uses `auto` and picks a provider based on what credentials are available in the credential store.

##### Step A - create the env file

```bash
echo "OPENAI_API_KEY=<YOUR_OPENAI_API_KEY>" | sudo tee /srv/oc-<OC_NAME>/.openclaw/env > /dev/null
sudo chown oc-<OC_NAME>:oc-<OC_NAME> /srv/oc-<OC_NAME>/.openclaw/env
sudo chmod 600 /srv/oc-<OC_NAME>/.openclaw/env
```

Do not put API keys directly in service files (they are readable by any user via `systemctl cat`).

##### Step B - register the key in the openclaw credential store

**This is the critical step.** The env file alone is not enough: openclaw looks for API keys in its own credential store (`auth-profiles.json`), not in the process environment. Even if `OPENAI_API_KEY` is exported in the shell or in the service, it is ignored unless registered in the store.

The official method is `paste-token`, which requires a TTY. Run it as the instance user via a direct SSH session:

```bash
ssh oc-<OC_NAME>@<IP_ADDRESS>
export PATH="$HOME/.local/bin:$PATH"
openclaw models auth paste-token --provider openai
# paste the key when prompted, then press enter
# creates profile openai:manual (paste-token default name)
```

**Workaround if TTY is not available** (e.g. from a script or `sudo -u`): write the profile directly into `auth-profiles.json`:

```bash
sudo -u oc-<OC_NAME> python3 - <<'EOF'
import json, os
path = os.path.expanduser("~/.openclaw/agents/main/agent/auth-profiles.json")
with open(path) as f:
    data = json.load(f)
data["profiles"]["openai:manual"] = {
    "type": "api_key",
    "provider": "openai",
    "apiKey": "sk-proj-<YOUR_OPENAI_API_KEY>"
}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
print("Done")
EOF
```

##### Step C - systemd drop-in to load the env file in the service

`openclaw gateway install` generates the service file without an `EnvironmentFile` directive. Add a drop-in that survives future `gateway install --force` calls:

```bash
sudo -u oc-<OC_NAME> bash -c '
  mkdir -p ~/.config/systemd/user/openclaw-gateway.service.d
  cat > ~/.config/systemd/user/openclaw-gateway.service.d/env.conf <<EOF
[Service]
EnvironmentFile=%h/.openclaw/env
EOF
'
```

Then reload and restart (via direct SSH as the instance user) — **after completing Step 7 (service install)**:

```bash
systemctl --user daemon-reload
openclaw gateway restart
```

##### Verify

```bash
ssh oc-<OC_NAME>@<IP_ADDRESS>
export PATH="$HOME/.local/bin:$PATH"
openclaw memory status --deep
```

Verify: `provider` is `openai` (or `auto`), `Embeddings: ready`, files indexed. If you skip this step, memory search falls back to `fts-only` (full-text search without vector embeddings).

### Step 6 - Enable linger

Before installing the service, enable **linger** for the instance user. This is required for two reasons:

1. The user service starts automatically at boot, even without an active login session
2. The user's systemd instance stays alive after SSH disconnects

```bash
sudo loginctl enable-linger oc-<OC_NAME>
```

Verify:

```bash
loginctl show-user oc-<OC_NAME> | grep Linger
```

Verify: `Linger=yes`.

### Step 7 - Install the service

OpenClaw manages its own service file via CLI. You must run this step **as the instance user via a direct SSH session** — not via `sudo su` or `sudo -u`.

**Why direct SSH is required:** `openclaw gateway install` creates a systemd user service and registers it via `systemctl --user`. This command requires `XDG_RUNTIME_DIR=/run/user/<uid>/` (the directory where the user's D-Bus socket lives) to be set. PAM only initializes this at login time. When you use `sudo su - oc-<OC_NAME>` or `sudo -u oc-<OC_NAME>` from another user, PAM does not create a full user session, `XDG_RUNTIME_DIR` is not set, and `systemctl --user` fails with "Failed to connect to bus". Direct SSH login is the only reliable way to get a complete PAM session.

If you are continuing from Step 4 you are already in the right session. Otherwise:

```bash
ssh oc-<OC_NAME>@<IP_ADDRESS>
```

Then:

```bash
openclaw gateway install
```

OpenClaw generates the service file automatically with the correct entrypoint, PATH, and environment variables. No manual editing required. To reinstall (e.g. after an OpenClaw update that changes the entrypoint):

```bash
openclaw gateway install --force
```

Verify:

```bash
openclaw gateway status
```

Verify: `Runtime: running` and no warnings about service config.

```bash
ss -tulpn | grep <OC_PORT>
```

Verify: listening on `127.0.0.1:<OC_PORT>`. If it shows `0.0.0.0:<OC_PORT>`, the service is publicly exposed - stop it immediately and investigate.

### Step 8 - Access via SSH tunnel

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
| Username | `oc-<name>` | `oc-work`, `oc-personal` |
| Home directory | `/srv/oc-<name>/` | `/srv/oc-work/` |
| Port | `N*1000+789` | 18789, 19789, 20789 |
| Service | `openclaw-gateway.service` (same for all instances) | `openclaw-gateway.service` |

The last 3 digits (`789`) are a "signature" to instantly recognize OpenClaw ports in `ss -tulpn` or logs.

### Instance registry

Create `/srv/openclaw-instances.conf`:

```bash
sudo tee /srv/openclaw-instances.conf > /dev/null << 'EOF'
# OpenClaw instance registry
# Format: USERNAME PORT  # optional comment
oc-work  18789   # Work projects
oc-personal  19789   # Personal use
EOF
```

### Provisioning script

Copy `templates/openclaw-provision.sh` to the server. From your **local machine** (where you cloned this repo):

```bash
scp templates/openclaw-provision.sh <USER>@<IP_ADDRESS>:/tmp/
```

Then on the **server**:

```bash
sudo mv /tmp/openclaw-provision.sh /usr/local/bin/openclaw-provision.sh
sudo chmod +x /usr/local/bin/openclaw-provision.sh
```

The script has two phases:

- **Phase 1 (setup):** creates user, configures npm prefix, installs OpenClaw (requires system Node.js), enables linger. Stops for manual onboarding.
- **Phase 2 (post-onboard):** runs `openclaw gateway install`, installs per-user npm packages, verifies binding. Must run as the instance user via direct SSH.

### Provisioning workflow

> **Prerequisite:** each instance user must be allowed to SSH directly. Add them to `AllowUsers` in your SSH hardening config (e.g. `/etc/ssh/sshd_config.d/99-hardening.conf`) before running post-onboard:
> ```
> AllowUsers <USER> oc-work oc-personal
> ```
> Then reload: `sudo systemctl reload sshd`

Phase 1 (user/openclaw setup) can run in batch as root. Phase 2 (service install) **cannot be batched** — it requires a direct SSH session per user for the reasons explained in Step 7. Onboarding is also interactive by design.

```bash
# Phase 1: setup all instances (can run in batch as root)
sudo openclaw-provision.sh batch /srv/openclaw-instances.conf
```

Then, for each instance, open a direct SSH session and complete onboarding and post-onboard setup:

```bash
# Onboard and install service — must be done via direct SSH as each user
ssh oc-work@<IP_ADDRESS>
openclaw onboard       # interactive wizard: provider, API key, channel, skills
openclaw-provision.sh post-onboard   # gateway install, npm deps, verify
exit

ssh oc-personal@<IP_ADDRESS>
openclaw onboard
openclaw-provision.sh post-onboard
exit
```

Verify all instances:

```bash
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
    LocalForward 18789 127.0.0.1:18789    # oc-work
    LocalForward 19789 127.0.0.1:19789    # oc-personal
```

Then: `ssh -N oc-tunnel`

## Management commands

Run as the instance user via direct SSH:

```bash
ssh oc-<OC_NAME>@<IP_ADDRESS>

# Status (shows service warnings if service file is outdated)
openclaw gateway status

# Health check (channels, agent, sessions)
openclaw health

# Full diagnostics
openclaw doctor

# Restart
openclaw gateway restart

# Update OpenClaw and refresh service file
npm update -g openclaw
openclaw gateway install --force
openclaw gateway restart

# Update API key (overwrites existing profile without creating duplicates)
openclaw models auth paste-token --provider anthropic --profile-id anthropic:default

# Remove a stale profile created by the wizard
openclaw config unset 'auth.profiles.anthropic:manual'
```

Live logs (run as admin with sudo):

```bash
# Find the UID of the instance user
id -u oc-<OC_NAME>

# Live logs
sudo journalctl -u "user@<UID>.service" -f

# Last 100 lines
sudo journalctl -u "user@<UID>.service" -n 100
```

All instances status (run as admin):

```bash
sudo openclaw-provision.sh status
```

## Troubleshooting

| Problem | Diagnosis | Fix |
|---|---|---|
| `gateway install` fails with "Failed to connect to bus" | Running via `sudo su` instead of direct SSH | SSH directly as the instance user: `ssh oc-<OC_NAME>@<IP>` |
| Service won't start at boot | `loginctl show-user oc-<OC_NAME> \| grep Linger` | Enable linger: `sudo loginctl enable-linger oc-<OC_NAME>` |
| Service file outdated after update | `openclaw gateway status` shows warnings | Run `openclaw gateway install --force` via direct SSH as instance user |
| Port already in use | `ss -tulpn \| grep <OC_PORT>` | Kill the process: `sudo kill $(sudo lsof -t -i :<OC_PORT>)` |
| SSH tunnel won't connect | `ssh -v -L <OC_PORT>:localhost:<OC_PORT> <USER>@<IP_ADDRESS>` | Check service is running, port 22 is accessible |
| API key rejected | `openclaw models status` via SSH as instance user | Use `openclaw models auth paste-token --provider anthropic --profile-id anthropic:default` |

## Checklist (per instance)

- [ ] Dedicated user created with home in `/srv/oc-<OC_NAME>/`
- [ ] System Node.js 22+ installed via NodeSource (once per server)
- [ ] npm prefix `~/.local` configured for instance user
- [ ] OpenClaw installed
- [ ] Onboarding completed, API keys configured (done via direct SSH as instance user)
- [ ] Global dependencies installed (ffmpeg, gh, uv) - once per server
- [ ] Per-user dependencies installed (@steipete/summarize)
- [ ] `openclaw doctor` shows no missing requirements for enabled skills
- [ ] (Optional) Memory search configured with embedding provider and env file
- [ ] Linger enabled: `loginctl show-user oc-<OC_NAME> | grep Linger` → `Linger=yes`
- [ ] `openclaw gateway install` run via direct SSH as instance user
- [ ] `openclaw gateway status` shows no warnings
- [ ] Listening on `127.0.0.1:<OC_PORT>` (verified with `ss -tulpn | grep <OC_PORT>`)
- [ ] SSH tunnel works from local machine
- [ ] Web access on `http://localhost:<OC_PORT>` works
- [ ] (Multi-instance) `/srv/openclaw-instances.conf` updated
- [ ] (Multi-instance) SSH config updated with all `LocalForward` entries

## Next

Proceed to [07-monitoring.md](07-monitoring.md).
