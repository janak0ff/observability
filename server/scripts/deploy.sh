#!/usr/bin/env bash
# ==========================================================
# deploy.sh — Production deployment helper
# Usage: ./scripts/deploy.sh [up|down|restart|status|logs]
# ==========================================================
set -euo pipefail

COMPOSE_FILE="docker-compose.prod.yml"
ENV_FILE=".env"

# Validate env file exists
if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: .env file not found!"
  echo "Copy .env.prod to .env and fill in all values first:"
  echo "  cp .env.prod .env && nano .env"
  exit 1
fi

# Validate required secrets are set
required_vars=("DOMAIN" "GRAFANA_ADMIN_PASSWORD" "SMTP_AUTH_PASSWORD" "DEFAULT_ALERT_EMAIL")
for var in "${required_vars[@]}"; do
  val=$(grep "^${var}=" "$ENV_FILE" | cut -d= -f2- || true)
  if [ -z "$val" ] || [[ "$val" == *"CHANGE_ME"* ]] || [[ "$val" == *"yourcompany"* ]]; then
    echo "ERROR: ${var} is not set or still has a placeholder value in .env"
    exit 1
  fi
done

ACTION="${1:-up}"

case "$ACTION" in
  up)
    echo ">> Pulling latest pinned images..."
    docker compose -f "$COMPOSE_FILE" pull

    echo ">> Starting production stack..."
    docker compose -f "$COMPOSE_FILE" up -d

    echo ">> Stack started! Status:"
    docker compose -f "$COMPOSE_FILE" ps
    ;;
  down)
    echo ">> Stopping production stack..."
    docker compose -f "$COMPOSE_FILE" down
    ;;
  restart)
    echo ">> Restarting production stack..."
    docker compose -f "$COMPOSE_FILE" restart
    ;;
  status)
    docker compose -f "$COMPOSE_FILE" ps
    ;;
  logs)
    docker compose -f "$COMPOSE_FILE" logs --tail=100 -f
    ;;
  validate)
    echo ">> Validating configs..."
    docker compose -f "$COMPOSE_FILE" config --quiet && echo "docker-compose.prod.yml: OK"
    docker compose -f "$COMPOSE_FILE" exec prometheus promtool check config /etc/prometheus/prometheus.yml \
      && echo "prometheus.yml: OK"
    docker compose -f "$COMPOSE_FILE" exec alertmanager amtool check-config /etc/alertmanager/alertmanager.yml \
      && echo "alertmanager.yml: OK"
    ;;
  *)
    echo "Usage: $0 [up|down|restart|status|logs|validate]"
    exit 1
    ;;
esac
