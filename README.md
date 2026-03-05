# Self-hosted AI lab

> Production-ready VPS for AI automation: hardened infrastructure, n8n workflows and OpenClaw AI gateway. Includes LLM-executable runbooks for AI assistants.

Run your own AI automation server on a EUR 7/month VPS with hardened infrastructure and multi-instance OpenClaw support.

Every runbook follows a Precondition / Action / Verify pattern designed for [Claude Code](https://claude.ai/code) or any AI coding assistant. Give a runbook to your assistant and it will execute the setup for you. Also works perfectly fine as a guide for humans.

## What you build

```
                  ┌─────────────────────────────────────────────┐
                  │                 Your VPS                     │
                  │                                             │
Internet ──443──► │  Caddy (reverse proxy, auto-HTTPS)          │
                  │    └──► n8n (AI workflows, webhooks)         │
                  │            └──► PostgreSQL                   │
                  │                                             │
SSH tunnel ─────► │  OpenClaw (multi-instance AI gateway)        │
                  │    └──► Cloud LLM APIs                      │
                  │                                             │
                  │  ┌─── Security ───────────────────────────┐ │
                  │  │ UFW + provider firewall (dual layer)    │ │
                  │  │ Fail2Ban, SSH hardening, swap           │ │
                  │  │ Monitoring, automated backups           │ │
                  │  └─────────────────────────────────────────┘ │
                  └─────────────────────────────────────────────┘
```

**n8n** is your AI automation platform: build workflows with 400+ integrations, AI Agent nodes, text classifiers, and LLM chains. Connect to OpenAI, Anthropic, or any API to automate tasks that would take hours manually.

**OpenClaw** is your personal AI gateway: a unified interface to interact with cloud LLM providers (Anthropic, OpenAI, Google, etc.) from a single dashboard, with per-instance isolation and SSH-only access.

## Who is this for

- You want a **cloud VPS** to run AI-powered automation and tools
- You want **production-grade infrastructure**: hardened SSH, firewall, monitoring, automated backups
- You use **cloud LLM APIs** (Anthropic, OpenAI, etc.) and want a secure server to run tools on top of them
- You want something you can hand to an AI assistant and say "set this up for me"

## What this is NOT

- **Not a local LLM hosting guide.** This guide uses cloud APIs via OpenClaw and n8n, not local models. Running Ollama or similar on a small VPS is possible but limited by CPU-only performance. If you want a full local AI stack (Ollama + Open WebUI + vector database), see [Going further](#going-further).
- **Not a homelab guide.** This targets cloud VPS instances, not bare metal or Raspberry Pi setups.

## Cost estimate

On Hetzner Cloud (ARM64 instances):

| Instance | Specs | Monthly cost | Good for |
|---|---|---|---|
| CAX11 | 2 vCPU, 4 GB, 40 GB | ~EUR 4 | n8n only |
| **CAX21** | **4 vCPU, 8 GB, 80 GB** | **~EUR 7** | **Full stack (recommended)** |
| CAX31 | 8 vCPU, 16 GB, 160 GB | ~EUR 14 | Heavy workloads |

New Hetzner accounts get EUR 20 credit with [this referral link](https://hetzner.cloud/?ref=7UcZyMnU7io5) (disclosure: referral gives credit to both parties), enough for 2-3 months on a CAX21.

Domain name: EUR 1-10/year depending on TLD. Required for HTTPS.

## Requirements

- A cloud server with **Ubuntu 24.04 LTS** (any provider with cloud-init support)
- **SSH key pair** (ed25519 recommended)
- A **domain name** (for HTTPS via Caddy)
- **API keys** for your LLM provider (for OpenClaw)

## Quick start

1. Choose a provider and create a server ([Hetzner recommended](#providers))
2. Follow the runbooks in order:

| # | Runbook | What it does |
|---|---------|-------------|
| 01 | [Provisioning](runbooks/01-provisioning.md) | Cloud-init, first boot, post-provision verification |
| 02 | [Hardening](runbooks/02-hardening.md) | SSH drop-in, Fail2Ban, UFW, swap, dual-layer firewall |
| 03 | [Docker](runbooks/03-docker.md) | Docker CE, Compose, log rotation, lazydocker |
| 04 | [Caddy](runbooks/04-caddy.md) | Reverse proxy, automatic HTTPS, Caddyfile |
| 05 | [n8n](runbooks/05-n8n.md) | n8n + PostgreSQL, encryption key, AI capabilities |
| 06 | [OpenClaw](runbooks/06-openclaw.md) | AI gateway, multi-instance, Tailscale alternative |
| 07 | [Monitoring](runbooks/07-monitoring.md) | Uptime checks, alerting, Uptime Kuma |
| 08 | [Backups](runbooks/08-backups.md) | Automated restic, pg_dump, restore verification |
| 09 | [Maintenance](runbooks/09-maintenance.md) | Updates, SSH key rotation, troubleshooting |

Each runbook is self-contained. You can stop at any step and have a working server. Runbooks 01-04 give you a hardened server with Docker. Add 05 for automation, 06 for AI gateway, 07-09 for operational maturity.

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

## For AI assistants

If you are an AI coding assistant executing these runbooks:

- Read the full runbook before starting
- Execute steps sequentially - each depends on the previous
- Always run the "Verify" step and check output matches expected
- If a verify step fails, stop and diagnose before continuing
- Placeholders (`<VALUE>`) must be resolved before execution
- Never skip verify steps, even if the command appeared to succeed
- After completing a runbook, report which steps succeeded and which need attention

### Example prompt

```text
Read the runbook 01-provisioning.md and execute all steps on a fresh Ubuntu 24.04 VPS.
Use "fra" as <USER> and "203.0.113.10" as <IP_ADDRESS>.
Run each command, verify outputs match expected results, and report which steps
succeeded and which need attention.
```

## Going further

This guide focuses on cloud API-based AI tools. If you want to expand your setup:

- **Local LLMs on your VPS**: [Ollama](https://ollama.com/) can run small models (Phi-3, Gemma) on CPU. Performance is limited without a GPU, but usable for n8n automation workflows.
- **Chat interface**: [Open WebUI](https://github.com/open-webui/open-webui) provides a ChatGPT-like interface that connects to Ollama (local) or cloud APIs (OpenAI, Anthropic).
- **Full local AI stack**: n8n's official [Self-hosted AI Starter Kit](https://github.com/n8n-io/self-hosted-ai-starter-kit) bundles n8n + Ollama + Qdrant (vector database) in a single Docker Compose. It runs on top of the infrastructure from runbooks 01-04 of this guide.
- **Vector database for RAG**: [Qdrant](https://qdrant.tech/) or [ChromaDB](https://www.trychroma.com/) for retrieval-augmented generation workflows in n8n.

The infrastructure you build with this guide (hardened server, Docker, Caddy, monitoring, backups) is the foundation for any of these expansions.

## License

MIT

## Contributing

Issues and PRs welcome. If you adapt these runbooks for a new provider, consider adding a guide in `providers/`.
