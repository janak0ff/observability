#!/usr/bin/env bash
# ============================================================
# add-node.sh — Add a monitored client node to Prometheus File SD
# ============================================================
# Usage:
#   ./scripts/add-node.sh <IP> <HOSTNAME> [ENVIRONMENT]
#
# Examples:
#   ./scripts/add-node.sh 10.0.1.50 web-01
#   ./scripts/add-node.sh 10.0.1.50 web-01 production
#
# What it does:
#   Appends 3 entries (node_exporter, alloy, process_exporter) for
#   the given IP into prometheus/targets/clients.json.
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
ENV="${3:-production}"

TARGETS_FILE="$(dirname "$0")/../prometheus/targets/clients.json"
PROMETHEUS_URL="http://localhost:9090/-/reload"

# ── Validation ───────────────────────────────────────────────
if [[ -z "$IP" || -z "$HOST" ]]; then
  echo "❌ Usage: $0 <IP> <HOSTNAME> [ENVIRONMENT]"
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

# ── Add entries ──────────────────────────────────────────────
echo "➕ Adding ${HOST} (${IP}) to ${TARGETS_FILE}..."

jq --arg ip    "$IP"   \
   --arg host  "$HOST" \
   --arg env   "$ENV"  \
'. += [
  {
    "targets": [($ip + ":9100"), ($ip + ":12345"), ($ip + ":9256"), ($ip + ":9338"), ($ip + ":9113"), ($ip + ":9506")],
    "labels":  {"host": $host, "environment": $env}
  }
]' "$TARGETS_FILE" > /tmp/clients.tmp && mv /tmp/clients.tmp "$TARGETS_FILE"

echo "✅ Added ${HOST} (${IP}) — ports 9100, 12345, 9256, 9338, 9113, 9506"

# ── Hot-reload Prometheus ────────────────────────────────────
echo "🔄 Hot-reloading Prometheus (no restart needed)..."
if curl -sf -XPOST "$PROMETHEUS_URL" > /dev/null 2>&1; then
  echo "✅ Prometheus reloaded. Check targets: http://localhost:9090/targets"
else
  echo "⚠️  Could not reach Prometheus at ${PROMETHEUS_URL}"
  echo "   File updated successfully — Prometheus will auto-reload within 30s."
fi
