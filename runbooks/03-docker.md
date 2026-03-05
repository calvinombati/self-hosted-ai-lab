# 03 - Docker

Docker CE installation, directory conventions, and lazydocker. If cloud-init ran successfully, Docker is already installed - this runbook covers verification and manual installation as fallback.

## Placeholders

| Placeholder | Description | Example |
|---|---|---|
| `<USER>` | Admin username | `deploy` |

## Step 1 - Verify Docker installation

```bash
docker --version
docker compose version
docker ps
```

Verify: version strings for Docker CE and Docker Compose plugin, empty container list.

If Docker is installed, skip to Step 3.

## Step 2 - Install Docker (manual, if cloud-init failed)

Precondition: Ubuntu 24.04 (`noble`).

```bash
# Add Docker GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Add Docker repository (codename hardcoded to 'noble')
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu noble stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Enable and start
sudo systemctl enable docker
sudo systemctl start docker

# Add user to docker group
sudo usermod -aG docker <USER>
```

> Note: the codename `noble` is hardcoded (not using `lsb_release -cs`) to avoid issues when cloud-init doesn't have the full path. After running `usermod`, you need to re-login (or reboot) for the group to take effect. If `docker ps` gives "permission denied", run `newgrp docker` or reconnect.

Verify:

```bash
docker --version && docker compose version && docker ps
```

## Step 3 - Verify directory structure

```bash
ls -la /srv/docker/
```

Verify: owner `root:docker`, permissions `drwxrws---` (SGID bit set).

If missing:

```bash
sudo mkdir -p /srv/docker
sudo chown root:docker /srv/docker
sudo chmod 2770 /srv/docker
```

### Directory conventions

All Docker projects follow a uniform structure:

```
/srv/docker/
├── n8n/
│   ├── docker-compose.yml
│   ├── .env
│   ├── n8n-data/
│   └── postgres-data/
├── caddy/
│   ├── docker-compose.yml
│   ├── Caddyfile
│   └── data/
└── <other-service>/
    └── ...
```

Rules:
- One directory per service under `/srv/docker/`
- Owner: `root:docker`
- Permissions: `2770` (SGID - new files inherit docker group)
- Any user in the `docker` group can read/write

## Step 4 - Configure log rotation

Without log rotation, Docker containers can fill the disk. Configure the Docker daemon to limit log size:

```bash
sudo tee /etc/docker/daemon.json > /dev/null << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

sudo systemctl restart docker
```

Verify:

```bash
docker info --format '{{.LoggingDriver}}'
cat /etc/docker/daemon.json
```

Verify: logging driver is `json-file`, max-size and max-file are set.

> Note: this applies to all new containers. Existing containers keep their current log config until recreated (`docker compose up -d` is enough).

## Step 5 - Install lazydocker

lazydocker is a terminal UI for Docker. Useful on headless servers.

```bash
curl -fsSL https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | DIR=/usr/local/bin sudo bash
```

Verify:

```bash
lazydocker --version
```

> Note: if the install script returns 404, the URL may have changed. Check the [lazydocker releases](https://github.com/jesseduffield/lazydocker/releases) page for current install instructions.

## Step 6 - Create shared Docker network

Services that need to communicate (e.g., Caddy reverse proxy with n8n) use a shared network:

```bash
docker network create caddy-net
```

Verify:

```bash
docker network ls | grep caddy-net
```

## Docker cheat sheet

```bash
# Start/stop a service
cd /srv/docker/<SERVICE>
docker compose up -d
docker compose down

# View logs
docker compose logs -f --tail=50

# Pull updated images and recreate
docker compose pull
docker compose up -d

# Clean up unused images
docker image prune -f

# Aggressive cleanup (removes ALL unused images, volumes, build cache)
# WARNING: removes named volumes not currently mounted
docker system prune -a --volumes
```

## Checklist

- [ ] Docker CE installed and running
- [ ] Docker Compose plugin installed
- [ ] `<USER>` is in docker group
- [ ] `/srv/docker/` exists with correct permissions (root:docker, 2770, SGID)
- [ ] Log rotation configured in `/etc/docker/daemon.json`
- [ ] lazydocker installed
- [ ] `caddy-net` Docker network created

## Next

Proceed to [04-caddy.md](04-caddy.md).
