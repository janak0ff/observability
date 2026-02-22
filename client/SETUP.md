# Client Setup Guide

## Prerequisites


#### Inbound Rules
Ports: 9100,12345,9256

#### Outbound Rules
Ports: 3100,9090

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
