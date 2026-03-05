# 02 - Hardening

SSH hardening, Fail2Ban tuning, and dual-layer firewall architecture. This runbook explains and verifies the security configuration applied by cloud-init. Use it to modify settings or to harden a server that was not provisioned with cloud-init.

## Placeholders

| Placeholder | Description | Example |
|---|---|---|
| `<USER>` | Admin username | `deploy` |

## SSH hardening - drop-in file

The configuration uses OpenSSH 8.2+ drop-in mechanism: a file in `/etc/ssh/sshd_config.d/` instead of editing the main `sshd_config`. The `99-` prefix ensures it loads last and overrides defaults. This file is NOT overwritten by package upgrades.

### Verify current config

```bash
cat /etc/ssh/sshd_config.d/99-hardening.conf
```

Verify: file exists with the settings below.

### Apply manually (if not set by cloud-init)

```bash
sudo tee /etc/ssh/sshd_config.d/99-hardening.conf > /dev/null << 'EOF'
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
KbdInteractiveAuthentication no
AllowUsers <USER>
MaxAuthTries 3
LoginGraceTime 30
AuthorizedKeysFile .ssh/authorized_keys
EOF

sudo systemctl reload ssh
```

**Before reloading:** open a second SSH session as backup. If the new config locks you out, the existing session stays alive.

### Directive reference

| Directive | Value | Purpose |
|---|---|---|
| `PermitRootLogin` | `no` | Blocks direct root login, even with key |
| `PasswordAuthentication` | `no` | Key-only auth (no brute-force surface) |
| `PubkeyAuthentication` | `yes` | Enables public key authentication |
| `KbdInteractiveAuthentication` | `no` | Disables challenge-response (brute-force vector) |
| `AllowUsers` | `<USER>` | Explicit whitelist: only this user can SSH in |
| `MaxAuthTries` | `3` | Max 3 auth attempts per connection |
| `LoginGraceTime` | `30` | 30 seconds to authenticate, then disconnect |

### Verify active config

```bash
sudo sshd -T | grep -E 'permitrootlogin|passwordauthentication|pubkeyauthentication|allowusers|maxauthtries'
```

Verify: values match the table above.

## Fail2Ban

Configuration lives in `/etc/fail2ban/jail.local`.

### Verify current config

```bash
cat /etc/fail2ban/jail.local
```

### Parameters

| Parameter | Default | Recommended | Why |
|---|---|---|---|
| `bantime` | 600 (10 min) | 3600 (1 hour) | Longer bans discourage persistent bots |
| `maxretry` | 5 | 3 | Smaller window reduces brute-force attempts |
| `findtime` | 600 | 600 | 10-minute observation window is reasonable |
| `backend` | auto | systemd | Reads from journal, more reliable on modern Ubuntu |

### Apply manually (if not set by cloud-init)

```bash
sudo tee /etc/fail2ban/jail.local > /dev/null << 'EOF'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 3
mode     = normal
backend  = systemd

[sshd]
enabled = true
port    = 22
logpath = %(sshd_log)s
EOF

sudo systemctl restart fail2ban
```

### Monitoring commands

```bash
# Jail status
sudo fail2ban-client status sshd

# Unban a specific IP (if you banned yourself)
sudo fail2ban-client set sshd unbanip <IP_ADDRESS>

# Live log
sudo journalctl -u fail2ban -f
```

## Dual-layer firewall

Two independent firewalls with separate responsibilities:

**Layer 1 - Provider firewall (network level):** filters traffic before it reaches the server. Manages source IP restrictions (e.g., SSH only from your IP). Blocked traffic never hits the server.

**Layer 2 - UFW (software level):** filters at server level. Defines which ports are open regardless of source. Defense in depth: even if the provider firewall is misconfigured, UFW blocks everything not explicitly allowed.

### Provider firewall rules

Configure in your provider's console:

| Port | Protocol | Source | Service |
|---|---|---|---|
| 22 | TCP | `<YOUR_IP>/32` | SSH |
| 80 | TCP | `0.0.0.0/0` | HTTP |
| 443 | TCP | `0.0.0.0/0` | HTTPS |

### UFW rules (set by cloud-init)

```bash
sudo ufw status verbose
```

Verify:
```
Status: active
Default: deny (incoming), allow (outgoing)
22/tcp    ALLOW IN    Anywhere    # SSH
80/tcp    ALLOW IN    Anywhere    # HTTP
443/tcp   ALLOW IN    Anywhere    # HTTPS
```

> Note: UFW does not filter by source IP - that is the provider firewall's job. Duplicating IP filtering in both layers complicates maintenance when your dynamic IP changes (two places to update).

### Apply manually (if not set by cloud-init)

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp comment 'SSH'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw --force enable
```

## Security tools deliberately excluded

These tools appear in many older guides but have low ROI on a modern server in active development:

| Tool | Why excluded |
|---|---|
| **rkhunter** | Rootkit hunter from 2003. Rarely updated signatures, many false positives with Docker/Python. Signal-to-noise ratio too low. Alternative: Lynis for on-demand audits. |
| **AIDE** | File integrity monitoring. Valid concept, but on an evolving server (installing packages, changing configs) it generates constant misleading alerts. Reconsider when server stabilizes. |
| **logwatch** | Requires a configured MTA to be useful. Local reports to root go unread. Alternative: Dozzle for Docker logs, or n8n workflow for alerting. |
| **bsd-mailx / postfix** | Useless without an external SMTP relay. Install only if you configure a relay (SMTP2GO, Mailgun). |
| **net-tools** | Legacy (`ifconfig`, `netstat`). Replaced by `ip` and `ss`, preinstalled on Ubuntu 24.04. |

## Swap file

Cloud-init creates a 2 GB swap file. Verify:

```bash
swapon --show
free -h
```

Verify: a swap entry exists (2 GB). If missing:

```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

> Note: swap prevents the OOM killer from terminating processes on instances with 4 GB RAM or less. On larger instances, it still provides a safety net during memory spikes.

## One-time security audit (optional)

Run Lynis for a quick security assessment after setup:

```bash
sudo apt install -y lynis
sudo lynis audit system --quick
```

Review the output for warnings and suggestions. This is a one-time check, not a recurring service.

## Periodic monitoring

```bash
# Currently banned IPs
sudo fail2ban-client status sshd

# Failed login attempts (last week)
sudo journalctl -u ssh --since "1 week ago" | grep "Failed"

# Active connections
ss -tuln

# Firewall status
sudo ufw status numbered

# Verify SSH hardening is active
sudo sshd -T | grep -i 'permitrootlogin\|passwordauth\|allowusers'
```

## Checklist

- [ ] SSH drop-in file present and correct
- [ ] `sshd -T` output matches expected values
- [ ] Fail2Ban active with sshd jail
- [ ] Fail2Ban parameters are 3600/600/3
- [ ] UFW active with deny incoming default
- [ ] UFW rules: 22, 80, 443 only
- [ ] Provider firewall attached with SSH restricted to your IP

## Next

Proceed to [03-docker.md](03-docker.md).
