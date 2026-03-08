#!/bin/bash
set -euxo pipefail

hostnamectl set-hostname "${name}"

dnf update -y
dnf install -y python3-pip git jq

# Clone the demo panel app
git clone "${app_repo}" /opt/demo-panel
pip3 install -r /opt/demo-panel/requirements.txt

# Systemd service — gunicorn on port 5000.
# DEMO_ENV and DEMO_TEAM are read by the Flask app via os.environ.
cat > /etc/systemd/system/demo-panel.service <<EOF
[Unit]
Description=Teleport Demo Panel (Flask)
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/demo-panel
Environment=DEMO_ENV=${env}
Environment=DEMO_TEAM=${team}
ExecStart=/usr/local/bin/gunicorn -w 2 -b 0.0.0.0:5000 app:app
Restart=on-failure
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl enable demo-panel
systemctl start demo-panel

# Install Teleport
curl "https://${proxy_address}/scripts/install.sh" | bash -s "${teleport_version}" enterprise

cat > /etc/teleport.yaml <<EOF
version: v3
teleport:
  data_dir: "/var/lib/teleport"
  auth_token: "${token}"
  proxy_server: ${proxy_address}:443
  log:
    output: stderr
    severity: INFO
    format:
      output: text
app_service:
  enabled: "yes"
  resources:
    - labels:
        "teleport.dev/app": "demo-panel"
        "env": "${env}"
        "team": "${team}"
ssh_service:
  enabled: "yes"
  labels:
    "env": "${env}"
    "team": "${team}"
auth_service:
  enabled: "no"
proxy_service:
  enabled: "no"
EOF

systemctl enable teleport
systemctl restart teleport
