#!/bin/bash

# Exit on error
set -e

# Define variables
readonly SETUP_DIR="/var/lib/jobdone"
readonly LOG_DIR="/var/log"
readonly BACKUP_DIR="${SETUP_DIR}/backups/$(date +%Y%m%d_%H%M%S)"
readonly SCRIPTS_DIR="/usr/local/bin"
readonly STATE_DIR="${SETUP_DIR}/state"
readonly FRP_VERSION="0.61.1"
readonly FRP_DIR="/opt/frp"
readonly TAILSCALE_LOG="${LOG_DIR}/jobdone-tailscale.log"
readonly FRP_LOG="${LOG_DIR}/jobdone-frp.log"

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
mkdir -p "${BACKUP_DIR}" "${STATE_DIR}" "${LOG_DIR}" "${FRP_DIR}"
echo "Directories created successfully"

# Get required keys and URLs
while true; do
    read -p "Enter your Tailscale auth key: " TAILSCALE_AUTH_KEY
    if [[ -z "${TAILSCALE_AUTH_KEY}" ]]; then
        echo "Error: Tailscale auth key cannot be empty"
        continue
    fi
    break
done

while true; do
    read -p "Enter your FRP server address: " FRP_SERVER_ADDR
    if [[ -z "${FRP_SERVER_ADDR}" ]]; then
        echo "Error: FRP server address cannot be empty"
        continue
    fi
    break
done

while true; do
    read -p "Enter your FRP auth token: " FRP_AUTH_TOKEN
    if [[ -z "${FRP_AUTH_TOKEN}" ]]; then
        echo "Error: FRP auth token cannot be empty"
        continue
    fi
    break
done

while true; do
    read -p "Enter your Discord webhook URL: " DISCORD_WEBHOOK_URL
    if [[ -z "${DISCORD_WEBHOOK_URL}" ]]; then
        echo "Error: Discord webhook URL cannot be empty"
        continue
    fi
    break
done

echo "Configuration received"

# Download and verify frp
echo "Downloading frp and checksums..."
wget https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_amd64.tar.gz -O /tmp/frp.tar.gz
wget https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_sha256_checksums.txt -O /tmp/frp_checksums.txt

# Verify checksum
echo "Verifying frp checksum..."
EXPECTED_CHECKSUM=$(grep "frp_${FRP_VERSION}_linux_amd64.tar.gz" /tmp/frp_checksums.txt | cut -d' ' -f1)
ACTUAL_CHECKSUM=$(sha256sum /tmp/frp.tar.gz | cut -d' ' -f1)

if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]; then
    echo "Checksum verification failed!"
    echo "Expected: $EXPECTED_CHECKSUM"
    echo "Got: $ACTUAL_CHECKSUM"
    rm -f /tmp/frp.tar.gz /tmp/frp_checksums.txt
    exit 1
fi

echo "Checksum verification successful"

# Extract and set up frp
echo "Extracting and setting up frp..."
tar -xf /tmp/frp.tar.gz -C /tmp
mv /tmp/frp_${FRP_VERSION}_linux_amd64/frpc "${FRP_DIR}/frpc"
chmod +x "${FRP_DIR}/frpc"
rm -rf /tmp/frp.tar.gz /tmp/frp_checksums.txt /tmp/frp_${FRP_VERSION}_linux_amd64

# Create frpc configuration
cat > "${FRP_DIR}/frpc.toml" << EOF
serverAddr = "${FRP_SERVER_ADDR}"
serverPort = 7000
auth.method = "token"
auth.token = "${FRP_AUTH_TOKEN}"

[[proxies]]
name = "ssh-$(hostname)"
type = "stcp"
secretKey = "${FRP_AUTH_TOKEN}"
localIP = "127.0.0.1"
localPort = 22
EOF

#############################################
# Create Discord boot script (0)
#############################################

echo "Creating Discord boot notification script..."
cat > "${SCRIPTS_DIR}/0-jobdone-discord.sh" << 'EOF'
#!/bin/bash

# Define variables
readonly SETUP_DIR="/var/lib/jobdone"
readonly LOG_DIR="/var/log"
readonly STATE_DIR="${SETUP_DIR}/state"
readonly DISCORD_LOG="${LOG_DIR}/jobdone-discord.log"
readonly DISCORD_WEBHOOK_URL="DISCORD_WEBHOOK_URL_PLACEHOLDER"

# Logging function
log_discord() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" >> "${DISCORD_LOG}"
}

# Error handling
trap 'log_discord "Error: Script failed on line $LINENO"; exit 1' ERR

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_discord "Script must be run as root"
    exit 1
fi

# Create necessary directories
mkdir -p "${LOG_DIR}"

# Discord notification function
send_discord_notification() {
    local message="$1"
    local hostname=$(hostname)
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local uptime=$(uptime -p)
    local ip_addr=$(hostname -I | awk '{print $1}')
    
    log_discord "Sending boot notification to Discord..."
    
    curl -H "Content-Type: application/json" \
         -d "{\"content\":null,\"embeds\":[{\"title\":\"[$(hostname)] VM Boot Alert\",\"description\":\"$message\",\"color\":3447003,\"fields\":[{\"name\":\"Hostname\",\"value\":\"$hostname\",\"inline\":true},{\"name\":\"Timestamp\",\"value\":\"$timestamp\",\"inline\":true},{\"name\":\"Uptime\",\"value\":\"$uptime\",\"inline\":true},{\"name\":\"IP Address\",\"value\":\"$ip_addr\",\"inline\":true}]}]}" \
         "${DISCORD_WEBHOOK_URL}" \
         2>> "${DISCORD_LOG}"
         
    if [ $? -eq 0 ]; then
        log_discord "Discord notification sent successfully"
    else
        log_discord "Failed to send Discord notification"
    fi
}

# Main execution
log_discord "Starting boot notification script..."

# Wait for network to be available
log_discord "Waiting for network connectivity..."
for i in {1..12}; do  # Try for 1 minute (5 seconds * 12)
    if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1 || ping -c 1 -W 5 1.1.1.1 >/dev/null 2>&1; then
        log_discord "Network connectivity established"
        send_discord_notification "🟢 VM has booted successfully"
        exit 0
    fi
    sleep 5
done

log_discord "Failed to establish network connectivity"
exit 1
EOF

#############################################
# Create Tailscale boot script (1)
#############################################

echo "Creating Tailscale boot script..."
cat > "${SCRIPTS_DIR}/1-jobdone-tailscale.sh" << 'EOF'
#!/bin/bash

# Define variables
readonly SETUP_DIR="/var/lib/jobdone"
readonly LOG_DIR="/var/log"
readonly STATE_DIR="${SETUP_DIR}/state"
readonly SETUP_DONE_FILE="${STATE_DIR}/setup.done"
readonly TAILSCALE_DONE_FILE="${STATE_DIR}/tailscale.done"
readonly TAILSCALE_LOG="${LOG_DIR}/jobdone-tailscale.log"
readonly DISCORD_WEBHOOK_URL="DISCORD_WEBHOOK_URL_PLACEHOLDER"

# Logging function
log_tailscale() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" >> "${TAILSCALE_LOG}"
}

# Discord notification function
send_discord_notification() {
    local message="$1"
    local hostname=$(hostname)
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    curl -H "Content-Type: application/json" \
         -d "{\"content\":null,\"embeds\":[{\"title\":\"VM Status Update\",\"description\":\"$message\",\"color\":3447003,\"fields\":[{\"name\":\"Hostname\",\"value\":\"$hostname\",\"inline\":true},{\"name\":\"Timestamp\",\"value\":\"$timestamp\",\"inline\":true}]}]}" \
         "${DISCORD_WEBHOOK_URL}"
}

# One-time system setup
perform_system_setup() {
    if [ -f "${SETUP_DONE_FILE}" ]; then
        log_tailscale "System setup already completed, skipping..."
        return 0
    fi

    log_tailscale "Starting one-time system setup..."
    
    # Set timezone
    log_tailscale "Setting timezone to UTC"
    timedatectl set-timezone UTC
    log_tailscale "Timezone set successfully"

    # Reset machine-id with proper error handling
    log_tailscale "Regenerating machine-id..."
    rm -f /etc/machine-id
    if ! systemd-machine-id-setup; then
        log_tailscale "Failed to regenerate machine-id"
        exit 1
    fi
    log_tailscale "Machine-id regenerated successfully"

    # Generate hostname
    DATE_TIME=$(date +%y%m%d_%H%M)
    MACHINE_ID=$(cat /etc/machine-id | cut -c-4)
    HOSTNAME="jobdone-debian-${DATE_TIME}-${MACHINE_ID}"

    log_tailscale "Setting hostname to: ${HOSTNAME}"
    hostnamectl set-hostname "${HOSTNAME}"
    sed -i "s/127\.0\.1\.1.*/127.0.1.1\t${HOSTNAME}/" /etc/hosts
    log_tailscale "Hostname set successfully"

    # Install base packages with retry logic
    log_tailscale "Starting package installation process..."
    
    # First try to update package lists
    apt_update_successful=false
    for i in {1..3}; do
        log_tailscale "Attempting apt-get update (attempt $i of 3)"
        if DEBIAN_FRONTEND=noninteractive apt-get update; then
            apt_update_successful=true
            log_tailscale "Package list update successful"
            break
        fi
        log_tailscale "Package list update attempt $i failed"
        sleep 10
    done

    if ! $apt_update_successful; then
        log_tailscale "Failed to update package list after 3 attempts"
        exit 1
    fi

    # Then install packages with retry logic
    log_tailscale "Installing required packages..."
    for i in {1..3}; do
        if DEBIAN_FRONTEND=noninteractive apt-get install -y curl unzip vim htop git net-tools wget ncdu tmux btop; then
            log_tailscale "Package installation successful"
            break
        fi
        log_tailscale "Package installation attempt $i failed"
        sleep 10
    done
    if [[ $i -eq 3 ]]; then
        log_tailscale "Failed to install packages after 3 attempts"
        exit 1
    fi

    # Mark setup as complete
    touch "${SETUP_DONE_FILE}"
    log_tailscale "One-time setup completed successfully"
    send_discord_notification "System setup completed successfully on $(hostname)"
}

# Check network connectivity
check_network() {
    log_tailscale "Checking network connectivity..."
    if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        log_tailscale "Network check successful using 8.8.8.8"
        return 0
    elif ping -c 1 -W 5 1.1.1.1 >/dev/null 2>&1; then
        log_tailscale "Network check successful using 1.1.1.1"
        return 0
    elif curl -s --connect-timeout 5 https://example.com >/dev/null; then
        log_tailscale "Network check successful using https://example.com"
        return 0
    fi
    log_tailscale "All network checks failed"
    return 1
}

# Check Tailscale connection
check_tailscale() {
    log_tailscale "Checking Tailscale status..."
    
    if ! command -v tailscale &> /dev/null; then
        log_tailscale "Tailscale binary not found"
        return 1
    fi
    
    if ! pgrep tailscaled &>/dev/null; then
        log_tailscale "Tailscale daemon not running, attempting to start..."
        systemctl start tailscaled
        log_tailscale "Waiting for Tailscale service to initialize..."
        timeout 30 bash -c 'until tailscale status; do sleep 1; done'
    fi
    
    if timeout 10 tailscale status | grep -q "^100\.*"; then
        log_tailscale "Tailscale is connected and running"
        return 0
    else
        log_tailscale "Tailscale is not fully connected"
        return 1
    fi
}

# Main execution
if [[ $EUID -ne 0 ]]; then
    log_tailscale "Script must be run as root"
    exit 1
fi

# Send startup notification
send_discord_notification "VM $(hostname) is starting up"

# Perform system setup first
perform_system_setup

# Install Tailscale if not present
if ! command -v tailscale &> /dev/null; then
    if [ ! -f "${TAILSCALE_DONE_FILE}" ]; then
        log_tailscale "Installing Tailscale..."
        if curl -fsSL https://tailscale.com/install.sh | sh; then
            touch "${TAILSCALE_DONE_FILE}"
            log_tailscale "Tailscale installation successful"
            send_discord_notification "Tailscale installed successfully on $(hostname)"
        else
            log_tailscale "Tailscale installation failed"
            send_discord_notification "Tailscale installation failed on $(hostname)"
        fi
    fi
fi

# Try to connect Tailscale
if check_network; then
    if ! check_tailscale; then
        log_tailscale "Attempting to connect to Tailscale..."
        if tailscale up --hostname="$(hostname)" --authkey=TAILSCALE_AUTH_KEY_PLACEHOLDER; then
            log_tailscale "Tailscale connection successful"
            send_discord_notification "Tailscale connected successfully on $(hostname)"
        else
            log_tailscale "Tailscale connection attempt failed"
            send_discord_notification "Tailscale connection failed on $(hostname)"
        fi
    else
        log_tailscale "Tailscale already connected"
    fi
else
    log_tailscale "No network connectivity"
    send_discord_notification "Network connectivity issues on $(hostname)"
fi

exit 0
EOF

#############################################
# Create FRP boot script (2)
#############################################

echo "Creating FRP boot script..."
cat > "${SCRIPTS_DIR}/2-jobdone-frp.sh" << 'EOF'
#!/bin/bash

# Define variables
readonly LOG_DIR="/var/log"
readonly FRP_DIR="/opt/frp"
readonly FRP_LOG="${LOG_DIR}/jobdone-frp.log"
readonly DISCORD_WEBHOOK_URL="DISCORD_WEBHOOK_URL_PLACEHOLDER"

# Logging function
log_frp() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" >> "${FRP_LOG}"
}

# Discord notification function
send_discord_notification() {
    local message="$1"
    local hostname=$(hostname)
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    curl -H "Content-Type: application/json" \
         -d "{\"content\":null,\"embeds\":[{\"title\":\"VM Status Update\",\"description\":\"$message\",\"color\":3447003,\"fields\":[{\"name\":\"Hostname\",\"value\":\"$hostname\",\"inline\":true},{\"name\":\"Timestamp\",\"value\":\"$timestamp\",\"inline\":true}]}]}" \
         "${DISCORD_WEBHOOK_URL}"
}

# Start frp
start_frp() {
    # Kill any existing frp process
    pkill -f "${FRP_DIR}/frpc" || true
    sleep 2
    
    log_frp "Starting frp client..."
    nohup "${FRP_DIR}/frpc" -c "${FRP_DIR}/frpc.toml" >> "${FRP_LOG}" 2>&1 &
    
    # Wait a bit and check if process is running
    sleep 5
    if pgrep -f "${FRP_DIR}/frpc" > /dev/null; then
        log_frp "frp client started successfully"
        send_discord_notification "FRP client started successfully on $(hostname)"
    else
        log_frp "Failed to start frp client"
        send_discord_notification "Failed to start FRP client on $(hostname)"
    fi
}

# Main execution
log_frp "Waiting 180 seconds before starting FRP..."
sleep 180

# Start FRP
start_frp

exit 0
EOF

# Replace placeholders in both scripts
echo "Replacing placeholders in boot scripts..."
sed -i "s/TAILSCALE_AUTH_KEY_PLACEHOLDER/$TAILSCALE_AUTH_KEY/g" "${SCRIPTS_DIR}/1-jobdone-tailscale.sh"
sed -i "s|DISCORD_WEBHOOK_URL_PLACEHOLDER|$DISCORD_WEBHOOK_URL|g" "${SCRIPTS_DIR}/0-jobdone-discord.sh"
sed -i "s|DISCORD_WEBHOOK_URL_PLACEHOLDER|$DISCORD_WEBHOOK_URL|g" "${SCRIPTS_DIR}/1-jobdone-tailscale.sh"
sed -i "s|DISCORD_WEBHOOK_URL_PLACEHOLDER|$DISCORD_WEBHOOK_URL|g" "${SCRIPTS_DIR}/2-jobdone-frp.sh"

# Set permissions and ownership
echo "Setting permissions and ownership..."
chmod +x "${SCRIPTS_DIR}/0-jobdone-discord.sh"
chmod +x "${SCRIPTS_DIR}/1-jobdone-tailscale.sh"
chmod +x "${SCRIPTS_DIR}/2-jobdone-frp.sh"
chown root:root "${SCRIPTS_DIR}/0-jobdone-discord.sh"
chown root:root "${SCRIPTS_DIR}/1-jobdone-tailscale.sh"
chown root:root "${SCRIPTS_DIR}/2-jobdone-frp.sh"

# Create log rotation configuration
echo "Creating log rotation configuration..."
cat > /etc/logrotate.d/jobdone << 'EOF'
/var/log/jobdone-discord.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
}

/var/log/jobdone-tailscale.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
}

/var/log/jobdone-frp.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
}
EOF

# Set up cron jobs to run at boot
echo "Setting up cron jobs..."
echo "@reboot root ${SCRIPTS_DIR}/0-jobdone-discord.sh" > /etc/cron.d/jobdone-discord
echo "@reboot root ${SCRIPTS_DIR}/1-jobdone-tailscale.sh" > /etc/cron.d/jobdone-tailscale
echo "@reboot root ${SCRIPTS_DIR}/2-jobdone-frp.sh" > /etc/cron.d/jobdone-frp
chmod 644 /etc/cron.d/jobdone-discord
chmod 644 /etc/cron.d/jobdone-tailscale
chmod 644 /etc/cron.d/jobdone-frp

# Send initial Discord notification
curl -H "Content-Type: application/json" \
     -d "{\"content\":null,\"embeds\":[{\"title\":\"VM Status Update\",\"description\":\"New VM $(hostname) has been configured and is ready for first boot\",\"color\":3447003,\"fields\":[{\"name\":\"Hostname\",\"value\":\"$(hostname)\",\"inline\":true},{\"name\":\"Timestamp\",\"value\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\"inline\":true}]}]}" \
     "${DISCORD_WEBHOOK_URL}"

echo "Setup complete! Next steps:"
echo "1. Review the scripts:"
echo "   - ${SCRIPTS_DIR}/0-jobdone-discord.sh"
echo "   - ${SCRIPTS_DIR}/1-jobdone-tailscale.sh"
echo "   - ${SCRIPTS_DIR}/2-jobdone-frp.sh"
echo "2. Check cron jobs:"
echo "   - /etc/cron.d/jobdone-discord"
echo "   - /etc/cron.d/jobdone-tailscale"
echo "   - /etc/cron.d/jobdone-frp"
echo "3. Backup files are stored in ${BACKUP_DIR}"
echo "4. State files will be kept in ${STATE_DIR}"
echo "5. Logs will be written to:"
echo "   - ${DISCORD_LOG}"
echo "   - ${TAILSCALE_LOG}"
echo "   - ${FRP_LOG}"
echo "6. Discord notifications have been configured"
echo "7. Shutdown the VM and use it as a template."
echo "Note: All scripts will run at each boot:"
echo "      - Script 0: Discord boot notification"
echo "      - Script 1: Tailscale setup and connection"
echo "      - Script 2: FRP start (after 3 minute delay)"