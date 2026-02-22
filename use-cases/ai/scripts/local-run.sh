#!/usr/bin/env bash
# Start all services locally — no Docker, no K8s.
# Can be run from any directory: ./scripts/local-run.sh or scripts/local-run.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# Load .env if present
if [[ -f .env ]]; then
  set -a; source .env; set +a
fi

PIDS=()
LOG_DIR="${LOG_DIR:-/tmp/a2a-demo-logs}"
mkdir -p "$LOG_DIR"

# ---------------------------------------------------------------------------
# Cleanup — kill all background services on exit
# ---------------------------------------------------------------------------
cleanup() {
  echo ""
  echo "Shutting down..."
  for pid in "${PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  wait 2>/dev/null || true
  echo "Done."
}
trap cleanup SIGINT SIGTERM EXIT

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
check_env() {
  if [[ "${LLM_PROVIDER:-anthropic}" == "anthropic" ]] && [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
    echo "ERROR: ANTHROPIC_API_KEY is not set."
    echo "       Set it in your environment or run: LLM_PROVIDER=ollama ./scripts/local-run.sh"
    exit 1
  fi
}

start_service() {
  local name=$1
  local module=$2
  local log="$LOG_DIR/${name}.log"
  echo "  Starting $name  →  $log"
  uv run python -m "$module" > "$log" 2>&1 &
  PIDS+=($!)
}

wait_healthy() {
  local name=$1
  local url=$2
  local attempts=0
  local max=30
  printf "  Waiting for %-20s" "$name..."
  while [[ $attempts -lt $max ]]; do
    if curl -sf "${url}/.well-known/agent.json" > /dev/null 2>&1; then
      echo " ready"
      return 0
    fi
    sleep 1
    ((attempts++))
  done
  echo " TIMEOUT"
  echo "ERROR: $name did not become healthy at $url"
  echo "       Check logs: $LOG_DIR/${name}.log"
  exit 1
}

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
check_env

echo ""
echo "=== A2A Demo — local run ==="
echo "Logs: $LOG_DIR"
echo ""

# ---------------------------------------------------------------------------
# Agents — start whichever modules exist
# ---------------------------------------------------------------------------
echo "Starting agents..."

[[ -f agents/general_agent/main.py ]] && start_service "general-agent" "agents.general_agent.main"

echo ""
echo "Waiting for agents to be healthy..."

[[ -f agents/general_agent/main.py ]] && wait_healthy "general-agent" "http://localhost:9003"

# ---------------------------------------------------------------------------
# Orchestrator
# ---------------------------------------------------------------------------
#echo ""
#echo "Starting orchestrator..."
#start_service "orchestrator" "orchestrator.main"
#wait_healthy "orchestrator" "http://localhost:9000"

# ---------------------------------------------------------------------------
# Ready
# ---------------------------------------------------------------------------
echo ""
echo "=== All services running ==="
echo ""
#echo "  Orchestrator  →  http://localhost:9000"
[[ -f agents/general_agent/main.py ]] && echo "  General Agent →  http://localhost:9003"
echo ""
echo "Press Ctrl+C to stop all services."
echo ""

wait
