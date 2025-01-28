#!/bin/bash

# Exit on error
set -e

# Define variables
readonly SETUP_DIR="/var/lib/jobdone"
readonly LOG_DIR="/var/log"
readonly BACKUP_DIR="${SETUP_DIR}/backups/$(date +%Y%m%d_%H%M%S)"
readonly SCRIPTS_DIR="/usr/local/bin"
readonly SYSTEMD_DIR="/etc/systemd/system"

# Error handling
trap 'echo "Error: Script failed on line $LINENO"; exit 1' ERR

# Check if we have sudo privileges without password
if ! sudo -n true 2>/dev/null; then
    echo "This script needs to be run with sudo privileges"
    echo "Please run: sudo $0"
    exit 1
fi

# If we're not root, re-run the script with sudo
if [[ $EUID -ne 0 ]]; then
    exec sudo "$0" "$@"
fi

# Create backup directory
mkdir -p "${BACKUP_DIR}"

# Get Tailscale auth key with validation
while true; do
    read -p "Enter your Tailscale auth key: " TAILSCALE_AUTH_KEY
    if [[ -z "${TAILSCALE_AUTH_KEY}" ]]; then
        echo "Error: Tailscale auth key cannot be empty"
        continue
    fi
    if [[ ! "${TAILSCALE_AUTH_KEY}" =~ ^tskey-[a-zA-Z0-9]+$ ]]; then
        echo "Error: Invalid Tailscale auth key format"
        continue
    fi
    break
done

# Backup existing files if they exist
for file in /etc/hosts /etc/machine-id; do
    if [[ -f "$file" ]]; then
        cp "$file" "${BACKUP_DIR}/$(basename $file).bak"
    fi
done

# Create service files
echo "Creating service files..."

# Create initial setup service
cat > "${SYSTEMD_DIR}/jobdone-initial-setup.service" << 'EOF'
[Unit]
Description=Initial JobDone VM Setup and Tailscale Installation
After=network-online.target
Wants=network-online.target
Before=jobdone-tailscale-check.service
StartLimitIntervalSec=300
StartLimitBurst=3

[Service]
Type=oneshot
User=root
Group=root
ExecStart=/usr/local/bin/jobdone-initial-setup.sh
RemainAfterExit=yes
ExecStartPre=/bin/sh -c 'if [ -f /var/lib/jobdone/setup-completed ]; then exit 0; else exit 1; fi'
ExecStartPost=/bin/sh -c 'mkdir -p /var/lib/jobdone && touch /var/lib/jobdone/setup-completed'
ProtectSystem=full
ProtectHome=true
PrivateTmp=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

# Create Tailscale check service
cat > "${SYSTEMD_DIR}/jobdone-tailscale-check.service" << 'EOF'
[Unit]
Description=Tailscale Connection Check
After=network-online.target tailscaled.service jobdone-initial-setup.service
Wants=network-online.target
Requires=jobdone-initial-setup.service

[Service]
Type=simple
User=root
Group=root
ExecStart=/usr/local/bin/jobdone-tailscale-check.sh
Restart=on-failure
ProtectSystem=full
ProtectHome=true
PrivateTmp=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

# Create initial setup script
echo "Creating initial setup script..."
cat > "${SCRIPTS_DIR}/jobdone-initial-setup.sh" << 'EOF'
#!/bin/bash
set -e

# Error handling
trap 'echo "Error: Script failed on line $LINENO"; exit 1' ERR

# Set up logging
LOG_FILE="/var/log/jobdone-initial-setup.log"
exec 1> >(tee -a "${LOG_FILE}") 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
    logger -t "jobdone-initial-setup" "$1"
}

log "Starting initial JobDone setup"

# Set timezone
log "Setting timezone to UTC"
timedatectl set-timezone UTC

# Reset machine-id
log "Regenerating machine-id"
rm -f /etc/machine-id
systemd-machine-id-setup

# Generate hostname
DATE_TIME=$(date +%y%m%d_%H%M)
MACHINE_ID=$(cat /etc/machine-id | cut -c-4)
HOSTNAME="jobdone-debian-${DATE_TIME}-${MACHINE_ID}"

log "Setting hostname to: ${HOSTNAME}"
hostnamectl set-hostname "${HOSTNAME}"
sed -i "s/127\.0\.1\.1.*/127.0.1.1\t${HOSTNAME}/" /etc/hosts

# Install base packages
log "Installing base packages"
apt update || {
    log "ERROR: Failed to update package list"
    exit 1
}
apt install -y curl unzip vim htop git net-tools wget ncdu tmux btop || {
    log "ERROR: Failed to install base packages"
    exit 1
}

# Install and configure Tailscale
log "Installing Tailscale"
curl -fsSL https://tailscale.com/install.sh | sh || {
    log "ERROR: Failed to install Tailscale"
    exit 1
}

log "Removing any existing Tailscale state"
rm -f /var/lib/tailscale/tailscaled.state

# Function to check network connectivity
check_network() {
    ping -c 1 -W 5 1.1.1.1 >/dev/null 2>&1
}

# Wait for network connectivity
MAX_RETRIES=30
RETRY_COUNT=0
while ! check_network; do
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        log "ERROR: Network connectivity not available after $MAX_RETRIES attempts"
        exit 1
    fi
    log "Waiting for network connectivity... (attempt $((RETRY_COUNT+1))/$MAX_RETRIES)"
    sleep 10
    RETRY_COUNT=$((RETRY_COUNT+1))
done

log "Starting Tailscale with new hostname"
if ! tailscale up --hostname="${HOSTNAME}" --authkey=TAILSCALE_AUTH_KEY_PLACEHOLDER; then
    log "ERROR: Failed to connect to Tailscale"
    exit 1
fi

# Enable the check service for future boots
systemctl enable jobdone-tailscale-check || {
    log "ERROR: Failed to enable Tailscale check service"
    exit 1
}

log "Initial JobDone setup complete"
EOF

# Create Tailscale check script
echo "Creating Tailscale check script..."
cat > "${SCRIPTS_DIR}/jobdone-tailscale-check.sh" << 'EOF'
#!/bin/bash
set -e

# Error handling
trap 'echo "Error: Script failed on line $LINENO"; exit 1' ERR

# Set up logging
LOG_FILE="/var/log/jobdone-tailscale-check.log"
exec 1> >(tee -a "${LOG_FILE}") 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
    logger -t "jobdone-tailscale-check" "$1"
}

check_connection() {
    # Check if tailscale is installed
    if ! command -v tailscale &> /dev/null; then
        log "ERROR: Tailscale not installed"
        return 1
    fi

    # Check if tailscale daemon is running
    if ! systemctl is-active --quiet tailscaled; then
        log "WARNING: Tailscale daemon not running, attempting to start"
        if ! systemctl start tailscaled; then
            log "ERROR: Failed to start tailscaled"
            return 1
        fi
        sleep 5
    fi

    # Check if tailscale is up with timeout
    if ! timeout 10 tailscale status | grep -q "^100\..*"; then
        log "WARNING: Tailscale not connected"
        return 1
    fi

    log "SUCCESS: Tailscale is running and connected"
    return 0
}

# Main loop
while true; do
    if ! check_connection; then
        log "Attempting to connect to Tailscale"
        tailscale up --hostname="$(hostname)" --authkey=TAILSCALE_AUTH_KEY_PLACEHOLDER || true
        
        # Wait before next check
        sleep 10
    else
        # Everything is good, wait longer before next check
        sleep 300
    fi
done
EOF

# Replace auth key placeholder in both scripts
sed -i "s/TAILSCALE_AUTH_KEY_PLACEHOLDER/$TAILSCALE_AUTH_KEY/g" "${SCRIPTS_DIR}/jobdone-initial-setup.sh"
sed -i "s/TAILSCALE_AUTH_KEY_PLACEHOLDER/$TAILSCALE_AUTH_KEY/g" "${SCRIPTS_DIR}/jobdone-tailscale-check.sh"

# Set permissions and ownership
echo "Setting permissions and ownership..."
chmod +x "${SCRIPTS_DIR}/jobdone-initial-setup.sh"
chmod +x "${SCRIPTS_DIR}/jobdone-tailscale-check.sh"
chmod 644 "${SYSTEMD_DIR}/jobdone-initial-setup.service"
chmod 644 "${SYSTEMD_DIR}/jobdone-tailscale-check.service"

# Set ownership
chown root:root "${SCRIPTS_DIR}/jobdone-initial-setup.sh"
chown root:root "${SCRIPTS_DIR}/jobdone-tailscale-check.sh"
chown root:root "${SYSTEMD_DIR}/jobdone-initial-setup.service"
chown root:root "${SYSTEMD_DIR}/jobdone-tailscale-check.service"

# Create log rotation configuration
cat > /etc/logrotate.d/jobdone << 'EOF'
/var/log/jobdone-*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
}
EOF

# Enable services
echo "Enabling services..."
systemctl daemon-reload
systemctl enable jobdone-initial-setup
systemctl enable jobdone-tailscale-check

echo "Setup complete! Next steps:"
echo "1. Review the scripts in ${SCRIPTS_DIR}/"
echo "2. Check service status with: systemctl status jobdone-initial-setup"
echo "3. Check logs in ${LOG_DIR}/jobdone-*.log"
echo "4. Backup files are stored in ${BACKUP_DIR}"
echo "5. Shutdown the VM and use it as a template"