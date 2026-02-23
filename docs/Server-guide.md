# Server Setup Guide

#### Inbound Rules
Ports: 3000, 9090, 9093, 3100, 80
#### Outbound Rules
Ports: 443, 587, 9100, 12345, 9256, 9338, 9113, 9506
| Port | Protocol | Destination | Purpose |
|------|----------|-------------|---------|
| 443 | TCP | `0.0.0.0/0` | Pull Docker images from registry |
| 587 | TCP | `0.0.0.0/0` | Alertmanager → Gmail SMTP |
| 9100 | TCP | `Client IPs` | Prometheus scrapes client node_exporter |
| 12345 | TCP | `Client IPs` | Prometheus scrapes client Alloy |
| 9256 | TCP | `Client IPs` | Prometheus scrapes client process_exporter |
| 9338 | TCP | `Client IPs` | Prometheus scrapes client cAdvisor |
| 9113 | TCP | `Client IPs` | Prometheus scrapes client nginx_exporter |
| 9506 | TCP | `Client IPs` | Prometheus scrapes client jenkins_exporter |
---



## Step 4 — Add Client Nodes to Prometheus

To start monitoring a client node (like `34.230.91.8`), run the add-node script. This automatically adds all 3 exporters (node_exporter, alloy, process_exporter) to Prometheus without requiring a restart.

```bash
cd ~/observability/server
./scripts/add-node.sh 34.230.91.8 client1
```

To remove a node later:
```bash
./scripts/remove-node.sh client1
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
Targets are managed in a single file: `prometheus/targets/clients.json`. Prometheus hot-reloads it automatically within 30s.

**Never edit the JSON manually.** Use the provided scripts on the server:
```bash
# Add a node (adds all 3 exporters)
./scripts/add-node.sh <IP> <HOSTNAME> [ENVIRONMENT]

# Remove a node
./scripts/remove-node.sh <HOSTNAME>

# List all monitored nodes
jq '.[].labels.host' prometheus/targets/clients.json
```

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
curl -XPOST http://localhost:9093/api/v2/alerts \
  -H 'Content-Type: application/json' \
  -d '[
    {
      "labels": {
        "alertname": "TestAlertServer",
        "severity": "critical"
      }
    }
  ]'
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
sleep 380 && kill $pids && echo "Done! Check your email."





for i in 1 2 3 4; do (while true; do :; done) & done; sleep 360 && kill $(jobs -p) 2>/dev/null

for i in 1 2 ; do (while true; do :; done) & done; sleep 400 && kill $(jobs -p) 2>/dev/null


---
### 4d. Add the Client Node to Prometheus
```bash
cd ~/observability/server
./scripts/add-node.sh 34.230.91.8 client1
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



Adding a new node just one command:

```bash
./scripts/add-node.sh 34.230.91.8 client1
```

And listing all nodes:

```bash
jq '.[].labels.host' prometheus/targets/clients.json
```


docker compose up -d --remove-orphans
