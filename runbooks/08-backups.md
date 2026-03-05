# 08 - Backups

Automated backup strategy with restic, PostgreSQL dump, and restore verification.

## Placeholders

| Placeholder | Description | Example |
|---|---|---|
| `<BACKUP_REPO>` | Restic repository URL | `s3:https://s3.amazonaws.com/mybucket` |
| `<RESTIC_PASSWORD>` | Restic encryption password | Store securely, you need it to restore |

## What to back up

| Path | Contents | Priority |
|---|---|---|
| `/srv/docker/` | All docker-compose.yml, .env, container data | Critical |
| `/srv/docker/n8n/postgres-data/` | PostgreSQL data (via pg_dump instead) | Critical |
| `/srv/oc-*/` | OpenClaw instances (config, data) | Critical |
| `/srv/openclaw-instances.conf` | Instance registry | Important |
| `/etc/ssh/sshd_config.d/` | SSH hardening | Important |
| `/etc/fail2ban/jail.local` | Fail2Ban config | Important |
| `/etc/docker/daemon.json` | Docker log rotation config | Low |

> Note: back up `.env` files (they contain passwords and encryption keys). Without `N8N_ENCRYPTION_KEY`, all n8n credentials are unrecoverable.

## Step 1 - Install restic

```bash
sudo apt install -y restic
```

Verify:

```bash
restic version
```

## Step 2 - Initialize repository

Choose a backend:

| Backend | Example URL | Notes |
|---|---|---|
| Backblaze B2 | `b2:bucketname:path` | Cheap, reliable |
| S3-compatible | `s3:https://endpoint/bucket` | Hetzner Storage Box, Wasabi, MinIO |
| SFTP | `sftp:user@host:/path` | Any SSH server |
| Local | `/mnt/backup` | Attached volume (not recommended alone) |

```bash
export RESTIC_REPOSITORY="<BACKUP_REPO>"
export RESTIC_PASSWORD="<RESTIC_PASSWORD>"

restic init
```

Verify: "created restic repository" message.

> Note: store `RESTIC_PASSWORD` securely (password manager, not on the server alone). Without it, backups are unrecoverable.

## Step 3 - Create backup script

```bash
sudo tee /usr/local/bin/backup.sh > /dev/null << 'SCRIPT'
#!/bin/bash
set -euo pipefail

# --- Configuration ---
export RESTIC_REPOSITORY="<BACKUP_REPO>"
export RESTIC_PASSWORD_FILE="/root/.restic-password"
BACKUP_LOG="/var/log/backup.log"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$BACKUP_LOG"; }

log "=== Backup started ==="

# --- PostgreSQL dump (before file backup) ---
log "Dumping PostgreSQL..."
docker exec n8n-postgres pg_dump -U n8n -d n8n --clean --if-exists \
    > /srv/docker/n8n/n8n-db-dump.sql 2>> "$BACKUP_LOG"
log "PostgreSQL dump: $(wc -c < /srv/docker/n8n/n8n-db-dump.sql) bytes"

# --- Restic backup ---
log "Running restic backup..."
restic backup \
    /srv/docker/ \
    /srv/oc-*/ \
    /srv/openclaw-instances.conf \
    /etc/ssh/sshd_config.d/ \
    /etc/fail2ban/jail.local \
    /etc/docker/daemon.json \
    --exclude='/srv/docker/*/postgres-data' \
    --exclude='*.log' \
    --tag auto \
    >> "$BACKUP_LOG" 2>&1

# --- Retention policy: 7 daily, 4 weekly, 6 monthly ---
log "Applying retention policy..."
restic forget \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 6 \
    --prune \
    >> "$BACKUP_LOG" 2>&1

log "=== Backup completed ==="
SCRIPT

sudo chmod +x /usr/local/bin/backup.sh
```

Store the restic password:

```bash
echo "<RESTIC_PASSWORD>" | sudo tee /root/.restic-password > /dev/null
sudo chmod 600 /root/.restic-password
```

> Note: PostgreSQL data is excluded from the file backup (`--exclude postgres-data`) because we use `pg_dump` instead. A SQL dump is portable, consistent, and smaller than raw data files. The dump file lands in `/srv/docker/n8n/` and gets picked up by restic.

## Step 4 - Test manual backup

```bash
sudo /usr/local/bin/backup.sh
```

Verify:

```bash
sudo restic -r "<BACKUP_REPO>" --password-file /root/.restic-password snapshots
```

Verify: at least one snapshot with the `auto` tag.

## Step 5 - Automate with systemd timer

```bash
sudo tee /etc/systemd/system/backup.service > /dev/null << 'EOF'
[Unit]
Description=Automated backup (restic)

[Service]
Type=oneshot
ExecStart=/usr/local/bin/backup.sh
EOF

sudo tee /etc/systemd/system/backup.timer > /dev/null << 'EOF'
[Unit]
Description=Daily backup at 03:00

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
RandomizedDelaySec=900

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable backup.timer
sudo systemctl start backup.timer
```

Verify:

```bash
systemctl list-timers | grep backup
```

Verify: backup.timer is listed with next trigger time.

## Step 6 - Verify restore (critical)

A backup you have never restored is not a backup. Test restore periodically:

```bash
# List snapshots
sudo restic -r "<BACKUP_REPO>" --password-file /root/.restic-password snapshots

# Restore a specific file to /tmp for inspection
sudo restic -r "<BACKUP_REPO>" --password-file /root/.restic-password restore latest \
    --target /tmp/restore-test \
    --include /srv/docker/n8n/.env

# Verify the restored file
cat /tmp/restore-test/srv/docker/n8n/.env

# Clean up
rm -rf /tmp/restore-test
```

### Full disaster recovery (reference)

If the server is lost:

1. Provision a new server (runbooks 01-03)
2. Install restic and configure the same repository
3. Restore all files: `restic restore latest --target /`
4. Restore PostgreSQL: `cat /srv/docker/n8n/n8n-db-dump.sql | docker exec -i n8n-postgres psql -U n8n -d n8n`
5. Start services: `docker compose up -d` in each directory
6. Recreate OpenClaw systemd services (runbook 06 or provisioning script)

## Checklist

- [ ] restic installed
- [ ] Repository initialized on external storage
- [ ] `RESTIC_PASSWORD` stored securely (password manager + `/root/.restic-password`)
- [ ] Backup script created and tested manually
- [ ] PostgreSQL dump included in backup
- [ ] systemd timer enabled (daily at 03:00)
- [ ] Restore tested at least once
- [ ] `.env` files (with `N8N_ENCRYPTION_KEY`) confirmed in backup

## Next

Proceed to [09-maintenance.md](09-maintenance.md).
