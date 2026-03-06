#!/bin/bash
set -euo pipefail

# ============================================================
# OpenClaw - Multi-instance provisioning script
# Usage:
#   Phase 1 (setup):    openclaw-provision.sh setup <username> <port>
#   Phase 2 (service):  openclaw-provision.sh service <username> <port>
#   Batch:              openclaw-provision.sh batch <config_file> <phase>
#   Status:             openclaw-provision.sh status
# ============================================================

NVM_VERSION="v0.40.2"
NODE_MAJOR="22"
OPENCLAW_PKG="openclaw@latest"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- Validation ---
validate_inputs() {
    local user="$1"
    local port="$2"

    if [[ ! "$user" =~ ^oc-[a-z][a-z0-9-]*$ ]]; then
        log_error "Invalid username '$user'. Use 'oc-<name>' (e.g., oc-work, oc-personal)."
        exit 1
    fi

    if [[ ! "$port" =~ ^[0-9]+$ ]] || (( port < 1024 || port > 65535 )); then
        log_error "Invalid port '$port'. Must be a number between 1024 and 65535."
        exit 1
    fi

    if (( port % 1000 != 789 )); then
        log_warn "Port $port does not follow the *789 convention. Continuing anyway."
    fi

    if ss -tulpn | grep -q ":${port} " 2>/dev/null; then
        log_error "Port $port is already in use."
        ss -tulpn | grep ":${port} "
        exit 1
    fi
}

# --- Phase 1: Setup (user, nvm, node, openclaw) ---
phase_setup() {
    local user="$1"
    local port="$2"
    local home="/srv/${user}"

    log_info "=== PHASE 1: Setup instance '${user}' (port ${port}) ==="

    if id "$user" &>/dev/null; then
        log_warn "User '$user' already exists. Skipping user creation."
    else
        log_info "Creating user '$user' with home in $home..."
        sudo useradd -r -s /bin/bash -d "$home" -m "$user"
    fi

    log_info "Installing nvm, Node.js ${NODE_MAJOR}, and OpenClaw for '$user'..."

    sudo -u "$user" bash -l << SETUP_EOF
set -euo pipefail

# nvm
if [ ! -d "\$HOME/.nvm" ]; then
    curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
fi

export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh"

# Node.js
if ! node --version 2>/dev/null | grep -q "v${NODE_MAJOR}"; then
    nvm install ${NODE_MAJOR}
fi
echo "Node.js: \$(node --version)"

# OpenClaw
npm install -g ${OPENCLAW_PKG}
echo "OpenClaw: \$(openclaw --version)"
echo "Binary: \$(which openclaw)"
SETUP_EOF

    log_info "Phase 1 complete for '$user'."
    echo ""
    log_warn "=== MANUAL ACTION REQUIRED ==="
    log_warn "Run the interactive onboarding:"
    echo ""
    echo "    sudo su - ${user}"
    echo "    cd /srv/${user}"
    echo "    openclaw onboard"
    echo "    exit"
    echo ""
    log_warn "Then run Phase 2:"
    echo ""
    echo "    sudo openclaw-provision.sh service ${user} ${port}"
    echo ""
}

# --- Phase 2: systemd service ---
phase_service() {
    local user="$1"
    local port="$2"
    local home="/srv/${user}"
    local service_name="${user}-gateway"

    log_info "=== PHASE 2: systemd service for '${user}' (port ${port}) ==="

    if ! id "$user" &>/dev/null; then
        log_error "User '$user' does not exist. Run Phase 1 first."
        exit 1
    fi

    local openclaw_bin
    openclaw_bin=$(sudo su - "$user" -c "which openclaw" 2>/dev/null || true)
    if [ -z "$openclaw_bin" ]; then
        log_error "OpenClaw not found for user '$user'. Run Phase 1 first."
        exit 1
    fi
    log_info "OpenClaw binary: $openclaw_bin"

    if [ ! -f "${home}/.openclaw/config.json" ]; then
        log_error "OpenClaw config not found at ${home}/.openclaw/config.json"
        log_error "Run first: sudo su - ${user} -c 'openclaw onboard'"
        exit 1
    fi

    local perms
    perms=$(stat -c "%a" "${home}/.openclaw/config.json")
    if [ "$perms" != "600" ]; then
        log_warn "config.json permissions are $perms, fixing to 600..."
        sudo chmod 600 "${home}/.openclaw/config.json"
    fi

    log_info "Creating service ${service_name}.service..."
    sudo tee "/etc/systemd/system/${service_name}.service" > /dev/null << SERVICE_EOF
[Unit]
Description=OpenClaw Gateway (${user})
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${user}
WorkingDirectory=${home}
ExecStart=${openclaw_bin} gateway run --port ${port}
Environment=HOME=${home}
Environment=NODE_ENV=production
Environment=PATH=$(dirname ${openclaw_bin}):/usr/local/bin:/usr/bin:/bin
StandardOutput=journal
StandardError=journal
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE_EOF

    sudo systemctl daemon-reload
    sudo systemctl enable "${service_name}.service"
    sudo systemctl start "${service_name}.service"

    sleep 3

    if sudo systemctl is-active --quiet "${service_name}.service"; then
        log_info "Service ${service_name} is active."
    else
        log_error "Service ${service_name} failed to start. Check logs:"
        echo "    sudo journalctl -u ${service_name} -n 30"
        exit 1
    fi

    if ss -tulpn | grep -q "127.0.0.1:${port}"; then
        log_info "Port ${port} listening on 127.0.0.1 (correct)."
    elif ss -tulpn | grep -q "0.0.0.0:${port}"; then
        log_error "Port ${port} exposed on 0.0.0.0! Stopping service for safety."
        sudo systemctl stop "${service_name}.service"
        exit 1
    else
        log_warn "Port ${port} not found listening. Service may need more time to start."
    fi

    echo ""
    log_info "=== Provisioning complete for '${user}' ==="
    echo "    Port:    ${port}"
    echo "    Service: ${service_name}.service"
    echo "    Tunnel:  ssh -L ${port}:localhost:${port} <USER>@<IP_ADDRESS> -N"
    echo "    Browser: http://localhost:${port}"
    echo ""
}

# --- Batch mode ---
phase_batch() {
    local config_file="$1"
    local phase="$2"

    if [ ! -f "$config_file" ]; then
        log_error "Config file '$config_file' not found."
        exit 1
    fi

    log_info "Batch processing from '$config_file' (phase: $phase)..."

    while IFS= read -r line; do
        # Strip trailing comments and skip empty/comment-only lines
        line="${line%%#*}"
        [[ -z "$line" || "$line" =~ ^[[:space:]]*$ ]] && continue
        read -r user port <<< "$line"
        [[ -z "$user" || -z "$port" ]] && continue
        validate_inputs "$user" "$port"
        case "$phase" in
            setup)   phase_setup "$user" "$port" ;;
            service) phase_service "$user" "$port" ;;
            *)       log_error "Invalid phase '$phase'. Use 'setup' or 'service'."; exit 1 ;;
        esac
    done < "$config_file"
}

# --- Main ---
case "${1:-}" in
    setup)
        [ $# -ne 3 ] && { echo "Usage: $0 setup <username> <port>"; exit 1; }
        validate_inputs "$2" "$3"
        phase_setup "$2" "$3"
        ;;
    service)
        [ $# -ne 3 ] && { echo "Usage: $0 service <username> <port>"; exit 1; }
        validate_inputs "$2" "$3"
        phase_service "$2" "$3"
        ;;
    batch)
        [ $# -ne 3 ] && { echo "Usage: $0 batch <config_file> <setup|service>"; exit 1; }
        phase_batch "$2" "$3"
        ;;
    status)
        echo "=== Active OpenClaw instances ==="
        systemctl list-units --type=service --state=running | grep -E "(oc-|openclaw).*gateway" || echo "No running instances."
        echo ""
        echo "=== OpenClaw ports listening ==="
        ss -tulpn | grep -E ":[0-9]*789 " || echo "No *789 ports listening."
        ;;
    *)
        echo "OpenClaw Instance Provisioner"
        echo ""
        echo "Usage:"
        echo "  $0 setup <username> <port>                Phase 1: create user, install nvm/node/openclaw"
        echo "  $0 service <username> <port>              Phase 2: create systemd service and start"
        echo "  $0 batch <config_file> <setup|service>    Process multiple instances from file"
        echo "  $0 status                                 Show active instances"
        echo ""
        echo "Example:"
        echo "  $0 setup oc-work 18789"
        echo "  # ... run manual onboarding ..."
        echo "  $0 service oc-work 18789"
        echo ""
        echo "  $0 batch /srv/openclaw-instances.conf setup"
        echo "  # ... run onboarding for each instance ..."
        echo "  $0 batch /srv/openclaw-instances.conf service"
        ;;
esac
