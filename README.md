# Self-hosted AI setup

> Full-stack setup for a self-hosted AI automation server: provisioning, hardening, Docker, reverse proxy, n8n, OpenClaw. From zero to production-ready.

**LLM-executable**: every runbook is designed to be followed step-by-step by [Claude Code](https://claude.ai/code) or any AI coding assistant. Give a runbook to your assistant and it will execute the setup for you.

Also works perfectly fine as a guide for humans.

## What you get

A hardened Ubuntu server running:

- **Docker** with organized project structure and log rotation
- **Caddy** as reverse proxy with automatic HTTPS
- **n8n** for workflow automation (with PostgreSQL, encrypted credentials)
- **OpenClaw** as AI gateway (multi-instance support)
- **Fail2Ban**, **UFW**, swap, and SSH hardening out of the box
- **Monitoring** via external services or self-hosted Uptime Kuma
- **Automated backups** with restic, PostgreSQL dumps, and restore verification

## Quick start

1. Choose a provider and create a server ([Hetzner recommended](#providers))
2. Follow the runbooks in order:

| # | Runbook | What it does |
|---|---------|-------------|
| 01 | [Provisioning](runbooks/01-provisioning.md) | Cloud-init, first boot, post-provision verification |
| 02 | [Hardening](runbooks/02-hardening.md) | SSH drop-in, Fail2Ban, UFW, swap, dual-layer firewall |
| 03 | [Docker](runbooks/03-docker.md) | Docker CE, Compose, log rotation, lazydocker |
| 04 | [Caddy](runbooks/04-caddy.md) | Reverse proxy, automatic HTTPS, Caddyfile |
| 05 | [n8n](runbooks/05-n8n.md) | n8n + PostgreSQL, encryption key, proxy config |
| 06 | [OpenClaw](runbooks/06-openclaw.md) | AI gateway, multi-instance, Tailscale alternative |
| 07 | [Monitoring](runbooks/07-monitoring.md) | Uptime checks, alerting, Uptime Kuma |
| 08 | [Backups](runbooks/08-backups.md) | Automated restic, pg_dump, restore verification |
| 09 | [Maintenance](runbooks/09-maintenance.md) | Updates, SSH key rotation, troubleshooting |

Each runbook is self-contained. You can stop at any step and have a working server.

## Runbook format

Every runbook follows this structure:

```
## Step name

Precondition: what must be true before this step
Action: exact commands to run
Verify: command + expected output to confirm success

> Note: optional context for humans (why this choice was made)
```

Commands use `<PLACEHOLDER>` format for values you must customize. All placeholders are listed at the top of each runbook.

## Templates

Ready-to-use configuration files in [`templates/`](templates/):

- `cloud-init.yaml` - server provisioning template
- `openclaw-provision.sh` - multi-instance provisioning script
- `openclaw-instances.conf` - instance registry

Docker Compose files for Caddy and n8n are embedded directly in their respective runbooks (04, 05) as `tee` commands, ready to copy-paste or execute.

## Providers

This guide is provider-agnostic. Any cloud provider with Ubuntu 24.04 and cloud-init support works. Provider-specific instructions (console walkthrough, firewall setup) are in [`providers/`](providers/).

Currently documented:

- [Hetzner Cloud](providers/hetzner.md) - recommended for price/performance ratio

> Hetzner offers ARM64 instances (Ampere) at lower cost than x86 with equivalent performance. New accounts get EUR 20 credit with [this referral link](https://hetzner.cloud/?ref=7UcZyMnU7io5) (disclosure: referral gives credit to both parties).

## Conventions

| Convention | Value |
|---|---|
| Admin user | `<USER>` (sudo NOPASSWD, key-only auth) |
| SSH hardening | Drop-in `/etc/ssh/sshd_config.d/99-hardening.conf` |
| Container base dir | `/srv/docker/<service-name>/` |
| Docker dir permissions | `root:docker`, `chmod 2770`, SGID |
| Firewall | Dual layer: provider (network) + UFW (software) |
| Ubuntu codename | `noble` (hardcoded, never use `lsb_release -cs`) |
| Placeholders | `<UPPER_CASE>` format throughout |
| OpenClaw naming | `oc-<name>` prefix, ports `*789` (18789, 19789, ...) |

## Requirements

- A cloud server with Ubuntu 24.04 LTS
- SSH key pair (ed25519 recommended)
- A domain name (for HTTPS via Caddy)
- API keys for your LLM provider (for OpenClaw)

## For AI assistants

If you are an AI coding assistant executing these runbooks:

- Read the full runbook before starting
- Execute steps sequentially - each depends on the previous
- Always run the "Verify" step and check output matches expected
- If a verify step fails, stop and diagnose before continuing
- Placeholders (`<VALUE>`) must be resolved before execution
- Never skip verify steps, even if the command appeared to succeed
- After completing a runbook, report which steps succeeded and which need attention

## License

MIT

## Contributing

Issues and PRs welcome. If you adapt these runbooks for a new provider, consider adding a guide in `providers/`.
