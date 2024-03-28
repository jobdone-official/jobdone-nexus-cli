# jobdone-nexus-cli 🌐

## Installation 🛠️

This section guides you through the installation process of `jobdone-nexus-cli`. Begin by ensuring you have root access, as the installation requires elevated permissions.

### Prerequisites

Execute the following commands:

```bash
sudo mkdir -p ~/.ssh
sudo chmod 700 ~/.ssh
```

Add the private key:

1. Type `sudo vi ~/.ssh/id_ed25519` to create or edit the private key file in your `.ssh` directory.
1. Press `i` to switch to insert mode.
1. Paste your private key content into the editor.
1. Press `Esc` to exit insert mode.
1. Type `:wq` and press `Enter` to save the changes and exit vi.

Add the public key:

1. Type `sudo vi ~/.ssh/id_ed25519.pub` to create or edit the public key file in your `.ssh` directory. Again, adjust the filename as necessary.
1. Press `i` to switch to insert mode.
1. Paste your public key content into the editor.
1. Press `Esc` to exit insert mode.
1. Type `:wq` and press `Enter` to save the changes and exit vi.

Execute the following commands:

```bash
sudo chmod 600 ~/.ssh/id_ed25519
sudo chmod 644 ~/.ssh/id_ed25519.pub
```

### Install Dependencies and `jobdone-nexus-cli`

Run the following commands to clean up your package lists, update your system, install necessary packages like `curl`, and download and install the `jobdone-nexus-cli`:

```bash
sudo apt clean && sudo apt autoclean && sudo apt update && sudo apt upgrade -y

sudo apt install curl -y

sudo curl -o /usr/local/bin/jobdone-nexus-cli https://raw.githubusercontent.com/jobdone-official/jobdone-nexus-cli/main/jobdone-nexus-cli && sudo chmod +x /usr/local/bin/jobdone-nexus-cli
```

## Usage 🔍

To install and configure the jobdone-nexus-cli, use the following command format. This command includes mandatory parameters for setting up the hostname, ZeroTier IP prefix, Tactical RMM mesh agent, API URL, client ID, site ID, and auth key. Optional network configuration parameters are also available if you're customizing network settings during the installation.

```bash
sudo ./jobdone-nexus-cli install \
  --hostname "<hostname>" \
  --ssh-private-key-name "<ssh_private_key_name>" \
  --ssh-public-key-name "<ssh_public_key_name>" \
  --zerotier-network-id "<zerotier_network_id>" \
  --zerotier-ip-prefix "<zerotier_ip_prefix>" \
  --trmm-mesh-agent "<trmm_mesh_agent>" \
  --trmm-api-url "<trmm_api_url>" \
  --trmm-client-id <trmm_client_id> \
  --trmm-site-id <trmm_site_id> \
  --trmm-auth-key "<trmm_auth_key>" \
  --static-ip "<static_ip>" \
  --gateway "<gateway>" \
  --netmask "<netmask>" \
  --dns "<dns>"
```

### Parameters Detail

- `--hostname`: The hostname for the system being installed.
- `--ssh-private-key-name`: The filename of the SSH private key to be used for secure connections.
- `--ssh-public-key-name`: The filename of the SSH public key corresponding to the private key.
- `--zerotier-network-id`: The network ID for the ZeroTier network.
- `--zerotier-ip-prefix`: The IP prefix for ZeroTier network configurations.
- `--trmm-mesh-agent`, `--trmm-api-url`, `--trmm-client-id`, `--trmm-site-id`, `--trmm-auth-key`: Parameters required for Tactical RMM integration.
- `--static-ip`, `--gateway`, `--netmask`, `--dns`: Optional parameters for static IP network configuration.

### Important Notes

- The script now checks and installs additional utilities such as `eget` for downloading executable binaries and `k9s` for Kubernetes cluster management.
- Kubernetes (`k3s`) installation is integrated into the script with specific configuration adjustments for ZeroTier networks.
- TacticalRMM agent installation steps are included, showcasing the script's readiness for IT management and monitoring integration.

After executing the installation command, follow the prompts to complete the setup. The script includes detailed logging and will suggest a reboot at the end of the installation to apply all configurations.
