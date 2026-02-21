# Client Setup Guide

Runs: **Node Exporter · Alloy · Process Exporter**

> **Public IP:** `34.230.91.8`
> **Server IP:** `54.152.52.171` (Prometheus + Loki)

---

## Prerequisites

### AWS Security Group — inbound rules
| Port | Source | Purpose |
|------|--------|---------|
| 22 | Your IP | SSH |
| 9100 | `54.152.52.171/32` | Node Exporter (server scrapes) |
| 12345 | `54.152.52.171/32` | Alloy metrics (server scrapes) |
| 9256 | `54.152.52.171/32` | Process Exporter (server scrapes) |

> **The server must be deployed and running before starting the client.**

---

## Step 1 — Install Docker

```bash
ssh -i ~/.ssh/your-key.pem ubuntu@34.230.91.8

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
  /home/jack/Documents/observability/client/ \
  ubuntu@34.230.91.8:~/observability/client/
```

---

## Step 3 — Configure `.env`

```bash
ssh -i ~/.ssh/your-key.pem ubuntu@34.230.91.8
cd ~/observability/client
nano .env
```

Set these values:

```bash
# ── Identity ──────────────────────────────────────────────────
COMPOSE_PROJECT_NAME=observability-client
HOSTNAME=client1
ENVIRONMENT=production

# ── Exporter Ports (keep defaults) ───────────────────────────
NODE_EXPORTER_PORT=9100
ALLOY_PORT=12345
PROCESS_EXPORTER_PORT=9256

# ── Server Connection ─────────────────────────────────────────
# Point to the server public IP
LOKI_URL=http://54.152.52.171:3100/loki/api/v1/push
PROMETHEUS_URL=http://54.152.52.171:9090/api/v1/write
```

Save: `Ctrl+O` → Enter → `Ctrl+X`

---

## Step 4 — Start the Client Stack

```bash
docker compose up -d
```

---

## Step 5 — Verify

```bash
# All 3 services should show Up
docker compose ps

# Check Alloy started with no errors
docker compose logs alloy | tail -n 10

# Check exporters are responding
curl -s http://localhost:9100/metrics | head -3   # node_exporter
curl -s http://localhost:12345/metrics | head -3  # alloy
curl -s http://localhost:9256/metrics | head -3   # process_exporter
```

### Verify from the SERVER side

SSH into the server and confirm it can reach the client:

```bash
ssh -i ~/.ssh/your-key.pem ubuntu@54.152.52.171

curl -s http://34.230.91.8:9100/metrics | head -3
curl -s http://34.230.91.8:12345/metrics | head -3
curl -s http://34.230.91.8:9256/metrics | head -3
```

Then check Prometheus targets at **http://54.152.52.171:9090/targets** — `node_exporter`, `alloy`, and `process_exporter` should show **UP**.

### Verify logs in Grafana

In Grafana (http://54.152.52.171:3000): **Explore → Loki** → query:
```
{host="client1"}
```

---

## Common Commands

```bash
docker compose ps                    # Status
docker compose logs -f               # All logs
docker compose logs -f alloy         # Alloy logs
docker compose restart alloy         # Restart a service
docker compose up -d                 # Apply config changes
docker compose pull && docker compose up -d   # Update images
```

## Re-sync After Local Config Changes

```bash
# From local machine
rsync -avz -e "ssh -i ~/.ssh/your-key.pem" \
  --exclude '.env' \
  /home/jack/Documents/observability/client/ \
  ubuntu@34.230.91.8:~/observability/client/

# Then on client
docker compose up -d
```

## Adding This Client to More Servers

If you deploy a second observability server and want this client to also ship logs to it, simply add another Loki endpoint in `configs/config.alloy`:

```alloy
loki.write "server2" {
  endpoint {
    url = "http://<NEW_SERVER_IP>:3100/loki/api/v1/push"
  }
}
```
