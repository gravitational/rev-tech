#!/bin/bash
set -euxo pipefail

hostnamectl set-hostname "${name}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y

# Xfce desktop + Xvfb (the virtual framebuffer Teleport renders sessions into).
# xfce4 ships /usr/share/xsessions/xfce.desktop, which is how Teleport discovers
# the session. No display manager: Teleport launches sessions itself.
apt-get install -y xfce4 xfce4-terminal xvfb dbus-x11

# Headless box — never try to bring up a graphical login on boot.
systemctl set-default multi-user.target

# The desktop service does not create host users; every login offered by the
# access role must already exist (session setup does a user.Lookup).
for u in ${desktop_logins}; do
  id "$u" &>/dev/null || useradd -m -s /bin/bash "$u"
done

# install.sh fetched from the proxy installs the cluster-advertised version via teleport-update
curl "https://${proxy_address}/scripts/install.sh" | bash

teleport version || true
which Xvfb

echo "${token}" > /tmp/token

cat <<EOF >/etc/teleport.yaml
version: v3
teleport:
  data_dir: /var/lib/teleport
  auth_token: /tmp/token
  proxy_server: ${proxy_address}:443
  log:
    output: stderr
    severity: INFO
    format:
      output: json
linux_desktop_service:
  enabled: true
  labels:
    env: ${env}
    team: ${team}
%{ if xsessions_included != "" || xsessions_excluded != "" ~}
  xsessions:
%{ if xsessions_included != "" ~}
    included: "${xsessions_included}"
%{ endif ~}
%{ if xsessions_excluded != "" ~}
    excluded: "${xsessions_excluded}"
%{ endif ~}
%{ endif ~}
ssh_service:
  enabled: true
  labels:
    env: ${env}
    team: ${team}
  commands:
    - name: hostname
      command: [hostname]
      period: 1m0s
auth_service:
  enabled: false
proxy_service:
  enabled: false
EOF

systemctl enable teleport
systemctl restart teleport

echo "[INFO] Teleport linux_desktop_service setup complete."
