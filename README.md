# jobdone-nexus-cli 🌐

## Installation 🛠️

This section guides you through the installation process of `jobdone-nexus-cli`. Begin by ensuring you have root access, as the installation requires elevated permissions.

### Become the Root User

To switch to the root user, execute the following command in your terminal:

```bash
su -
```

### Install Dependencies and `jobdone-nexus-cli`

Run the following commands to clean up your package lists, update your system, install `curl`, and finally, download and install the `jobdone-nexus-cli`:

```bash
apt clean && apt autoclean && apt update && apt upgrade -y

apt install curl -y

curl -o /usr/local/bin/jobdone-nexus-cli https://raw.githubusercontent.com/jobdone-official/jobdone-nexus-cli/main/jobdone-nexus-cli && chmod +x /usr/local/bin/jobdone-nexus-cli
```

## Usage 🔍

Please be aware that the `trmm-auth-key` expires and will need to be renewed periodically.

### Command Parameters

When executing the `jobdone-nexus-cli install` command, you'll need to specify several parameters to tailor the installation to your environment:

- **Without network (optional):**

  ```bash
  jobdone-nexus-cli install \
    --user "<user>" \
    --hostname "<hostname>" \
    --zerotier-id <zerotier-id> \
    --trmm-mesh-agent "<trmm-mesh-agent>" \
    --trmm-api-url "<trmm-api-url>" \
    --trmm-client-id <trmm-client-id> \
    --trmm-site-id <trmm-site-id> \
    --trmm-auth-key <"trmm-auth-key">
  ```

- **With network:**

  ```bash
  jobdone-nexus-cli install \
    --user "<user>" \
    --hostname "<hostname>" \
    --zerotier-id <zerotier-id> \
    --trmm-mesh-agent "<trmm-mesh-agent>" \
    --trmm-api-url "<trmm-api-url>" \
    --trmm-client-id <trmm-client-id> \
    --trmm-site-id <trmm-site-id> \
    --trmm-auth-key "<trmm-auth-key>" \
    --static_ip <static_ip> \
    --gateway <gateway> \
    --netmask <netmask> \
    --dns <dns>
  ```
