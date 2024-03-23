# jobdone-nexus-cli 🌐

## Installation 🛠️

This section guides you through the installation process of `jobdone-nexus-cli`. Begin by ensuring you have root access, as the installation requires elevated permissions.

### Prerequisites

Execute the following commands:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
```

Add the private key:

1. Type `vi ~/.ssh/id_ed25519` to create or edit the private key file in your `.ssh` directory.
1. Press `i` to switch to insert mode.
1. Paste your private key content into the editor.
1. Press `Esc` to exit insert mode.
1. Type `:wq` and press `Enter` to save the changes and exit vi.

Add the public key:

1. Type `vi ~/.ssh/id_ed25519.pub` to create or edit the public key file in your `.ssh` directory. Again, adjust the filename as necessary.
1. Press `i` to switch to insert mode.
1. Paste your public key content into the editor.
1. Press `Esc` to exit insert mode.
1. Type `:wq` and press `Enter` to save the changes and exit vi.

Execute the following commands:

```bash
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub
```

### Install Dependencies and `jobdone-nexus-cli`

Run the following commands to clean up your package lists, update your system, install necessary packages like `curl`, and download and install the `jobdone-nexus-cli`:

```bash
sudo apt clean && sudo apt autoclean && sudo apt update && sudo apt upgrade -y

sudo apt install curl -y

sudo curl -o /usr/local/bin/jobdone-nexus-cli https://raw.githubusercontent.com/jobdone-official/jobdone-nexus-cli/main/jobdone-nexus-cli && sudo chmod +x /usr/local/bin/jobdone-nexus-cli
```

## Usage 🔍

Note: The `trmm-auth-key` and other sensitive parameters may expire or require updating over time. Ensure you maintain these credentials securely and update them as necessary.

### Command Parameters

When executing the `jobdone-nexus-cli install` command, specify the following parameters to tailor the installation to your environment. Include network parameters if configuring network settings during installation:

```bash
jobdone-nexus-cli install \
  --hostname "<hostname>" \
  --argocd_repo_url "<argocda-repo-url>" \
  --argocd-app-path "<argocd-app-path>" \
  --hcp-client-id "<hcp-client-id>" \
  --hcp-client-id-secret "<hcp-client-id-secret>" \
  --hcp-org-id "<hcp-org-id>" \
  --hcp-project-id "<hcp-project-id>" \
  --trmm-mesh-agent "<trmm-mesh-agent>" \
  --trmm-api-url "<trmm-api-url>" \
  --trmm-client-id <trmm-client-id> \
  --trmm-site-id <trmm-site-id> \
  --trmm-auth-key "<trmm-auth-key>" \
  --zerotier-id "<zerotier-id>" \
  --static-ip "<static_ip>" \
  --gateway "<gateway>" \
  --netmask "<netmask>" \
  --dns "<dns>"
```

#### Example Usage

- **Basic Installation Example** (minimal setup without network configuration):

  ```bash
  jobdone-nexus-cli install \
    --hostname "nexus-server-1" \
    --argocd-git-repo-url "https://git.example.com/repo.git" \
    --argocd-app-path "path/to/app" \
    --hcp-client-id "example-client-id" \
    --hcp-client-id-secret "example-client-secret" \
    --hcp-org-id "example-org-id" \
    --hcp-project-id "example-project-id" \
    --trmm-mesh-agent "meshagent.example.com" \
    --trmm-api-url "https://api.trmm.example.com" \
    --trmm-client-id 1 \
    --trmm-site-id 1 \
    --trmm-auth-key "authkey789" \
    --zerotier-id "e5cd7a82840b9b7e"
  ```

- **Full Installation Example** (with network configuration):

  ```bash
  jobdone-nexus-cli install \
    --hostname "nexus-server-1" \
    --argocd-git-repo-url "https://git.example.com/repo.git" \
    --argocd-app-path "path/to/app" \
    --hcp-client-id "example-client-id" \
    --hcp-client-id-secret "example-client-secret" \
    --hcp-org-id "example-org-id" \
    --hcp-project-id "example-project-id" \
    --trmm-mesh-agent "meshagent.example.com" \
    --trmm-api-url "https://api.trmm.example.com" \
    --trmm-client-id 1 \
    --trmm-site-id 1 \
    --trmm-auth-key "authkey789" \
    --zerotier-id "e5cd7a82840b9b7e" \
    --static_ip "192.168.1.100" \
    --gateway "192.168.1.1" \
    --netmask "255.255.255.0" \
    --dns "8.8.8.8"
  ```

These examples demonstrate the flexibility and customization available with the `jobdone-nexus-cli` installation process, catering to various infrastructure needs and configurations.
