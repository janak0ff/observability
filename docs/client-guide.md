# Client Setup Guide

## Prerequisites


#### Inbound Rules (From Server IP ONLY)
Ports: `9100` (Node), `12345` (Alloy), `9256` (Process), `9338` (cAdvisor), `9113` (Nginx), `9506` (Jenkins)

#### Outbound Rules
Ports: `3100` (Loki), `9090` (Prometheus)

> [!IMPORTANT]
> Deploy and verify the **server** before starting the client.


---

## Transfer Files

Run from your **local machine**:

```bash
rsync -avz -e "ssh -i ~/.ssh/labsuser.pem" /home/jack/Documents/observability/client/ ubuntu@34.230.91.8:~/observability/client/
```

---

## Verify

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
ssh -i ~/.ssh/your-key.pem ubuntu@202.51.74.196

curl -s http://34.230.91.8:9100/metrics | head -3
curl -s http://34.230.91.8:12345/metrics | head -3
curl -s http://34.230.91.8:9256/metrics | head -3
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
sudo usermod -aG docker $USER && newgrp docker
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

## ⚠️ Important: Enable Docker Daemon Metrics

The client observability stack collects statistics about the Docker engine itself. By default, Docker does not expose these metrics. You **must explicitly enable them** on every client node.

Run these steps on the client server:

```bash
# 1. Create or update the Docker daemon config
sudo tee /etc/docker/daemon.json << 'EOF'
{
  "metrics-addr": "127.0.0.1:9323"
}
EOF

# 2. Restart the Docker service to apply
sudo systemctl restart docker

# 3. Verify it is working:
curl http://127.0.0.1:9323/metrics | head -n 5
```

> **Note**: We bind to `127.0.0.1` intentionally. The Grafana Alloy container runs in host-network mode and scrapes this endpoint locally. Do not bind it to `0.0.0.0` or expose port 9323 to the internet.

---

## Testing Alerts (Manual Load Generation)

If you want to intentionally trigger the **HighCPUUsage** and **HighMemoryUsage** alerts to verify your Alertmanager email routing, you can use `stress-ng` to temporarily peg the server's resources.

```bash
# 1. Install the stress-ng utility
sudo apt-get update && sudo apt-get install -y stress-ng

# 2. Run a 10-minute stress test (75% CPU load across all cores, 75% RAM usage)
stress-ng --cpu $(nproc) --cpu-load 75 --vm 1 --vm-bytes 75% --timeout 10m
```

> **Note**: The Prometheus alerts are configured with a `for: 5m` duration. You must let this command run for at least 5 minutes before the alerts automatically transition from *Pending* to *Firing* and send you an email. You can press `Ctrl+C` at any time to abort the test early and resolve the alerts.