Access Points:

Grafana: http://localhost:3000 (admin / your-password)
Prometheus: http://localhost:9090
Loki: http://localhost:3100
Alertmanager: http://localhost:9093
Alloy UI: http://localhost:12345

# Reload Prometheus config without restart
curl -X POST http://localhost:9090/-/reload


# Observability Stack - Client-Server Monitoring Solution

## Overview
This is a complete, production-ready monitoring solution with client-server architecture. It includes Prometheus, Grafana, Loki, and Alertmanager on the server side, and various exporters on the client side.

## Architecture

### Server Components
- **Prometheus**: Metrics collection and storage
- **Grafana**: Visualization and dashboards
- **Loki**: Log aggregation
- **Alertmanager**: Alert handling and notification

### Client Components
- **Node Exporter**: System metrics (CPU, memory, disk, network)
- **Alloy**: Log collection and forwarding
- **Process Exporter**: Process-level monitoring
- **Additional Exporters**: Nginx, Jenkins, PostgreSQL, MySQL, Redis (enabled via profiles)

## Prerequisites
- Docker Engine 20.10+
- Docker Compose 2.0+
- Network connectivity between client and server
- Ports availability as configured in .env files

## Quick Start

### 1. Server Setup
```bash
cd server
cp .env.example .env
# Edit .env with your configuration
docker-compose up -d