#!/bin/bash

# Exit on error
set -e

# Define variables
readonly SETUP_DIR="/var/lib/jobdone"
readonly LOG_DIR="/var/log"
readonly BACKUP_DIR="${SETUP_DIR}/backups/$(date +%Y%m%d_%H%M%S)"
readonly SCRIPTS_DIR="/usr/local/bin"
readonly STATE_DIR="${SETUP_DIR}/state"

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

# Create necessary directories
mkdir -p "${BACKUP_DIR}" "${STATE_DIR}" "${LOG_DIR}"

# Get Tailscale auth key with validation
while true; do
    read -p "Enter your Tailscale auth key: " TAILSCALE_AUTH_KEY
    if [[ -z "${TAILSCALE_AUTH_KEY}" ]]; then
        echo "Error: Tailscale auth key cannot be empty"
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

#############################################
# Create main script
#############################################

echo "Creating main script..."
cat > "${SCRIPTS_DIR}/jobdone-boot.sh" << 'EOF'
#!/bin/bash

# Exit on error
set -e

# Define variables
readonly SETUP_DIR="/var/lib/jobdone"
readonly LOG_DIR="/var/log"
readonly SCRIPTS_DIR="/usr/local/bin"
readonly STATE_DIR="${SETUP_DIR}/state"
readonly SETUP_DONE_FILE="${STATE_DIR}/setup.done"
readonly TAILSCALE_DONE_FILE="${STATE_DIR}/tailscale.done"
readonly LOG_FILE="${LOG_DIR}/jobdone.log"

# Create necessary directories
mkdir -p "${STATE_DIR}" "${LOG_DIR}"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
    logger -t "jobdone" "$1"
}

# Function to check network connectivity
check_network() {
    ping -c 1 -W 5 1.1.1.1 >/dev/null 2>&1
}

# Function to check Tailscale connection
check_tailscale() {
    # Check if tailscale is installed and running
    if ! command -v tailscale &> /dev/null; then
        return 1
    fi
    
    if ! pgrep tailscaled &>/dev/null; then
        systemctl start tailscaled || return 1
        sleep 5
    fi
    
    # Check if tailscale is up
    timeout 10 tailscale status | grep -q "^100\.*" || return 1
    return 0
}

# One-time system setup
perform_system_setup() {
    if [ -f "${SETUP_DONE_FILE}" ]; then
        log "System setup already completed, skipping..."
        return 0
    fi

    log "Performing one-time system setup..."
    
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
    if ! DEBIAN_FRONTEND=noninteractive apt-get update; then
        log "Failed to update package list"
        exit 1
    fi

    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y curl unzip vim htop git net-tools wget ncdu tmux btop; then
        log "Failed to install required packages"
        exit 1
    fi

    # Mark setup as complete
    touch "${SETUP_DONE_FILE}"
    log "One-time setup completed"
}

# Main execution
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

# Initial delay to allow other boot processes to complete
log "Starting jobdone boot script..."
sleep 30

# Perform system setup first
perform_system_setup

# Install Tailscale if not present
if ! command -v tailscale &> /dev/null; then
    if [ ! -f "${TAILSCALE_DONE_FILE}" ]; then
        log "Installing Tailscale"
        curl -fsSL https://tailscale.com/install.sh | sh
        touch "${TAILSCALE_DONE_FILE}"
    fi
fi

# Loop until Tailscale is connected
log "Starting Tailscale connection loop..."
while true; do
    if ! check_network; then
        log "Waiting for network connectivity..."
        sleep 30
        continue
    fi

    if ! check_tailscale; then
        log "Attempting to connect to Tailscale"
        tailscale up --hostname="$(hostname)" --authkey=TAILSCALE_AUTH_KEY_PLACEHOLDER || true
        sleep 30
    else
        log "Tailscale successfully connected"
        break
    fi
done

# Remove cron job as we're done
rm -f /etc/cron.d/jobdone-boot
log "Setup complete, removed cron job"

exit 0
EOF

# Replace auth key placeholder
sed -i "s/TAILSCALE_AUTH_KEY_PLACEHOLDER/$TAILSCALE_AUTH_KEY/g" "${SCRIPTS_DIR}/jobdone-boot.sh"

# Set permissions and ownership
echo "Setting permissions and ownership..."
chmod +x "${SCRIPTS_DIR}/jobdone-boot.sh"
chown root:root "${SCRIPTS_DIR}/jobdone-boot.sh"

# Create log rotation configuration
cat > /etc/logrotate.d/jobdone << 'EOF'
/var/log/jobdone.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
}
EOF

# Set up cron job to run only at boot
echo "Setting up cron job..."
echo "@reboot root ${SCRIPTS_DIR}/jobdone-boot.sh >/dev/null 2>&1" > /etc/cron.d/jobdone-boot
chmod 644 /etc/cron.d/jobdone-boot

echo "Setup complete! Next steps:"
echo "1. Review the script in ${SCRIPTS_DIR}/jobdone-boot.sh"
echo "2. Check cron job in /etc/cron.d/jobdone-boot"
echo "3. Backup files are stored in ${BACKUP_DIR}"
echo "4. State files will be kept in ${STATE_DIR}"
echo "5. Logs will be written to ${LOG_DIR}/jobdone.log"
echo "6. Shutdown the VM and use it as a template."
echo "Note: The script will run at next boot and:"
echo "      - Perform one-time system setup (if not done)"
echo "      - Install and configure Tailscale"
echo "      - Loop until Tailscale is connected"
echo "      - Remove itself once everything is complete"