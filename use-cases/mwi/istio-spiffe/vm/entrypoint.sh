#!/bin/bash
set -e

mkdir -p /run/teleport

# Substitute env vars into config templates so no secrets are baked into the image
envsubst < /etc/tbot/tbot.yaml.tmpl > /etc/tbot/tbot.yaml
envsubst < /etc/envoy/envoy.yaml.tmpl > /etc/envoy/envoy.yaml

echo "[*] Starting tbot (proxy: ${TELEPORT_PROXY})..."
tbot start -c /etc/tbot/tbot.yaml &
TBOT_PID=$!

echo "[*] Waiting for Workload API socket at /run/teleport/workload.sock..."
for i in $(seq 1 30); do
  if [ -S /run/teleport/workload.sock ]; then
    echo "[*] Socket ready (${i}s)."
    break
  fi
  echo "    waiting... (${i}/30)"
  sleep 1
done

if [ ! -S /run/teleport/workload.sock ]; then
  echo "[!] Socket never appeared — check tbot output above for errors"
  wait $TBOT_PID
  exit 1
fi

echo "[*] Starting Envoy (forward proxy on :8080, admin on :9901)..."
envoy -c /etc/envoy/envoy.yaml --log-level warn

wait $TBOT_PID