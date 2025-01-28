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
echo "Creating required directories..."
mkdir -p "${BACKUP_DIR}" "${STATE_DIR}" "${LOG_DIR}"
echo "Directories created successfully"

# Get Tailscale auth key with validation
while true; do
    read -p "Enter your Tailscale auth key: " TAILSCALE_AUTH_KEY
    if [[ -z "${TAILSCALE_AUTH_KEY}" ]]; then
        echo "Error: Tailscale auth key cannot be empty"
        continue
    fi
    break
done
echo "Tailscale auth key received"

# Backup existing files if they exist
echo "Starting backup of existing configuration files..."
for file in /etc/hosts /etc/machine-id; do
    if [[ -f "$file" ]]; then
        echo "Backing up $file to ${BACKUP_DIR}/$(basename $file).bak"
        cp "$file" "${BACKUP_DIR}/$(basename $file).bak"
    else
        echo "File $file does not exist, skipping backup"
    fi
done
echo "Backup process completed"

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
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | tee -a "${LOG_FILE}"
    logger -t "jobdone" "$1"
}

# Enhanced network check function with multiple endpoints
check_network() {
    log "Checking network connectivity..."
    if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        log "Network check successful using 8.8.8.8"
        return 0
    elif ping -c 1 -W 5 1.1.1.1 >/dev/null 2>&1; then
        log "Network check successful using 1.1.1.1"
        return 0
    elif curl -s --connect-timeout 5 https://example.com >/dev/null; then
        log "Network check successful using https://example.com"
        return 0
    fi
    log "All network checks failed"
    return 1
}

# Function to check Tailscale connection
check_tailscale() {
    log "Checking Tailscale status..."
    
    # Check if tailscale is installed
    if ! command -v tailscale &> /dev/null; then
        log "Tailscale binary not found"
        return 1
    fi
    
    # Check if tailscale daemon is running and start if needed
    if ! pgrep tailscaled &>/dev/null; then
        log "Tailscale daemon not running, attempting to start..."
        systemctl start tailscaled
        # Wait up to 30 seconds for service to start
        log "Waiting for Tailscale service to initialize..."
        timeout 30 bash -c 'until tailscale status; do sleep 1; done'
    fi
    
    # Check if tailscale is up
    log "Checking Tailscale connection status..."
    if timeout 10 tailscale status | grep -q "^100\.*"; then
        log "Tailscale is connected and running"
        return 0
    else
        log "Tailscale is not fully connected"
        return 1
    fi
}

# One-time system setup
perform_system_setup() {
    if [ -f "${SETUP_DONE_FILE}" ]; then
        log "System setup already completed, skipping..."
        return 0
    fi

    log "Starting one-time system setup..."
    
    # Set timezone
    log "Setting timezone to UTC"
    timedatectl set-timezone UTC
    log "Timezone set successfully"

    # Reset machine-id with proper error handling
    log "Regenerating machine-id..."
    rm -f /etc/machine-id
    if ! systemd-machine-id-setup; then
        log "Failed to regenerate machine-id"
        exit 1
    fi
    log "Machine-id regenerated successfully"

    # Generate hostname
    DATE_TIME=$(date +%y%m%d_%H%M)
    MACHINE_ID=$(cat /etc/machine-id | cut -c-4)
    HOSTNAME="jobdone-debian-${DATE_TIME}-${MACHINE_ID}"

    log "Setting hostname to: ${HOSTNAME}"
    hostnamectl set-hostname "${HOSTNAME}"
    sed -i "s/127\.0\.1\.1.*/127.0.1.1\t${HOSTNAME}/" /etc/hosts
    log "Hostname set successfully"

    # Install base packages with retry logic
    log "Starting package installation process..."
    
    # First try to update package lists
    apt_update_successful=false
    for i in {1..3}; do
        log "Attempting apt-get update (attempt $i of 3)"
        if DEBIAN_FRONTEND=noninteractive apt-get update; then
            apt_update_successful=true
            log "Package list update successful"
            break
        fi
        log "Package list update attempt $i failed"
        sleep 10
    done

    if ! $apt_update_successful; then
        log "Failed to update package list after 3 attempts"
        exit 1
    fi

    # Then install packages with retry logic
    log "Installing required packages..."
    for i in {1..3}; do
        if DEBIAN_FRONTEND=noninteractive apt-get install -y curl unzip vim htop git net-tools wget ncdu tmux btop; then
            log "Package installation successful"
            break
        fi
        log "Package installation attempt $i failed"
        sleep 10
    done
    if [[ $i -eq 3 ]]; then
        log "Failed to install packages after 3 attempts"
        exit 1
    fi

    # Mark setup as complete
    touch "${SETUP_DONE_FILE}"
    log "One-time setup completed successfully"
}

# Main execution
if [[ $EUID -ne 0 ]]; then
    log "Script must be run as root"
    exit 1
fi

# Initial delay to allow other boot processes to complete
log "Starting jobdone boot script..."
log "Waiting 30 seconds for system initialization..."
sleep 30

# Perform system setup first
perform_system_setup

# Install Tailscale if not present with proper error handling
if ! command -v tailscale &> /dev/null; then
    if [ ! -f "${TAILSCALE_DONE_FILE}" ]; then
        log "Installing Tailscale..."
        if curl -fsSL https://tailscale.com/install.sh | sh; then
            touch "${TAILSCALE_DONE_FILE}"
            log "Tailscale installation successful"
        else
            log "Tailscale installation failed"
            exit 1
        fi
    fi
fi

# Loop until Tailscale is connected
log "Starting Tailscale connection loop..."
while true; do
    if ! check_network; then
        log "No network connectivity, waiting 30 seconds before retry..."
        sleep 30
        continue
    fi

    if ! check_tailscale; then
        log "Attempting to connect to Tailscale..."
        if tailscale up --hostname="$(hostname)" --authkey=TAILSCALE_AUTH_KEY_PLACEHOLDER; then
            log "Tailscale connection attempt successful"
        else
            log "Tailscale connection attempt failed"
        fi
        sleep 30
    else
        log "Tailscale successfully connected"
        break
    fi
done

# Remove cron job as we're done
log "Removing boot script from cron..."
rm -f /etc/cron.d/jobdone-boot
log "Setup complete, cron job removed"

exit 0
EOF

# Replace auth key placeholder
echo "Replacing Tailscale auth key in boot script..."
sed -i "s/TAILSCALE_AUTH_KEY_PLACEHOLDER/$TAILSCALE_AUTH_KEY/g" "${SCRIPTS_DIR}/jobdone-boot.sh"

# Set permissions and ownership
echo "Setting permissions and ownership..."
chmod +x "${SCRIPTS_DIR}/jobdone-boot.sh"
chown root:root "${SCRIPTS_DIR}/jobdone-boot.sh"

# Create log rotation configuration
echo "Creating log rotation configuration..."
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
echo "@reboot root ${SCRIPTS_DIR}/jobdone-boot.sh >> ${LOG_DIR}/jobdone.log 2>&1" > /etc/cron.d/jobdone-boot
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