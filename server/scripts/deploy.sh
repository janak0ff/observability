#!/usr/bin/env bash
# ==========================================================
# deploy.sh — Observability Stack Helper
#
# Dev:  ./scripts/deploy.sh up
# Prod: ./scripts/deploy.sh up --profile nginx
#
# Usage: ./scripts/deploy.sh [up|down|restart|status|logs|validate] [extra docker compose flags]
# ==========================================================
set -euo pipefail

ENV_FILE=".env"

# Validate .env exists
if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: .env file not found!"
  echo "Copy the template and fill in your values:"
  echo "  cp .env-example .env && nano .env"
  exit 1
fi

# Validate required variables are set and not placeholders
required_vars=("SMTP_AUTH_PASSWORD" "DEFAULT_ALERT_EMAIL" "GRAFANA_ADMIN_PASSWORD")
for var in "${required_vars[@]}"; do
  val=$(grep "^${var}=" "$ENV_FILE" | cut -d= -f2- || true)
  if [ -z "$val" ] || [[ "$val" == *"xxxx"* ]] || [[ "$val" == *"yourcompany"* ]]; then
    echo "WARNING: ${var} appears to be unset or still a placeholder in .env"
  fi
done

ACTION="${1:-up}"
shift || true  # allow extra flags to be passed through

case "$ACTION" in
  up)
    echo ">> Pulling images..."
    docker compose pull
    echo ">> Starting stack ($@)..."
    docker compose up -d "$@"
    echo ""
    docker compose ps
    ;;
  down)
    docker compose down "$@"
    ;;
  restart)
    docker compose restart "$@"
    ;;
  status)
    docker compose ps
    ;;
  logs)
    docker compose logs --tail=100 -f "$@"
    ;;
  validate)
    echo ">> Validating docker-compose.yml..."
    docker compose config --quiet && echo "docker-compose.yml: OK"
    echo ">> Validating prometheus.yml..."
    docker compose exec prometheus promtool check config /etc/prometheus/prometheus.yml \
      && echo "prometheus.yml: OK"
    echo ">> Validating alertmanager.yml..."
    docker compose exec alertmanager amtool check-config /etc/alertmanager/alertmanager.yml \
      && echo "alertmanager.yml: OK"
    ;;
  *)
    echo "Usage: $0 [up|down|restart|status|logs|validate] [extra flags]"
    echo ""
    echo "Examples:"
    echo "  ./scripts/deploy.sh up                   # Start (dev)"
    echo "  ./scripts/deploy.sh up --profile nginx   # Start with Nginx (production)"
    echo "  ./scripts/deploy.sh logs alertmanager    # Tail alertmanager logs"
    exit 1
    ;;
esac
