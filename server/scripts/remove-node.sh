#!/usr/bin/env bash
# ============================================================
# remove-node.sh — Remove a monitored client node from Prometheus File SD
# ============================================================
# Usage:
#   ./scripts/remove-node.sh <HOSTNAME>
#
# Examples:
#   ./scripts/remove-node.sh web-01
#
# What it does:
#   Removes all entries (all jobs) for the given hostname
#   from prometheus/targets/clients.json.
#   Prometheus picks this up automatically within 30 seconds.
# ============================================================
set -euo pipefail

# ── Arguments ────────────────────────────────────────────────
HOST="${1:-}"
TARGETS_FILE="$(dirname "$0")/../prometheus/targets/clients.json"
PROMETHEUS_URL="http://localhost:9090/-/reload"

# ── Validation ───────────────────────────────────────────────
if [[ -z "$HOST" ]]; then
  echo "❌ Usage: $0 <HOSTNAME>"
  echo "   Example: $0 web-01"
  exit 1
fi

if ! command -v jq &> /dev/null; then
  echo "❌ jq is required but not installed. Run: sudo apt install jq"
  exit 1
fi

# Check host actually exists
COUNT=$(jq --arg host "$HOST" '[.[] | select(.labels.host == $host)] | length' "$TARGETS_FILE")
if [[ "$COUNT" -eq 0 ]]; then
  echo "❌ No entries found for host '${HOST}' in ${TARGETS_FILE}"
  echo "   List all hosts: jq '.[].labels.host' ${TARGETS_FILE} | sort -u"
  exit 1
fi

# ── Remove entries ───────────────────────────────────────────
echo "🗑️  Removing all ${COUNT} entries for host '${HOST}'..."

jq --arg host "$HOST" \
  '[.[] | select(.labels.host != $host)]' \
  "$TARGETS_FILE" > /tmp/clients.tmp && mv /tmp/clients.tmp "$TARGETS_FILE"

echo "✅ Removed ${HOST} from ${TARGETS_FILE}"

# ── Hot-reload Prometheus ────────────────────────────────────
echo "🔄 Hot-reloading Prometheus..."
if curl -sf -XPOST "$PROMETHEUS_URL" > /dev/null 2>&1; then
  echo "✅ Prometheus reloaded."
else
  echo "⚠️  Could not reach Prometheus at ${PROMETHEUS_URL}"
  echo "   File updated — Prometheus will auto-reload within 30s."
fi
