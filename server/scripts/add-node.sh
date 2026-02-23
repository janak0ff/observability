#!/usr/bin/env bash
# ============================================================
# add-node.sh — Add a monitored client node to Prometheus File SD
# ============================================================
# Usage:
#   ./scripts/add-node.sh <IP> <HOSTNAME> [ENVIRONMENT] [--nginx] [--jenkins]
#
# Examples:
#   ./scripts/add-node.sh 10.0.1.50 web-01
#   ./scripts/add-node.sh 10.0.1.50 web-01 production
#   ./scripts/add-node.sh 10.0.1.50 web-01 production --nginx
#   ./scripts/add-node.sh 54.152.52.171 aws-node-01 production --nginx --jenkins
#
# What it does:
#   Appends entries for the given IP into prometheus/targets/clients.json.
#   By default, it adds node_exporter (9100), alloy (12345), and
#   process_exporter (9256).
#   Use --nginx to add nginx-exporter (9113) and nginx-vts-exporter (9338).
#   Use --jenkins to add jenkins-exporter (8080).
#   Prometheus picks this up automatically within 30 seconds via
#   file_sd hot-reload — no restart needed.
#
# Requirements:
#   - jq must be installed (sudo apt install jq)
#   - Run from the server/ directory OR using the full path
# ============================================================
set -euo pipefail

# ── Arguments ────────────────────────────────────────────────
IP="${1:-}"
HOST="${2:-}"
ENV="production" # Default environment
NGINX_FLAG=false
JENKINS_FLAG=false

# Shift IP and HOST
shift 2

# Parse remaining arguments for flags and environment
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --nginx)
      NGINX_FLAG=true
      ;;
    --jenkins)
      JENKINS_FLAG=true
      ;;
    *)
      # Assume it's the environment if not a flag
      if [[ -z "$ENV" || "$ENV" == "production" ]]; then # Only set if not already set by a previous non-flag arg
        ENV="$1"
      else
        echo "❌ Unknown argument or too many environment arguments: $1"
        echo "Usage: $0 <IP> <HOSTNAME> [--nginx] [--jenkins] [ENVIRONMENT]"
        exit 1
      fi
      ;;
  esac
  shift
done

TARGETS_FILE="$(dirname "$0")/../prometheus/targets/clients.json"
PROMETHEUS_URL="http://localhost:9090/-/reload"

# ── Validation ───────────────────────────────────────────────
if [[ -z "$IP" || -z "$HOST" ]]; then
  echo "❌ Usage: $0 <IP> <HOSTNAME> [--nginx] [--jenkins] [ENVIRONMENT]"
  echo "   Example: $0 10.0.1.50 web-01 production"
  exit 1
fi

if ! command -v jq &> /dev/null; then
  echo "❌ jq is required but not installed. Run: sudo apt install jq"
  exit 1
fi

# Check for duplicate IP
if jq -e --arg ip "$IP" '.[] | .targets[] | select(startswith($ip))' "$TARGETS_FILE" &>/dev/null; then
  echo "⚠️  Warning: IP ${IP} already exists in ${TARGETS_FILE}"
  echo "   Remove it first with: ./scripts/remove-node.sh ${HOST}"
  exit 1
fi

# ── Construct targets ────────────────────────────────────────
TARGET_PORTS=()
TARGET_PORTS+=("9100")  # node_exporter
TARGET_PORTS+=("12345") # alloy
TARGET_PORTS+=("9256")  # process_exporter
TARGET_PORTS+=("9338")  # cadvisor

if [[ "$NGINX_FLAG" == "true" ]]; then
  TARGET_PORTS+=("9113") # nginx_exporter
fi

if [[ "$JENKINS_FLAG" == "true" ]]; then
  TARGET_PORTS+=("8080") # jenkins prometheus endpoint
fi

# Format ports for jq
JQ_TARGETS=""
for port in "${TARGET_PORTS[@]}"; do
  if [[ -n "$JQ_TARGETS" ]]; then
    JQ_TARGETS+=","
  fi
  JQ_TARGETS+="(\$ip + \":${port}\")"
done

echo "➕ Adding ${HOST} (${IP}) to ${TARGETS_FILE} with ports: ${TARGET_PORTS[*]}..."

jq --arg ip    "$IP"   \
   --arg host  "$HOST" \
   --arg env   "$ENV"  \
   --argjson targets_array "[${JQ_TARGETS}]" \
'. += [
  {
    "targets": $targets_array,
    "labels":  {"host": $host, "environment": $env}
  }
]' "$TARGETS_FILE" > /tmp/clients.tmp && mv /tmp/clients.tmp "$TARGETS_FILE"

echo "✅ Added ${HOST} (${IP}) — ports ${TARGET_PORTS[*]}"

# ── Hot-reload Prometheus ────────────────────────────────────
echo "🔄 Hot-reloading Prometheus (no restart needed)..."
if curl -sf -XPOST "$PROMETHEUS_URL" > /dev/null 2>&1; then
  echo "✅ Prometheus reloaded. Check targets: http://localhost:9090/targets"
else
  echo "⚠️  Could not reach Prometheus at ${PROMETHEUS_URL}"
  echo "   File updated successfully — Prometheus will auto-reload within 30s."
fi
