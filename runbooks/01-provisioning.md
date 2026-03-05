# 01 - Provisioning

Automated server provisioning via cloud-init. After this runbook, you have a server with a hardened SSH config, Docker, firewall, and Fail2Ban - ready for application deployment.

## Placeholders

| Placeholder | Description | Example |
|---|---|---|
| `<HOSTNAME>` | Server hostname | `myserver` |
| `<USER>` | Admin username | `deploy` |
| `<SSH_PUBLIC_KEY>` | Your full SSH public key | `ssh-ed25519 AAAA... label` |

## What cloud-init does

The template at [`templates/cloud-init.yaml`](../templates/cloud-init.yaml) automates:

1. Sets hostname and timezone (Europe/Rome)
2. Creates admin user with SSH key-only auth and passwordless sudo
3. Writes SSH hardening drop-in, Fail2Ban config, and auto-upgrade config
4. Installs base packages + Docker CE from official repo
5. Configures Docker log rotation (`daemon.json`)
6. Creates 2 GB swap file (prevents OOM on small instances)
7. Sets up UFW firewall (deny incoming, allow 22/80/443)
8. Enables Fail2Ban and unattended-upgrades
9. Creates `/srv/docker/` with correct permissions
10. Installs lazydocker
11. Reboots

## Step 1 - Prepare cloud-init

Copy `templates/cloud-init.yaml` and replace all placeholders:

- `<HOSTNAME>` - your chosen hostname
- `<USER>` - your admin username
- `<SSH_PUBLIC_KEY>` - your full public key string

Verify: no `<` characters remain in the file (all placeholders resolved).

## Step 2 - Create server

Follow your provider's guide in [`providers/`](../providers/). Paste the customized cloud-init in the "User data" field.

## Step 3 - Wait and connect

Precondition: server created, 3-5 minutes elapsed, automatic reboot completed.

```bash
ssh <USER>@<IP_ADDRESS>
```

Verify: you get a shell prompt on the remote server.

> Note: if the first connection fails, wait 2-3 more minutes. Cloud-init may still be running. If it keeps failing, use your provider's VNC console.

## Step 4 - Verify cloud-init status

```bash
sudo cloud-init status --long
```

Verify: output contains `status: done`.

If `extended_status` shows `degraded done`, check which step failed:

```bash
sudo cat /var/log/cloud-init-output.log | grep -i -E 'error|fail' | head -20
```

Common non-critical failures:
- **lazydocker 404**: install script URL changed. Install manually (see runbook 03).
- **debconf/whiptail "Failed to open terminal"**: non-interactive dpkg-reconfigure. Service works anyway.
- **pickle blob warnings**: cloud-init bug, no impact.

## Step 5 - Verify services

Run all checks. Every command must produce the expected output.

**SSH hardening:**

```bash
sudo sshd -T | grep -E 'permitrootlogin|passwordauthentication|pubkeyauthentication|allowusers|maxauthtries'
```

Verify:
```
permitrootlogin no
passwordauthentication no
pubkeyauthentication yes
allowusers <USER>
maxauthtries 3
```

**Docker:**

```bash
docker --version && docker compose version
```

Verify: both commands return version strings without errors.

**UFW:**

```bash
sudo ufw status verbose
```

Verify: Status `active`, default deny incoming, ports 22/80/443 allowed.

**Fail2Ban:**

```bash
sudo fail2ban-client status sshd
```

Verify: jail `sshd` is active with filter and actions sections visible.

**Unattended-upgrades:**

```bash
sudo systemctl is-active unattended-upgrades
```

Verify: `active`

**Docker directory:**

```bash
ls -la /srv/docker/
```

Verify: owner `root:docker`, permissions `drwxrws---` (the `s` confirms SGID).

**Hostname and timezone:**

```bash
hostname && timedatectl | grep "Time zone"
```

Verify: hostname matches `<HOSTNAME>`, timezone is `Europe/Rome`.

## Step 6 - Record server details

```bash
echo "IPv4: $(curl -4 -s ifconfig.me)"
echo "IPv6: $(curl -6 -s ifconfig.me)"
echo "Fingerprint: $(ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub)"
```

Save these values. You will need the IP for DNS configuration (runbook 04) and SSH tunnel setup (runbook 06).

## Checklist

- [ ] SSH connection works with `<USER>`
- [ ] Cloud-init completed (`status: done`)
- [ ] Docker + Docker Compose active
- [ ] UFW active with correct rules
- [ ] Fail2Ban active with sshd jail
- [ ] Unattended-upgrades active
- [ ] `/srv/docker/` exists with correct permissions
- [ ] Hostname and timezone correct
- [ ] IP addresses recorded
- [ ] Provider firewall attached with correct rules

## Next

Proceed to [02-hardening.md](02-hardening.md) for detailed security configuration, or skip to [03-docker.md](03-docker.md) if cloud-init covered everything and all checks passed.

> Note: runbook 02 provides deeper explanation of the security settings that cloud-init already applied. If all Step 5 checks passed, you can safely skip to runbook 03. Runbook 02 is useful if you need to modify settings or understand the "why" behind each choice.
