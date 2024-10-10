#!/bin/bash

# Update and clean the package lists
echo "Cleaning up apt and updating..."
sudo apt clean && sudo apt autoclean && sudo apt update && sudo apt upgrade -y

# Install curl if it's not installed
echo "Installing curl..."
sudo apt install curl -y

# Download and install the JobDone Nexus CLI
echo "Installing JobDone Nexus CLI..."
sudo curl -o /usr/local/bin/jobdone-nexus-cli https://raw.githubusercontent.com/jobdone-official/jobdone-nexus-cli/main/jobdone-nexus-cli
sudo chmod +x /usr/local/bin/jobdone-nexus-cli

echo "Setup complete!"