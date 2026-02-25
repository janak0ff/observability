Access Points:

Grafana: http://localhost:3000 (admin / your-password)
Prometheus: http://localhost:9090
Loki: http://localhost:3100
Alertmanager: http://localhost:9093
Alloy UI: http://localhost:12345
Logs from client35	http://54.152.52.171:3000
Loki health check	http://54.152.52.171:3100/ready
Loki's own metrics	http://54.152.52.171:3100/metrics
Prometheus targets	http://54.152.52.171:9090/targets
Alloy metrics (on client)	http://{client_ip}:12345/metrics
Node exporter (on client)	http://{client_ip}:9100/metrics



Essential Grafana Dashboards:
- Full Node Exporter : 1860
- Jenkins: Performance and Health Overview: 9964
- Nginx Dashboard → ID: 12708
- SSH Logs : 17514
- Global SSH Logs View : 21750
- Logs / App : 13639
- Docker Container : 11600
- cAdvisor Docker Insights : 19908
- y0nei's cAdvisor dashboard : 19724
- docker container & OS node(node_exporter, cadvisor) : 16314
- MongoDB : 2583




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


