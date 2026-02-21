# Server Setup Guide

Runs: **Prometheus · Grafana · Loki · Alertmanager · docker-socket-proxy**

> **Public IP:** `54.152.52.171`

---

## Prerequisites

### AWS Security Group — inbound rules
| Port | Source | Purpose |
|------|--------|---------|
| 22 | Your IP | SSH |
| 3000 | Your IP | Grafana |
| 9090 | Your IP | Prometheus |
| 9093 | Your IP | Alertmanager |
| 3100 | `34.230.91.8/32` | Loki (client only) |

---

## Step 1 — Install Docker

```bash
ssh -i ~/.ssh/your-key.pem ubuntu@54.152.52.171

sudo apt-get update && sudo apt-get upgrade -y
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
newgrp docker
sudo apt-get install -y docker-compose-plugin

# Verify
docker --version && docker compose version
```

---

## Step 2 — Transfer Files

Run from your **local machine**:

```bash
rsync -avz \
  -e "ssh -i ~/.ssh/your-key.pem" \
  --exclude '.env' \
  --exclude 'prometheus_data' \
  --exclude 'grafana_data' \
  --exclude 'loki_data' \
  --exclude 'alertmanager_data' \
  /home/jack/Documents/observability/server/ \
  ubuntu@54.152.52.171:~/observability/server/
```

---

## Step 3 — Configure `.env`

```bash
ssh -i ~/.ssh/your-key.pem ubuntu@54.152.52.171
cd ~/observability/server
cp .env-example .env
nano .env
```

Set these values:

```bash
COMPOSE_PROJECT_NAME=observability
ENVIRONMENT=production

# Grafana
GRAFANA_ADMIN_PASSWORD=<STRONG_PASSWORD>
GRAFANA_ROOT_URL=http://54.152.52.171:3000

# Prometheus
SCRAPE_INTERVAL=30s
SCRAPE_TIMEOUT=10s
PROMETHEUS_RETENTION=30d

# Loki
LOKI_STORAGE_TYPE=filesystem
LOKI_RETENTION_PERIOD=720h

# Alertmanager
ALERTMANAGER_EXTERNAL_URL=http://54.152.52.171:9093
ALERTMANAGER_LOG_LEVEL=warn

# SMTP — Gmail App Password
# Generate at: https://myaccount.google.com/apppasswords
SMTP_FROM=janak.shrestha.it@gmail.com
SMTP_AUTH_USERNAME=janak.shrestha.it@gmail.com
SMTP_AUTH_PASSWORD=<GMAIL_APP_PASSWORD>
DEFAULT_ALERT_EMAIL=janak123g@gmail.com

# AWS EC2 SD (optional — skip for now)
# AWS_EC2_SD_ACCESS_KEY_ID=
# AWS_EC2_SD_SECRET_ACCESS_KEY=
```

Save: `Ctrl+O` → Enter → `Ctrl+X`

---

## Step 4 — Set Prometheus File SD Targets

Point these at the client node (`34.230.91.8`):

```bash
cat > prometheus/targets/node_exporter.json << 'EOF'
[{"targets":["34.230.91.8:9100"],"labels":{"job":"node_exporter","host":"client1","environment":"production"}}]
EOF

cat > prometheus/targets/alloy.json << 'EOF'
[{"targets":["34.230.91.8:12345"],"labels":{"job":"alloy","host":"client1","environment":"production"}}]
EOF

cat > prometheus/targets/process_exporter.json << 'EOF'
[{"targets":["34.230.91.8:9256"],"labels":{"job":"process_exporter","host":"client1","environment":"production"}}]
EOF
```

To add more nodes later, just append to any of these files and run:
```bash
curl -XPOST http://localhost:9090/-/reload
```

---

## Step 5 — Start the Stack

```bash
docker compose up -d
```

---

## Step 6 — Verify

```bash
# All 5 services should show Up
docker compose ps

# Prometheus health check
curl -s http://localhost:9090/-/healthy

# Active scrape targets
curl -s http://localhost:9090/api/v1/targets | python3 -c "
import json, sys
d = json.load(sys.stdin)
for t in d['data']['activeTargets']:
    print(f\"[{t['health']:7}] {t['labels'].get('job','?'):25} -> {t['labels'].get('instance','?')}\")"

# Test alert email
curl -XPOST http://localhost:9093/api/v1/alerts \
  -H 'Content-Type: application/json' \
  -d '[{"labels":{"alertname":"TestAlert","severity":"critical"}}]'
```

Open Grafana: **http://54.152.52.171:3000** — login: `admin` / `<your password>`

---

## Common Commands

```bash
docker compose ps                               # Status
docker compose logs -f                          # All logs
docker compose logs -f prometheus               # Single service
docker compose restart prometheus               # Restart service
docker compose up -d                            # Apply config changes
curl -XPOST http://localhost:9090/-/reload      # Reload Prometheus (no restart)
docker compose pull && docker compose up -d     # Update images
```

## Re-sync After Local Config Changes

```bash
# From local machine
rsync -avz -e "ssh -i ~/.ssh/your-key.pem" \
  --exclude '.env' \
  /home/jack/Documents/observability/server/ \
  ubuntu@54.152.52.171:~/observability/server/

# Then on server
docker compose up -d
```
