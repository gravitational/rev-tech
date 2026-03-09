#!/bin/bash
set -euxo pipefail

# Fetch Teleport's user CA from the proxy (unauthenticated endpoint).
# sshd will trust certificates signed by this CA — no Teleport agent needed.
curl -fsSL "https://${proxy_address}/webapi/auth/export?type=user" \
  -o /etc/ssh/teleport_user_ca.pub

# Configure sshd to trust the Teleport user CA
cat > /etc/ssh/sshd_config.d/teleport-ca.conf <<EOF
TrustedUserCAKeys /etc/ssh/teleport_user_ca.pub
EOF

# Create the OS login that Teleport roles will use
# The login name is set by var.ssh_login (default: teleport-user)
useradd -m -s /bin/bash "${login}" || true
echo "${login} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${login}

systemctl restart sshd
