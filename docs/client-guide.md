# Client Setup Guide

This guide provides a complete, step-by-step walkthrough for deploying the observability client stack on any Linux server (e.g., AWS EC2, on-premise).

The client stack is responsible for gathering logs and metrics from the server it resides on and pushing them to a central monitoring server.

## Overview of Components

The client stack consists of several lightweight containers:
1. **Node Exporter**: Collects hardware and OS metrics (CPU, RAM, disk usage, network I/O).
2. **Alloy**: Grafana's telemetry collector. It gathers logs (`/var/log/*`, Docker logs) and Docker daemon metrics, forwarding them to Loki and Prometheus.
3. **Process Exporter**: Collects per-process metrics (CPU, memory, file descriptors).
4. **cAdvisor**: Analyzes resource usage and performance of running Docker containers.
5. *(Optional)* **Additional Exporters**: Nginx, Jenkins, PostgreSQL, MySQL, Redis.

---

## 1. Prerequisites

Before installing the client stack, ensure the following network rules are configured on the client server's firewall (e.g., AWS Security Group).

### Inbound Rules (From the Monitor Server IP ONLY)
Allow the central Monitor server to reach these ports for scraping metrics. For security, restrict the source IP to your Monitor server's IP address.

| Port | Service | Purpose |
|------|---------|---------|
| `9100` | Node Exporter | OS/Hardware metrics |
| `12345` | Alloy | Alloy's own metrics |
| `9256` | Process Exporter | Per-process metrics |
| `9338` | cAdvisor | Docker container metrics |
| `9113` | Nginx Exporter | (Optional) Nginx metrics |
| `9506` | Jenkins Exporter | (Optional) Jenkins metrics |

### Outbound Rules
The client needs to send data (logs) to the central Monitor server.

| Port | Destination | Purpose |
|------|-------------|---------|
| `3100` | Monitor IP | Alloy forwarding logs to Loki |
| `9090` | Monitor IP | Alloy remote-writing metrics to Prometheus |
| `443` | `0.0.0.0/0` | Pulling Docker images from the internet |

> [!IMPORTANT]  
> Deploy and verify the **central Monitor server** before starting the client setup.

---

## 2. Server Preparation

Log in to the client server where you want to install the monitoring agents.

### Step 2.1: Install Docker
If Docker is not already installed, run the official installation script:
```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER && newgrp docker
```

### Step 2.2: Enable Docker Daemon Metrics
The client stack collects statistics about the Docker engine itself. By default, Docker does not expose these metrics. You **must explicitly enable them**.

1. Create or update the Docker daemon config:
```bash
sudo tee /etc/docker/daemon.json << 'EOF'
{
  "metrics-addr": "127.0.0.1:9323"
}
EOF
```

2. Restart the Docker service to apply the changes:
```bash
sudo systemctl restart docker
```

3. Verify it is working:
```bash
curl http://127.0.0.1:9323/metrics | head -n 5
```
> **Note**: We bind to `127.0.0.1` intentionally. The Grafana Alloy container runs in host-network mode (or accesses it via the host) and scrapes this endpoint locally. Do not expose port 9323 to the internet.

---

## 3. Deployment

### Step 3.1: Get the Source Code
Clone the observability repository to the client server.

```bash
git clone https://github.com/janak0ff/observability.git
cd observability/client
```

*(Alternatively, you can `rsync` just the `client` directory from your local machine to the server.)*
```bash
# From your local machine:
rsync -avz -e "ssh -i ~/.ssh/your-key.pem" /path/to/observability/client/ user@<CLIENT-IP>:~/observability/client/
```

### Step 3.2: Configure Environment Variables
Create the environment file from the cloud template:

```bash
cp .env-cloud .env
nano .env
```

Update the following critical variables in `.env`:
- `NODE_HOSTNAME`: Provide a unique, recognizable name for this client (e.g., `web-server-01`, `db-node-qa`). This is how it will appear in Grafana.
- `LOKI_URL`: Point this to your central Monitor server's Loki instance (e.g., `http://<MONITOR-IP>:3100/loki/api/v1/push`).
- `PROMETHEUS_URL`: Point this to your central Monitor server's Prometheus instance (e.g., `http://<MONITOR-IP>:9090/api/v1/write`).
- `ENVIRONMENT`: Set to match the environment (e.g., `production`, `staging`, `development`).

### Step 3.3: Start the Stack
Bring up the Docker Compose stack in detached mode:

```bash
docker compose --env-file .env up -d
```

---

## 4. Verification

### Step 4.1: Check Local Containers
Ensure all containers started successfully without crash-looping:

```bash
# View running containers (should be 4 by default)
docker compose ps

# Check logs for errors (especially Alloy)
docker compose logs alloy | tail -n 20
```

### Step 4.2: Test Exporter Endpoints locally
Verify the exporters are actively serving metrics:

```bash
curl -s http://localhost:9100/metrics | head -3   # node_exporter
curl -s http://localhost:12345/metrics | head -3  # alloy
curl -s http://localhost:9256/metrics | head -3   # process_exporter
curl -s http://localhost:9338/metrics | head -3   # cadvisor
```

### Step 4.3: Verify from the Monitor Server
This is crucial. The central server must be able to reach the client.

1. SSH into your **Monitor Server**.
2. Run `curl` against the client's IP address:

```bash
# Replace <CLIENT-IP> with the actual IP address
curl -s http://<CLIENT-IP>:9100/metrics | head -3
```
If this hangs or fails, your AWS Security Group inbound rules are incorrect on the client.

---

## 5. Adding the Client to the Monitor Server

Once the client is running, you must tell the Prometheus server to start scraping it.

1. SSH into the **Monitor Server**.
2. Navigate to the server codebase.
3. Run the helper script:

```bash
cd ~/observability/server

# Usage: ./scripts/add-node.sh <CLIENT_IP> <HOSTNAME> [ENVIRONMENT]
./scripts/add-node.sh 34.230.91.8 client-web-01 production
```

This updates `prometheus/targets/clients.json` automatically, and Prometheus will begin scraping within 30 seconds. No restart is required.

---

## 6. Testing Alerts (Manual Load Generation)

If you want to intentionally trigger the **HighCPUUsage** and **HighMemoryUsage** alerts to verify your Alertmanager email routing, you can use `stress-ng` to temporarily peg the client server's resources.

1. Install the utility:
```bash
sudo apt-get update && sudo apt-get install -y stress-ng
```

2. Run a memory stress test (exceeding 80% RAM for 10 mins):
```bash
stress-ng --vm 1 --vm-bytes 85% --timeout 10m
```

3. Monitor the RAM usage in another terminal:
```bash
watch -n 1 free -h
```

> **Note**: Prometheus alerts configured with `for: 5m` require the metrics to stay above the threshold for 5 continuous minutes before transitioning from *Pending* to *Firing* and sending an email. Press `Ctrl+C` to abort.

---

## 7. Useful Administration Commands

**Apply config updates:**
If you change `configs/config.alloy` or `.env`, run:
```bash
docker compose up -d
```
Docker Compose detects the changes and recreates only the necessary containers.

**Restart a single service:**
```bash
docker compose restart alloy
```

**Update to latest Docker images:**
```bash
docker compose pull && docker compose up -d
```

**Adding multiple Loki endpoints:**
If you have multiple monitoring servers, Alloy can send logs to all of them. Edit `configs/config.alloy`:
```alloy
loki.write "server2" {
  endpoint {
    url = "http://<SECOND-MONITOR-IP>:3100/loki/api/v1/push"
  }
}
```
*(Remember to apply changes with `docker compose restart alloy`)*.