# Server Setup Guide

## Overview

The observability server is the central node that aggregates logs and metrics from your client instances. It runs the following core components:
1. **Prometheus**: Scrapes and stores time-series metrics.
2. **Grafana**: Visualizes metrics and logs via diverse dashboards.
3. **Loki**: Aggregates logs sent by Alloy agents.
4. **Alertmanager**: Triggers notifications for alerts based on Prometheus rules.
5. **Nginx** (Production only): Reverse proxy handling port mapping and TLS.

---

## 1. Prerequisites (Port Configuration)

Ensure your server's firewall (e.g., AWS Security Group) is configured correctly.

### 1.1 Inbound Rules (Traffic reaching you)

| Port | Protocol | Source | Purpose |
|------|----------|--------|---------|
| `80` | TCP | `0.0.0.0/0` | HTTP traffic to Grafana UI / Nginx |
| `443`| TCP | `0.0.0.0/0` | HTTPS traffic to Grafana UI / Nginx |
| `3000`| TCP | Your IP | Direct access to Grafana (for dev/debugging) |
| `9090`| TCP | Your IP | Direct access to Prometheus UI |
| `3100`| TCP | **Client IPs** | Log ingestion endpoint for Loki |
| `9093`| TCP | Your IP | Direct access to Alertmanager UI |

### 1.2 Outbound Rules (Traffic leaving you)

| Port | Protocol | Destination | Purpose |
|------|----------|-------------|---------|
| `443` | TCP | `0.0.0.0/0` | Pull Docker images from registry / AWS API |
| `587` | TCP | `0.0.0.0/0` | Alertmanager sending emails via SMTP |
| `9100`| TCP | Client IPs | Prometheus scrapes node_exporter |
| `12345`| TCP | Client IPs | Prometheus scrapes Alloy metrics |
| `9256`| TCP | Client IPs | Prometheus scrapes process_exporter |
| `9338`| TCP | Client IPs | Prometheus scrapes cAdvisor |
| `9113`| TCP | Client IPs | Prometheus scrapes nginx_exporter |
| `9506`| TCP | Client IPs | Prometheus scrapes jenkins_exporter |

---

## 2. Server Deployment

### 2.1 Sync the files to your server
If you are deploying from a local machine, sync the `server` directory to your EC2 instance.

```bash
rsync -avz -e "ssh -i ~/.ssh/your-key.pem" \
  --exclude '.env' \
  /path/to/observability/server/ \
  ubuntu@<SERVER_IP>:~/observability/server/
```

### 2.2 Define Environment Variables
The `.env` file controls your server deployment based on the template.

```bash
cd ~/observability/server
cp .env-example .env
nano .env
```

**Key Variables Reference:**

| Variable | Dev Default | Production |
|----------|-------------|------------|
| `ENVIRONMENT` | `development` | `production` |
| `SCRAPE_INTERVAL` | `15s` | `30s` |
| `GRAFANA_ADMIN_PASSWORD` | `admin` | Generate a strong password |
| `GRAFANA_ROOT_URL` | `http://localhost:3000` | `https://your-domain.com` or IP |
| `GRAFANA_COOKIE_SECURE` | `false` | `true` (if using HTTPS) |
| `LOKI_STORAGE_TYPE` | `filesystem` | `s3` (See `aws-guide.md` for setup) |
| `ALERTMANAGER_EXTERNAL_URL` | `http://localhost:9093` | `http://<SERVER_IP>:9093` |

### 2.3 Set Up Alert Configuration (Optional)
Specify SMTP credentials in your `.env` so Alertmanager can send email notifications.

```env
SMTP_FROM=sender@gmail.com
SMTP_AUTH_USERNAME=sender@gmail.com
SMTP_AUTH_PASSWORD=xxxx_xxxx_xxxx_xxxx   # Use a Google App Password
DEFAULT_ALERT_EMAIL=oncall@yourcompany.com
```

### 2.4 Start the Stack
Start the server containers.

```bash
docker compose up -d
```

> **Note:** If deploying inside an environment with port 80/443 mapping, include the Nginx profile: `docker compose --profile nginx up -d`

---

## 3. Service Discovery (Adding Clients)

Prometheus needs to dynamically learn about which client nodes to scrape. The repo implements three tracking systems:

### 3.1 Docker SD (Internal Containers)
Internal containers are automatically scraped by Prometheus via the docker-socket-proxy using Docker compose labels.
Example for new services:
```yaml
labels:
  prometheus.io/scrape: "true"
  prometheus.io/port: "9090"
  prometheus.io/path: "/metrics"
```

### 3.2 EC2 SD (AWS Automated Discovery)
Prometheus can automatically scrape instances launched in AWS by querying tags. Refer to the **AWS Guide (`aws-guide.md`)** for configuring this feature. 

### 3.3 File SD (Manual Node Management)
For nodes not in AWS or strictly manual control, Prometheus watches a file `prometheus/targets/clients.json`. 

**Never edit the JSON manually.** Use the helper scripts within the `/server/scripts` folder.

**Add a standard node (node, alloy, process, cadvisor):**
```bash
./scripts/add-node.sh <IP> <HOSTNAME> [ENVIRONMENT]
./scripts/add-node.sh 34.230.91.8 my-web-node production
```

**Add a node with specific app exporters:**
```bash
# Node with Nginx exporter
./scripts/add-node.sh 10.0.1.50 web-01 production --nginx

# Node with Nginx & Jenkins exporters
./scripts/add-node.sh 54.152.52.171 build-manager production --nginx --jenkins
```

**Remove a node:**
```bash
./scripts/remove-node.sh <HOSTNAME>
./scripts/remove-node.sh my-web-node
```

**List all actively monitored nodes:**
```bash
jq '.[].labels.host' prometheus/targets/clients.json
```

Prometheus watches the JSON file for changes—**restarting Prometheus is not required.**

---

## 4. Testing & Operations

### 4.1 Common Management Commands

```bash
docker compose ps                               # View status of containers
docker compose logs -f                          # Tail all logs
docker compose logs -f prometheus               # Tail a specific container
docker compose restart grafana alertmanager     # Restart specific services
docker compose pull && docker compose up -d     # Update images to latest versions
```

### 4.2 Reload Configurations
If you modify `prometheus.yml` but don't want to restart the container, perform a hot-reload:
```bash
curl -XPOST http://localhost:9090/-/reload
```

### 4.3 Test Alert Routing
Test your Alertmanager SMTP setup by sending a mock alert:

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

### 4.4 Load Testing (Client Side)
To verify your CPU and Memory alerts functionally trigger, SSH into a **Client Node** and artificially generate load.

**Memory Stress (2-3 minutes):**
```bash
python3 -c "import time; a = bytearray(8 * 1024**3); print('Memory allocated!'); time.sleep(360)"
```

**CPU Stress (7 minutes):**
```bash
# Spawns 4 infinite loops background processes. Runs for 360 seconds.
for i in 1 2 3 4; do (while true; do :; done) & done; sleep 360 && kill $(jobs -p) 2>/dev/null
```
