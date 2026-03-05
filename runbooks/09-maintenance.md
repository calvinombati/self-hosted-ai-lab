# 09 - Maintenance

OS updates, Docker image updates, OpenClaw updates, SSH key rotation, and troubleshooting.

## Placeholders

| Placeholder | Description | Example |
|---|---|---|
| `<USER>` | Admin username | `deploy` |
| `<IP_ADDRESS>` | Server IPv4 | `203.0.113.10` |

## OS updates

Automatic security patches are handled by unattended-upgrades (configured in runbook 01). Manual full upgrade:

```bash
sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y
```

Frequency: weekly for manual upgrades. After kernel updates, check if reboot is needed:

```bash
[ -f /var/run/reboot-required ] && echo "REBOOT REQUIRED" || echo "OK, no reboot needed"
```

## Docker image updates

For each service in `/srv/docker/<service>/`:

```bash
cd /srv/docker/<SERVICE>
docker compose pull
docker compose up -d
docker compose ps
docker compose logs -f --tail=20
```

Clean up old images:

```bash
docker image prune -f
```

## OpenClaw updates

Per instance:

```bash
sudo su - oc-<OC_NAME> -c "npm update -g openclaw && openclaw --version"
sudo systemctl restart oc-<OC_NAME>-gateway
```

If Node.js major version changes (e.g., v22 to v24), update the `ExecStart` path in the systemd service file.

## Versioned components registry

Check this table before a new provisioning or after several months.

| Component | Pinned version | Where to check for updates |
|---|---|---|
| **nvm** | `v0.40.2` (URL with explicit version) | [nvm releases](https://github.com/nvm-sh/nvm/releases) |
| **Node.js** | `22` LTS (via nvm) | [nodejs.org/releases](https://nodejs.org/en/about/releases/) |
| **PostgreSQL** | `16-alpine` (major pinned) | [postgresql.org/versioning](https://www.postgresql.org/support/versioning/) |
| **Caddy** | `2-alpine` (auto-updates minor/patch) | [caddy releases](https://github.com/caddyserver/caddy/releases) |
| **Docker CE** | From official repo | [docker release notes](https://docs.docker.com/engine/release-notes/) |
| **lazydocker** | Latest (install script) | [lazydocker releases](https://github.com/jesseduffield/lazydocker/releases) |
| **OpenClaw** | `@latest` (npm) | [npmjs.com/package/openclaw](https://www.npmjs.com/package/openclaw) |
| **Uptime Kuma** | `1` (major pinned) | [uptime-kuma releases](https://github.com/louislam/uptime-kuma/releases) |
| **restic** | From apt repo | [restic releases](https://github.com/restic/restic/releases) |

> Note: URLs with explicit versions (like nvm) do NOT auto-update. If you copy the cloud-init template months later without checking this table, you install today's version.

## SSH key rotation

On your local machine, generate a new key:

```bash
ssh-keygen -t ed25519 -C "<NEW_KEY_LABEL>" -f ~/.ssh/id_ed25519_new
```

On the server (via an existing SSH session):

```bash
# 1. Add new key
echo "<NEW_PUBLIC_KEY>" >> /home/<USER>/.ssh/authorized_keys

# 2. Test from a NEW terminal (keep old session open as backup)
ssh -i ~/.ssh/id_ed25519_new <USER>@<IP_ADDRESS>

# 3. Only after verifying: remove old key
# Edit /home/<USER>/.ssh/authorized_keys and remove the old key line
```

**Never remove the old key before verifying the new one works.** Keep a backup SSH session open during the entire process.

## Troubleshooting

### SSH access

| Problem | Diagnosis | Fix |
|---|---|---|
| Connection refused | `ssh -v <USER>@<IP_ADDRESS>` | Check provider firewall allows your current IP on port 22 |
| Permission denied | Wrong key or user | Specify key: `ssh -i ~/.ssh/id_ed25519 <USER>@<IP_ADDRESS>` |
| MaxAuthTries exceeded | Too many keys tried | Specify the correct key explicitly |
| Key changed warning | Server reinstalled | Remove old fingerprint: `ssh-keygen -R <IP_ADDRESS>` |
| Total lockout | No SSH access at all | Use provider VNC console, check sshd config and authorized_keys |

### Docker

| Problem | Diagnosis | Fix |
|---|---|---|
| Permission denied | User not in docker group | `sudo usermod -aG docker <USER>` then re-login |
| Container won't start | `docker compose logs <service>` | Check logs for specific error |
| Port conflict | `ss -tulpn \| grep <PORT>` | Stop conflicting service |
| Disk full | `df -h` | `docker system prune -a` (careful: removes all unused) |

### Caddy

| Problem | Diagnosis | Fix |
|---|---|---|
| Certificate not obtained | `docker compose logs caddy` | Verify DNS A record points to server IP, ports 80/443 open |
| 502 Bad Gateway | Backend service not running | Check target container is running and on `caddy-net` |
| Config syntax error | `docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile` | Fix Caddyfile syntax |

### Backups

| Problem | Diagnosis | Fix |
|---|---|---|
| Backup timer not running | `systemctl list-timers \| grep backup` | `sudo systemctl enable --now backup.timer` |
| Restic lock stale | `restic unlock` | Another backup may have crashed |
| Restore fails | `restic check` | Verify repository integrity |
| pg_dump fails | `docker logs n8n-postgres` | Check container is running and healthy |

### General diagnostics

```bash
# System overview
uptime
free -h
df -h /
htop

# Failed services
systemctl --failed

# Active timers (backup, certbot, apt)
systemctl list-timers --all

# Quick connectivity reference
ssh <USER>@<IP_ADDRESS>                                          # shell
ssh -L <LOCAL_PORT>:127.0.0.1:<REMOTE_PORT> <USER>@<IP_ADDRESS>  # tunnel
```

## Checklist

- [ ] Understand which updates are automatic (security) and which are manual (full upgrade, Docker images, OpenClaw)
- [ ] Versioned components table reviewed and up to date
- [ ] Backup timer running (see [08-backups.md](08-backups.md))
- [ ] Know how to rotate SSH keys safely
- [ ] Know how to recover via VNC console if SSH is locked out
