# Observability Stack — Complete Guide

A self-hosted observability stack running **Prometheus · Grafana · Loki · Alertmanager · Alloy**.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  SERVER (54.152.52.171)                                         │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────┐    │
│  │  Prometheus  │  │   Grafana    │  │   Alertmanager     │    │
│  │  :9090       │  │   :3000      │  │   :9093            │    │
│  └──────┬───────┘  └──────────────┘  └────────────────────┘    │
│         │ scrapes        ▲ queries              ▲ alerts        │
│  ┌──────▼───────┐        │                      │               │
│  │  Loki :3100  ├────────┘                      │               │
│  └──────────────┘                               │               │
│  ┌─────────────────────┐                        │               │
│  │  docker-socket-proxy│ (Docker SD)            │               │
│  └─────────────────────┘                        │               │
└─────────────────────────────────────────────────┼───────────────┘
                 ▲ scrapes metrics                 │ alert rules
┌────────────────┼──────────────────────────────── ┼───────────────┐
│  CLIENT (34.230.91.8)                            │               │
│                                                  │               │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────┴────────┐     │
│  │ node-exporter│  │    Alloy     │  │  process-exporter  │     │
│  │  :9100       │  │  :12345      │  │  :9256             │     │
│  └──────────────┘  └──────┬───────┘  └────────────────────┘     │
│                            │ pushes logs to Loki :3100           │
└────────────────────────────┼──────────────────────────────────────┘
                             ▼
                  Loki on Server :3100
```

---

## Repository Layout

```
observability/
├── GUIDE.md                   ← This file
├── server/
│   ├── docker-compose.yml     # Single compose file for dev + prod
│   ├── .env-example           # Template — copy to .env and fill values
│   ├── prometheus/
│   │   ├── prometheus.yml     # Docker SD + File SD + EC2 SD
│   │   ├── targets/           # File SD JSON files (hot-reload)
│   │   │   ├── node_exporter.json
│   │   │   ├── alloy.json
│   │   │   └── process_exporter.json
│   │   └── rules/
│   │       └── alert-rules.yml
│   ├── grafana/
│   │   ├── datasources/       # Auto-provisioned datasources
│   │   └── plugins/
│   ├── loki/
│   │   ├── loki-config.yaml   # filesystem or S3 via LOKI_STORAGE_TYPE
│   │   └── rules/
│   ├── alertmanager/
│   │   ├── alertmanager.yml   # Credentials from env vars
│   │   └── templates/         # HTML email templates
│   ├── nginx/
│   │   └── nginx.conf         # HTTPS reverse proxy (opt-in, --profile nginx)
│   └── scripts/
│       └── deploy.sh
│
└── client/
    ├── docker-compose.yml
    ├── .env                   # LOKI_URL + PROMETHEUS_URL → server
    └── configs/
        ├── config.alloy       # Log collection + Docker discovery
        └── process-exporter/
            └── process.yml
```

---

## Running the Stack

### Development (local machine)
```bash
cd server
docker compose up -d
```

### Production (with Nginx HTTPS)
```bash
docker compose --profile nginx up -d
```

### Common Commands
```bash
docker compose ps                              # Status
docker compose logs -f                         # All logs
docker compose logs -f prometheus              # Single service logs
docker compose restart prometheus              # Restart one service
curl -XPOST http://localhost:9090/-/reload     # Reload Prometheus config (no restart)
docker compose config --quiet && echo "OK"     # Validate config
docker compose pull && docker compose up -d    # Update images
```

---

## Environment Variables Reference

```bash
cp server/.env-example server/.env
nano server/.env
```

| Variable | Dev Default | Production |
|---|---|---|
| `ENVIRONMENT` | `development` | `production` |
| `SCRAPE_INTERVAL` | `15s` | `30s` |
| `GRAFANA_ADMIN_PASSWORD` | `admin` | Strong password |
| `GRAFANA_ROOT_URL` | `http://localhost:3000` | `http://54.152.52.171:3000` |
| `GRAFANA_COOKIE_SECURE` | `false` | `true` (if HTTPS) |
| `LOKI_STORAGE_TYPE` | `filesystem` | `filesystem` or `s3` |
| `ALERTMANAGER_EXTERNAL_URL` | `http://localhost:9093` | `http://54.152.52.171:9093` |
| `SMTP_AUTH_PASSWORD` | — | Gmail App Password |

### Loki S3 Storage (optional)
```bash
LOKI_STORAGE_TYPE=s3
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
LOKI_BUCKET_NAME=my-loki-logs
```

---

## Service Discovery

### 1. Docker SD — internal containers
Add these labels to any container to have it auto-scraped:
```yaml
labels:
  prometheus.io/scrape: "true"
  prometheus.io/port: "9090"      # optional
  prometheus.io/path: "/metrics"  # optional
```
Prometheus reads Docker via `tecnativa/docker-socket-proxy` (read-only, secure).

### 2. File SD — external nodes
Edit files in `prometheus/targets/`. Prometheus hot-reloads in 30s. No restart needed.
```json
[
  {"targets": ["10.0.1.10:9100"], "labels": {"job": "node_exporter", "host": "web-01", "environment": "production"}},
  {"targets": ["10.0.1.11:9100"], "labels": {"job": "node_exporter", "host": "web-02", "environment": "production"}}
]
```
Reload: `curl -XPOST http://localhost:9090/-/reload`

### 3. EC2 SD — auto-discovers AWS EC2 instances
Tag EC2 instances in the AWS Console:

| Tag | Value | Notes |
|-----|-------|-------|
| `Scrape` | `true` | Required — opts instance in |
| `Name` | `web-01` | Becomes `instance` label |
| `Environment` | `production` | Becomes `environment` label |
| `Job` | `node_exporter` | Becomes `job` label |
| `ScrapePort` | `9100` | Override default port |

Set in `.env` (min IAM permission: `ec2:DescribeInstances`):
```bash
AWS_EC2_SD_ACCESS_KEY_ID=...
AWS_EC2_SD_SECRET_ACCESS_KEY=...
```

---

## Label Schema

All logs and metrics share these consistent labels:

| Label | Value | Where Set |
|---|---|---|
| `host` | Machine hostname | `env("HOSTNAME")` |
| `environment` | `development` / `production` | `env("ENVIRONMENT")` |
| `collector` | `alloy` | Static |
| `source` | `file` or `docker` | Per pipeline |
| `job` | Service group | Container name / tag |
| `app` | Specific app | Container name |

**Docker logs also:** `container`, `stream` (stdout/stderr), `image`, `level`

**System file logs also:** `log_type` (boot / packages / display / error)

**EC2 metrics also:** `region`, `availability_zone`, `instance_type`, `ec2_instance_id`

---

## Alert Configuration

```bash
SMTP_FROM=sender@gmail.com
SMTP_AUTH_USERNAME=sender@gmail.com
SMTP_AUTH_PASSWORD=xxxx_xxxx_xxxx_xxxx   # https://myaccount.google.com/apppasswords
DEFAULT_ALERT_EMAIL=oncall@yourcompany.com
```

Test:
```bash
curl -XPOST http://localhost:9093/api/v1/alerts \
  -H 'Content-Type: application/json' \
  -d '[{"labels":{"alertname":"TestAlert","severity":"critical"}}]'
```

---

---

# AWS EC2 Deployment — Step by Step

## Instances

| Role | Public IP | Services |
|------|-----------|----------|
| **Server** | `54.152.52.171` | Prometheus, Grafana, Loki, Alertmanager |
| **Client** | `34.230.91.8` | Node Exporter, Alloy, Process Exporter |

> [!IMPORTANT]
> Replace `~/.ssh/your-key.pem` with the actual path to your `.pem` key file throughout this guide.

---

## STEP 1 — Configure AWS Security Groups

Do this in the **AWS Console → EC2 → Security Groups** before anything else.

### Server Security Group
| Port | Protocol | Source | Purpose |
|------|----------|--------|---------|
| 22 | TCP | Your IP | SSH |
| 3000 | TCP | Your IP | Grafana UI |
| 9090 | TCP | Your IP | Prometheus UI |
| 9093 | TCP | Your IP | Alertmanager UI |
| 3100 | TCP | `34.230.91.8/32` | Loki — **client only, never public** |

### Client Security Group
| Port | Protocol | Source | Purpose |
|------|----------|--------|---------|
| 22 | TCP | Your IP | SSH |
| 9100 | TCP | `54.152.52.171/32` | Node Exporter |
| 12345 | TCP | `54.152.52.171/32` | Alloy metrics |
| 9256 | TCP | `54.152.52.171/32` | Process Exporter |

---

## STEP 2 — Install Docker on the SERVER

### 2a. SSH into the server
```bash
ssh -i ~/.ssh/your-key.pem ubuntu@54.152.52.171
```

### 2b. Install Docker
```bash
sudo apt-get update && sudo apt-get upgrade -y
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
newgrp docker
sudo apt-get install -y docker-compose-plugin
```

### 2c. Verify
```bash
docker --version
docker compose version
```

### 2d. Exit the server
```bash
exit
```

---

## STEP 3 — Install Docker on the CLIENT

### 3a. SSH into the client
```bash
ssh -i ~/.ssh/your-key.pem ubuntu@34.230.91.8
```

### 3b. Install Docker
```bash
sudo apt-get update && sudo apt-get upgrade -y
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
newgrp docker
sudo apt-get install -y docker-compose-plugin
```

### 3c. Verify
```bash
docker --version
docker compose version
```

### 3d. Exit the client
```bash
exit
```

---

## STEP 4 — Deploy the SERVER Environment

### 4a. Transfer server files (from your local machine)

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

> [!NOTE]
> `.env` is excluded on purpose — you will create a **fresh production `.env`** directly on the server.

### 4b. SSH into the server
```bash
ssh -i ~/.ssh/your-key.pem ubuntu@54.152.52.171
cd ~/observability/server
```

### 4c. Create the production `.env`
```bash
cp .env-example .env
nano .env
```

Fill in **all** the values below (replace every `<...>` placeholder):

```bash
# ── Core ──────────────────────────────────────────────────────
COMPOSE_PROJECT_NAME=observability
ENVIRONMENT=production

# ── Prometheus ────────────────────────────────────────────────
PROMETHEUS_PORT=9090
PROMETHEUS_RETENTION=30d
PROMETHEUS_RETENTION_SIZE=10GB
SCRAPE_INTERVAL=30s
SCRAPE_TIMEOUT=10s

# ── Grafana ───────────────────────────────────────────────────
GRAFANA_PORT=3000
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=<STRONG_PASSWORD>
GRAFANA_ROOT_URL=http://54.152.52.171:3000
GRAFANA_SERVE_FROM_SUBPATH=false
GRAFANA_COOKIE_SECURE=false
GRAFANA_ANONYMOUS_ACCESS=false
GRAFANA_LOG_LEVEL=warn

# ── Loki ──────────────────────────────────────────────────────
LOKI_PORT=3100
LOKI_RETENTION_PERIOD=720h
LOKI_STORAGE_TYPE=filesystem

# ── Alertmanager ──────────────────────────────────────────────
ALERTMANAGER_PORT=9093
ALERTMANAGER_EXTERNAL_URL=http://54.152.52.171:9093
ALERTMANAGER_LOG_LEVEL=warn

# ── SMTP — Gmail App Password ─────────────────────────────────
# Generate at: https://myaccount.google.com/apppasswords
SMTP_FROM=janak.shrestha.it@gmail.com
SMTP_AUTH_USERNAME=janak.shrestha.it@gmail.com
SMTP_AUTH_PASSWORD=<GMAIL_APP_PASSWORD>
DEFAULT_ALERT_EMAIL=janak123g@gmail.com

# ── AWS EC2 SD (optional — leave commented for now) ───────────
# AWS_EC2_SD_ACCESS_KEY_ID=
# AWS_EC2_SD_SECRET_ACCESS_KEY=
```

Save: `Ctrl+O` → Enter → `Ctrl+X`

### 4d. Set File SD targets to point to the client
```bash
cat > prometheus/targets/node_exporter.json << 'EOF'
[
  {
    "targets": ["34.230.91.8:9100"],
    "labels": {"job": "node_exporter", "host": "client1", "environment": "production"}
  }
]
EOF

cat > prometheus/targets/alloy.json << 'EOF'
[
  {
    "targets": ["34.230.91.8:12345"],
    "labels": {"job": "alloy", "host": "client1", "environment": "production"}
  }
]
EOF

cat > prometheus/targets/process_exporter.json << 'EOF'
[
  {
    "targets": ["34.230.91.8:9256"],
    "labels": {"job": "process_exporter", "host": "client1", "environment": "production"}
  }
]
EOF
```

### 4e. Start the server stack
```bash
docker compose up -d
```

### 4f. Verify all server services are Up
```bash
docker compose ps
```

Expected:
```
NAME                  STATUS    PORTS
alertmanager          Up        0.0.0.0:9093->9093/tcp
docker-socket-proxy   Up
grafana               Up        0.0.0.0:3000->3000/tcp
loki                  Up        0.0.0.0:3100->3100/tcp
prometheus            Up        0.0.0.0:9090->9090/tcp
```

Check for errors:
```bash
docker compose logs --tail=20
```

Check Prometheus health:
```bash
curl -s http://localhost:9090/-/healthy
# Expected: Prometheus Server is Healthy.
```

### 4g. Exit the server
```bash
exit
```

---

## STEP 5 — Deploy the CLIENT Environment

### 5a. Transfer client files (from your local machine)
```bash
rsync -avz \
  -e "ssh -i ~/.ssh/your-key.pem" \
  --exclude '.env' \
  /home/jack/Documents/observability/client/ \
  ubuntu@34.230.91.8:~/observability/client/
```

### 5b. SSH into the client
```bash
ssh -i ~/.ssh/your-key.pem ubuntu@34.230.91.8
cd ~/observability/client
```

### 5c. Create the client `.env`
```bash
nano .env
```

Fill in these values:

```bash
# ── Core ──────────────────────────────────────────────────────
COMPOSE_PROJECT_NAME=observability-client
HOSTNAME=client1
ENVIRONMENT=production

# ── Exporter Ports (keep defaults) ───────────────────────────
NODE_EXPORTER_PORT=9100
ALLOY_PORT=12345
PROCESS_EXPORTER_PORT=9256

# ── Server Connection ─────────────────────────────────────────
LOKI_URL=http://54.152.52.171:3100/loki/api/v1/push
PROMETHEUS_URL=http://54.152.52.171:9090/api/v1/write
```

Save: `Ctrl+O` → Enter → `Ctrl+X`

### 5d. Start the client stack
```bash
docker compose up -d
```

### 5e. Verify all client services are Up
```bash
docker compose ps
```

Expected:
```
NAME               STATUS    PORTS
alloy              Up        0.0.0.0:12345->12345/tcp
node-exporter      Up        0.0.0.0:9100->9100/tcp
process-exporter   Up        0.0.0.0:9256->9256/tcp
```

Check Alloy logs:
```bash
docker compose logs alloy | tail -n 10
# Look for: "now listening for http traffic" — no errors
```

### 5f. Exit the client
```bash
exit
```

---

## STEP 6 — End-to-End Verification

### 6a. Open Grafana
**URL:** http://54.152.52.171:3000
**Login:** `admin` / `<your password>`

### 6b. Check all Prometheus targets
**URL:** http://54.152.52.171:9090/targets

All should be **green (UP)**:

| Target | Discovery | Status |
|--------|-----------|--------|
| `prometheus` | Docker SD | UP |
| `grafana` | Docker SD | UP |
| `loki` | Docker SD | UP |
| `alertmanager` | Docker SD | UP |
| `node_exporter` | File SD | UP |
| `alloy` | File SD | UP |
| `process_exporter` | File SD | UP |

Or check via CLI:
```bash
ssh -i ~/.ssh/your-key.pem ubuntu@54.152.52.171

curl -s http://localhost:9090/api/v1/targets | python3 -c "
import json, sys
d = json.load(sys.stdin)
for t in d['data']['activeTargets']:
    print(f\"[{t['health']:7}] {t['labels'].get('job','?'):25} -> {t['labels'].get('instance','?')}\")"
```

### 6c. Verify logs are arriving from the client
In Grafana: **Explore → Loki datasource** → query:
```
{host="client1"}
```
You should see live system and Docker logs from the client.

### 6d. Test alert email
```bash
# From your local machine — no SSH needed
curl -XPOST http://54.152.52.171:9093/api/v1/alerts \
  -H 'Content-Type: application/json' \
  -d '[{"labels":{"alertname":"TestAlert","severity":"critical"}}]'
```
Check inbox at `janak123g@gmail.com`.

### 6e. Confirm exporters reachable from server
```bash
ssh -i ~/.ssh/your-key.pem ubuntu@54.152.52.171

curl -s http://34.230.91.8:9100/metrics | head -3    # node_exporter
curl -s http://34.230.91.8:12345/metrics | head -3   # alloy
curl -s http://34.230.91.8:9256/metrics | head -3    # process_exporter
# Each should return lines starting with #
```

---

## Adding More Client Nodes Later

### Option A — File SD (instant, no restart)
```bash
ssh -i ~/.ssh/your-key.pem ubuntu@54.152.52.171
nano ~/observability/server/prometheus/targets/node_exporter.json
```
Add the new entry to the JSON array, then:
```bash
curl -XPOST http://localhost:9090/-/reload
# Prometheus reloads within 30 seconds
```

### Option B — EC2 SD (automatic via AWS tags)
Tag the EC2 instance in AWS Console:

| Key | Value |
|-----|-------|
| `Scrape` | `true` |
| `Name` | `client2` |
| `Environment` | `production` |

Add credentials to server `.env` and restart Prometheus:
```bash
ssh -i ~/.ssh/your-key.pem ubuntu@54.152.52.171
nano ~/observability/server/.env
# Set: AWS_EC2_SD_ACCESS_KEY_ID and AWS_EC2_SD_SECRET_ACCESS_KEY

docker compose restart prometheus
```

---

## Daily Operations Reference

```bash
# ── SSH ───────────────────────────────────────────────────────
ssh -i ~/.ssh/your-key.pem ubuntu@54.152.52.171   # server
ssh -i ~/.ssh/your-key.pem ubuntu@34.230.91.8     # client

# ── Service management (on server) ───────────────────────────
docker compose ps
docker compose logs -f
docker compose logs -f grafana
docker compose restart prometheus
docker compose up -d

# ── Prometheus config reload (no restart) ────────────────────
curl -XPOST http://localhost:9090/-/reload

# ── Re-sync after local config changes ───────────────────────
# From local machine:
rsync -avz -e "ssh -i ~/.ssh/your-key.pem" \
  --exclude '.env' \
  /home/jack/Documents/observability/server/ \
  ubuntu@54.152.52.171:~/observability/server/

# Then on server:
docker compose up -d

# ── Update images ─────────────────────────────────────────────
docker compose pull && docker compose up -d
```
