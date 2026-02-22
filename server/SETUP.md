# Server Setup Guide

#### Inbound Rules
Ports: 3000, 9090, 9093, 3100, 80
#### Outbound Rules
Ports: 443, 587, 9100, 12345, 9256
| Port | Protocol | Destination | Purpose |
|------|----------|-------------|---------|
| 443 | TCP | `0.0.0.0/0` | Pull Docker images from registry |
| 587 | TCP | `0.0.0.0/0` | Alertmanager → Gmail SMTP |
| 9100 | TCP | `34.230.91.8/32` | Prometheus scrapes client node_exporter |
| 12345 | TCP | `34.230.91.8/32` | Prometheus scrapes client Alloy |
| 9256 | TCP | `34.230.91.8/32` | Prometheus scrapes client process_exporter |
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
| `GRAFANA_ROOT_URL` | `http://localhost:3000` | `http://202.51.74.196:3000` |
| `GRAFANA_COOKIE_SECURE` | `false` | `true` (if HTTPS) |
| `LOKI_STORAGE_TYPE` | `filesystem` | `filesystem` or `s3` |
| `ALERTMANAGER_EXTERNAL_URL` | `http://localhost:9093` | `http://202.51.74.196:9093` |
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



load testing 



run this (adjust 8 to ~80% of your total RAM in GB):
```
python3 -c "import time; a = bytearray(8 * 1024**3); print('Memory allocated!'); time.sleep(360)"
```

CPU stress for just 2 minutes
echo "Starting 2-minute CPU stress... DO NOT close this terminal!"
for i in 1 2 3 4; do (while true; do :; done) & pids+=" $!"; done
sleep 120 && kill $pids && echo "Done! Check your email."


echo "Starting 6-minute CPU stress... DO NOT close this terminal!"
for i in 1 2 3 4; do (while true; do :; done) & pids+=" $!"; done
sleep 360 && kill $pids && echo "Done! Check your email."


for i in 1 2 3 4; do (while true; do :; done) & done; sleep 360 && kill $(jobs -p) 2>/dev/null




---
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




# Server
rsync -avz --exclude '.env' /home/jack/Documents/observability/server/ ubuntu@54.152.52.171:~/observability/server/

# Client
rsync -avz --exclude '.env' /home/jack/Documents/observability/client/ ubuntu@34.230.91.8:~/observability/client/


# Start 2 CPU stress processes in the background
yes > /dev/null & yes > /dev/null &

docker-compose logs alloy | grep -i "loki" | tail -n 15
docker-compose down && docker-compose up -d
docker compose restart grafana alertmanager
curl -s http://54.152.52.171:3100/ready


# Reload Prometheus config without restart
curl -X POST http://localhost:9090/-/reload
