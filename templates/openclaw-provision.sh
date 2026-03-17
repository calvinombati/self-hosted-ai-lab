#!/bin/bash
set -euo pipefail

# ============================================================
# OpenClaw - Multi-instance provisioning script
#
# Two distinct phases with different execution contexts:
#
#   Phase 1 (root)  — create user, configure npm prefix, install openclaw, enable linger
#   Phase 2 (user)  — install gateway service, per-user deps, verify
#
# Prerequisite for Phase 1: system Node.js 22 LTS already installed
# (via NodeSource apt repo — once per server, not per instance).
#
# Phase 1 can run in batch as root. Phase 2 MUST run as the instance user
# via a direct SSH session — not via sudo or su. See below for why.
#
# Usage:
#   Phase 1 (as root):       openclaw-provision.sh setup <username> <port>
#   Phase 1 batch (as root): openclaw-provision.sh batch <config_file>
#   Phase 2 (as oc-* user):  openclaw-provision.sh post-onboard
#   Status (as root):        openclaw-provision.sh status
#
# Why Phase 2 requires direct SSH as the instance user:
#   openclaw gateway install creates a systemd user service via
#   `systemctl --user`. This requires XDG_RUNTIME_DIR=/run/user/<uid>/
#   (where the user's D-Bus socket lives) to be set. PAM only initializes
#   this at login time. sudo/su does not create a full PAM session, so
#   XDG_RUNTIME_DIR is not set and systemctl --user fails with
#   "Failed to connect to bus". Direct SSH is the only reliable path.
# ============================================================

NODE_MAJOR="22"
OPENCLAW_PKG="openclaw@latest"
PER_USER_NPM_PACKAGES="@steipete/summarize"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${CYAN}[STEP]${NC} $1"; }

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

# --- Phase 1: Setup (runs as root) ---
# Creates the user, configures npm prefix, installs OpenClaw, enables linger.
# Stops here — onboarding is interactive and must be done by the user.
phase_setup() {
    local user="$1"
    local port="$2"
    local home="/srv/${user}"

    if [ "$(id -u)" -ne 0 ]; then
        log_error "Phase 1 must run as root (sudo)."
        exit 1
    fi

    log_info "=== PHASE 1: Setup instance '${user}' (port ${port}) ==="

    # Prerequisite: system Node.js must already be installed
    # One-time server setup: see runbooks/06-openclaw.md Step 2
    if ! command -v node &>/dev/null; then
        log_error "System Node.js not found."
        log_error "Install Node.js ${NODE_MAJOR} LTS via NodeSource before running this script:"
        log_error "  curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | sudo -E bash -"
        log_error "  sudo apt install -y nodejs"
        exit 1
    fi
    NODE_VER=$(node --version | grep -oE '[0-9]+' | head -1)
    if (( NODE_VER < NODE_MAJOR )); then
        log_error "System Node.js v${NODE_VER} found, v${NODE_MAJOR}+ required."
        exit 1
    fi
    log_info "System Node.js: $(node --version) (ok)"

    # Create user
    if id "$user" &>/dev/null; then
        log_warn "User '$user' already exists. Skipping user creation."
    else
        log_info "Creating user '$user' with home in $home..."
        useradd -r -s /bin/bash -d "$home" -m "$user"
    fi

    # Enable linger — required so the user service starts at boot without
    # an active login session, and so systemctl --user works reliably.
    log_info "Enabling linger for '$user'..."
    loginctl enable-linger "$user"
    log_info "Linger: $(loginctl show-user "$user" | grep Linger)"

    # Configure npm prefix and install OpenClaw
    # npm prefix in ~/.local keeps binaries in ~/.local/bin without requiring root
    log_info "Configuring npm prefix and installing OpenClaw for '$user'..."
    sudo -u "$user" bash -l << SETUP_EOF
set -euo pipefail

# Configure per-user npm prefix — binaries in ~/.local/bin, no root required
mkdir -p "\$HOME/.local/bin"
npm config set prefix "\$HOME/.local"

# Add ~/.local/bin to PATH if not already present
if ! grep -q '.local/bin' "\$HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="\$HOME/.local/bin:\$PATH"' >> "\$HOME/.bashrc"
fi

# Install OpenClaw
PATH="\$HOME/.local/bin:\$PATH" npm install -g ${OPENCLAW_PKG}
echo "OpenClaw: \$(PATH="\$HOME/.local/bin:\$PATH" openclaw --version)"
SETUP_EOF

    log_info "Phase 1 complete for '${user}'."
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN} NEXT: complete onboarding for '${user}'${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  1. SSH directly as the instance user (not sudo su):"
    echo ""
    echo "       ssh ${user}@<IP_ADDRESS>"
    echo ""
    echo "  2. Run the interactive onboarding wizard:"
    echo ""
    echo "       openclaw onboard"
    echo ""
    echo "  3. After onboarding, run the post-onboard setup:"
    echo ""
    echo "       openclaw-provision.sh post-onboard"
    echo ""
}

# --- Phase 2: Post-onboard setup (runs as oc-* user via direct SSH) ---
# Installs the gateway service, per-user npm deps, verifies the setup.
# Must run as the instance user — not as root, not via sudo.
phase_post_onboard() {
    local user
    user="$(whoami)"

    # Refuse to run as root
    if [ "$(id -u)" -eq 0 ]; then
        log_error "post-onboard must run as the instance user (oc-*), not root."
        log_error "SSH directly as the instance user: ssh ${user}@<IP_ADDRESS>"
        exit 1
    fi

    if [[ ! "$user" =~ ^oc- ]]; then
        log_warn "Current user '$user' does not follow the oc-* naming convention. Continuing anyway."
    fi

    log_info "=== POST-ONBOARD SETUP for '${user}' ==="

    # Ensure ~/.local/bin is in PATH (npm prefix for this user)
    export PATH="${HOME}/.local/bin:${PATH}"

    # Check onboarding was completed
    if [ ! -f "${HOME}/.openclaw/openclaw.json" ]; then
        log_error "OpenClaw config not found. Run 'openclaw onboard' first."
        exit 1
    fi

    # Install gateway service
    log_step "Installing gateway service..."
    if openclaw gateway status 2>/dev/null | grep -q "Runtime: running"; then
        log_info "Gateway already running. Reinstalling service file..."
        openclaw gateway install --force
    else
        openclaw gateway install
    fi

    # Install per-user npm dependencies
    log_step "Installing per-user npm packages: ${PER_USER_NPM_PACKAGES}..."
    for pkg in ${PER_USER_NPM_PACKAGES}; do
        npm install -g "$pkg" && log_info "Installed: $pkg" || log_warn "Failed to install $pkg — check manually."
    done

    # Verify gateway — install already ran daemon-reload + enable + restart internally
    log_step "Verifying gateway..."
    sleep 3
    openclaw gateway status

    # Check port binding
    local port
    port=$(openclaw gateway status 2>/dev/null | grep -oE 'port=[0-9]+' | grep -oE '[0-9]+' || true)
    if [ -n "$port" ]; then
        if ss -tulpn | grep -q "127.0.0.1:${port}"; then
            log_info "Port ${port} listening on 127.0.0.1 (correct)."
        elif ss -tulpn | grep -q "0.0.0.0:${port}"; then
            log_error "Port ${port} is exposed on 0.0.0.0 — stop the service immediately!"
            openclaw gateway stop
            exit 1
        fi
    fi

    # Run doctor
    log_step "Running openclaw doctor..."
    openclaw doctor

    echo ""
    log_info "=== Post-onboard complete for '${user}' ==="
    echo ""
}

# --- Status (runs as root) ---
phase_status() {
    echo "=== Active OpenClaw instances (ports *789) ==="
    ss -tulpn | grep -E ":[0-9]*789 " || echo "No *789 ports listening."
    echo ""
    echo "=== Linger status for oc-* users ==="
    while IFS=: read -r u _ _ _ _ home _; do
        [[ "$u" =~ ^oc- ]] || continue
        if [ -f "/var/lib/systemd/linger/$u" ]; then
            echo "  $u: Linger=yes"
        else
            echo "  $u: Linger=no"
        fi
    done < /etc/passwd
}

# --- Main ---
case "${1:-}" in
    setup)
        [ $# -ne 3 ] && { echo "Usage: $0 setup <username> <port>"; exit 1; }
        validate_inputs "$2" "$3"
        phase_setup "$2" "$3"
        ;;
    batch)
        [ $# -ne 2 ] && { echo "Usage: $0 batch <config_file>"; exit 1; }
        config_file="$2"
        if [ ! -f "$config_file" ]; then
            log_error "Config file '$config_file' not found."
            exit 1
        fi
        if [ "$(id -u)" -ne 0 ]; then
            log_error "Batch setup must run as root (sudo)."
            exit 1
        fi
        log_info "Batch Phase 1 from '$config_file'..."
        while IFS= read -r line; do
            line="${line%%#*}"
            [[ -z "$line" || "$line" =~ ^[[:space:]]*$ ]] && continue
            read -r user port <<< "$line"
            [[ -z "$user" || -z "$port" ]] && continue
            validate_inputs "$user" "$port"
            phase_setup "$user" "$port"
        done < "$config_file"
        echo ""
        log_info "Batch Phase 1 complete. Now SSH as each user and run post-onboard."
        ;;
    post-onboard)
        phase_post_onboard
        ;;
    status)
        phase_status
        ;;
    *)
        echo "OpenClaw Instance Provisioner"
        echo ""
        echo "Usage:"
        echo "  sudo $0 setup <username> <port>    Phase 1: create user, configure npm prefix, install openclaw, enable linger"
        echo "  sudo $0 batch <config_file>        Phase 1 in batch for all instances in file"
        echo "  $0 post-onboard                    Phase 2: install service, deps, verify"
        echo "                                     (run as oc-* user via direct SSH, not sudo)"
        echo "  sudo $0 status                     Show active instances and linger status"
        echo ""
        echo "Typical workflow:"
        echo "  sudo $0 setup oc-work 18789"
        echo "  ssh oc-work@<IP>                   # direct SSH as instance user"
        echo "  openclaw onboard                   # interactive wizard"
        echo "  $0 post-onboard                    # install service and verify"
        echo ""
        echo "  # Or batch Phase 1, then SSH per user for onboard + post-onboard:"
        echo "  sudo $0 batch /srv/openclaw-instances.conf"
        ;;
esac
