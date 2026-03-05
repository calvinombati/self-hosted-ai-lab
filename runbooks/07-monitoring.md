# 07 - Monitoring

Uptime monitoring and alerting. Know when your server or services go down before your users do.

## Approach

You need monitoring that works **when the server is down**. A monitoring tool running on the same server it monitors is blind to the most critical failure: the server itself being unreachable.

Two options:

| Option | Pros | Cons |
|---|---|---|
| **External service** (UptimeRobot, Hetrixtools) | Works when server is down, no maintenance | Free tiers limited, third-party dependency |
| **Self-hosted on another server** (Uptime Kuma) | Full control, more checks | Requires a second server or instance |

For a single-server setup, an external service is the pragmatic choice. If you have multiple servers, self-host Uptime Kuma on one to monitor the others.

## Option A - External monitoring (recommended for single server)

### Step 1 - Choose a service

Free tiers that cover basic needs:

| Service | Free tier | Check interval |
|---|---|---|
| [UptimeRobot](https://uptimerobot.com/) | 50 monitors, 5 min | 5 min |
| [Hetrixtools](https://hetrixtools.com/) | 15 monitors, 1 min | 1 min |
| [Cronitor](https://cronitor.io/) | 5 monitors | 1 min |

### Step 2 - Configure monitors

Add these monitors at minimum:

| Type | Target | What it checks |
|---|---|---|
| HTTP(S) | `https://<DOMAIN_N8N>` | Caddy + n8n are up, HTTPS works |
| Port | `<IP_ADDRESS>:22` | SSH is reachable |
| Ping | `<IP_ADDRESS>` | Server is online |

### Step 3 - Configure alerts

Set up notifications via:
- Email (always, as fallback)
- Telegram or Slack webhook (faster response)

Verify: trigger a test alert from the service dashboard.

## Option B - Self-hosted Uptime Kuma

If you have a second server or want to run Uptime Kuma on the same server (useful for monitoring individual services, not the server itself):

### Step 1 - Create directory

```bash
sudo mkdir -p /srv/docker/uptime-kuma
```

### Step 2 - Create docker-compose.yml

```bash
sudo tee /srv/docker/uptime-kuma/docker-compose.yml > /dev/null << 'EOF'
services:
  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: uptime-kuma
    restart: unless-stopped
    ports:
      - "127.0.0.1:3001:3001"
    volumes:
      - ./data:/app/data
    networks:
      - caddy-net

networks:
  caddy-net:
    external: true
EOF
```

### Step 3 - Start

```bash
cd /srv/docker/uptime-kuma
docker compose up -d
```

Verify:

```bash
docker compose ps
```

Verify: container is `running`.

### Step 4 - Access

Via SSH tunnel:

```bash
ssh -L 3001:127.0.0.1:3001 <USER>@<IP_ADDRESS> -N
```

Open `http://localhost:3001`, create admin account, add monitors.

To expose via Caddy, add to your Caddyfile:

```
<DOMAIN_UPTIME> {
    reverse_proxy uptime-kuma:3001
}
```

### Step 5 - Add monitors

In the Uptime Kuma dashboard, add:

| Type | Target | Interval |
|---|---|---|
| HTTP(s) | `https://<DOMAIN_N8N>` | 60s |
| Docker Container | `n8n` | 60s |
| Docker Container | `n8n-postgres` | 60s |
| TCP Port | `127.0.0.1:<OC_PORT>` | 60s |

Configure notification channels (Telegram, email, Slack, webhook).

## Server-level monitoring commands

For quick diagnosis without a monitoring tool:

```bash
# System overview
uptime
free -h
df -h /

# Failed services
systemctl --failed

# Docker containers status
docker ps --format "table {{.Names}}\t{{.Status}}"

# OpenClaw instances
systemctl list-units --type=service --state=running | grep oc-
```

## Checklist

- [ ] At least one external HTTP monitor on your primary domain
- [ ] SSH/ping monitor on server IP
- [ ] Alert notifications configured and tested
- [ ] (Optional) Uptime Kuma for per-service monitoring

## Next

Proceed to [08-backups.md](08-backups.md).
