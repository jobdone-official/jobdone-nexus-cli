# jobdone-nexus-cli

## Installation

For the very first time, execute the script with the root user, to install all prerequisites.

```bash
apt install curl
curl -o /usr/local/bin/jobdone-nexus-cli https://raw.githubusercontent.com/jobdone-official/jobdone-nexus-cli/main/jobdone-nexus-cli
chmod +x /usr/local/bin/jobdone-nexus-cli
```

## Usage

Please note that the trmm-auth-key key has an expiry date and needs to be fetched again.

Without network (optional):

```bash
jobdone-nexus-cli install \
  --user <user>
  --zerotier-id <zerotier-id> \
  --trmm-mesh-agent "<trmm-mesh-agent>" \
  --trmm-api-url "<trmm-api-url>" \
  --trmm-client-id <trmm-client-id> \
  --trmm-site-id <trmm-site-id> \
  --trmm-auth-key <"trmm-auth-key">
```

With network:

```bash
jobdone-nexus-cli install \
  --user <user>
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
