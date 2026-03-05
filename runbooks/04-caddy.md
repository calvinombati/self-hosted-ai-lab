# 04 - Caddy

Caddy as reverse proxy with automatic HTTPS (ACME). Runs as a Docker container and proxies traffic to other services.

## Placeholders

| Placeholder | Description | Example |
|---|---|---|
| `<DOMAIN_N8N>` | Domain for n8n | `n8n.example.com` |

## Why Caddy

| Criteria | Nginx + Certbot | Caddy |
|---|---|---|
| HTTPS | Manual (Certbot) | Automatic (built-in ACME) |
| Config | Server blocks, sites-available/enabled | Single Caddyfile |
| Docker integration | None | Shared network |
| Renewal failures | Silent (port 80 conflict with Certbot standalone) | Never (built-in) |

> Note: Nginx + Certbot standalone can fail silently when Nginx occupies port 80 during ACME challenges. Migrating to `certbot --nginx` plugin fixes it but adds complexity. Caddy eliminates this entire class of problems.

## Step 1 - Create directory

```bash
sudo mkdir -p /srv/docker/caddy/data
sudo mkdir -p /srv/docker/caddy/config
```

Verify:

```bash
ls -la /srv/docker/caddy/
```

## Step 2 - Create Caddyfile

```bash
sudo tee /srv/docker/caddy/Caddyfile > /dev/null << 'EOF'
# n8n
<DOMAIN_N8N> {
	reverse_proxy n8n:5678
}

# Add more services below:
# <DOMAIN_SERVICE> {
# 	reverse_proxy <container_name>:<port>
# }
EOF
```

Verify:

```bash
cat /srv/docker/caddy/Caddyfile
```

## Step 3 - Create docker-compose.yml

```bash
sudo tee /srv/docker/caddy/docker-compose.yml > /dev/null << 'EOF'
services:
  caddy:
    image: caddy:2-alpine
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ./data:/data
      - ./config:/config
    networks:
      - caddy-net

networks:
  caddy-net:
    external: true
EOF
```

> Note: the `443:443/udp` binding enables HTTP/3 (QUIC). The `caddy-net` network must already exist (created in runbook 03). Caddy resolves container names via Docker DNS on this shared network.

## Step 4 - DNS configuration

Precondition: you have a domain and access to its DNS settings.

Create an A record pointing to your server's IPv4:

| Type | Name | Value |
|---|---|---|
| A | `n8n` (or your subdomain) | `<IPV4_ADDRESS>` |

Wait for DNS propagation (usually 1-5 minutes with Cloudflare, up to 48h with other providers).

Verify:

```bash
dig +short <DOMAIN_N8N>
```

Verify: returns your server's IP.

## Step 5 - Start Caddy

```bash
cd /srv/docker/caddy
docker compose up -d
```

Verify:

```bash
docker compose ps
```

Verify: caddy container is `running` (healthy).

```bash
docker compose logs --tail=20
```

Verify: no errors. You should see Caddy obtaining a certificate for your domain.

## Step 6 - Test HTTPS

```bash
curl -I https://<DOMAIN_N8N>
```

Verify: HTTP response (may be 502 if n8n is not running yet - that's OK, it means Caddy is working and has a valid certificate).

## Rate limiting (optional)

If you expose webhook endpoints (e.g., n8n webhooks), consider adding rate limiting. Caddy supports this via the `rate_limit` directive (requires the [caddy-ratelimit](https://github.com/mholt/caddy-ratelimit) plugin) or via a custom Caddy build.

A simpler alternative: use n8n's built-in webhook authentication (Header Auth, Basic Auth, or JWT) and rely on Fail2Ban + provider firewall for abuse prevention.

## Adding services

To add a new service behind Caddy:

1. Add a block to the Caddyfile
2. Connect the service's Docker container to `caddy-net`
3. Reload Caddy: `cd /srv/docker/caddy && docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile`

## Checklist

- [ ] `/srv/docker/caddy/` directory created
- [ ] Caddyfile written with domain configured
- [ ] docker-compose.yml created
- [ ] DNS A record pointing to server IP
- [ ] Caddy container running
- [ ] HTTPS certificate obtained automatically
- [ ] Domain resolves and returns HTTPS response

## Next

Proceed to [05-n8n.md](05-n8n.md).
