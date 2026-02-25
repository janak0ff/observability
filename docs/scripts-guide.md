# Node Management Scripts Guide

This guide details the usage of the helper scripts located in the `server/scripts/` directory. These scripts are designed to dynamically add or remove client nodes from Prometheus' scraping targets without requiring a restart of the Prometheus service.

## 1. Overview

Prometheus is configured using a File-based Service Discovery (File SD) mechanism. Instead of hardcoding static IP addresses into the main `prometheus.yml` configuration parsing block, Prometheus watches a JSON file: `prometheus/targets/clients.json`.

The provided scripts safely modify this JSON file. Prometheus detects changes to the file and updates its targets within 30 seconds automatically.

> **Never edit `prometheus/targets/clients.json` manually**, as invalid JSON syntax will cause Prometheus to stop reading the file entirely.

---

## 2. Using `add-node.sh`

The `add-node.sh` script registers a new client node to be monitored by the central server. By default, it registers the three core mandatory exporters: `node_exporter`, `alloy`, and `process_exporter`.

### Syntax

```bash
cd ~/observability/server
./scripts/add-node.sh <IP_ADDRESS> <HOSTNAME> [ENVIRONMENT] [--nginx] [--jenkins]
```

### Arguments

| Argument | Requirement | Description |
|---|---|---|
| `<IP_ADDRESS>` | **Required** | The public or private IPv4 address of the client node. |
| `<HOSTNAME>` | **Required** | A unique, human-readable identifier for the node (e.g., `web-server-01`). This becomes the `instance` label in Grafana. |
| `[ENVIRONMENT]` | *Optional* | The environment tag (e.g., `production`, `staging`). If omitted, it defaults to the value of `$ENVIRONMENT` in your `.env` file, or simply `production`. |
| `--nginx` | *Optional* | Flag to append the node's Nginx metrics port (`9113`) to the target list. |
| `--jenkins` | *Optional* | Flag to append the node's Jenkins metrics port (`9506`) to the target list. |

### Examples

**Example 1: Adding a standard Database Node**
```bash
./scripts/add-node.sh 10.0.5.12 db-primary-01 production
```
*Result:* Prometheus begins scraping `10.0.5.12` on ports `9100`, `12345`, `9256`, and `9338`.

**Example 2: Adding a Web Server with Nginx Exporter**
```bash
./scripts/add-node.sh 34.230.91.8 my-nginx-frontend production --nginx
```
*Result:* Prometheus begins scraping the 4 standard ports, **plus** port `9113` for Nginx metrics.

**Example 3: Adding a CI/CD Server with both Nginx and Jenkins**
```bash
./scripts/add-node.sh 54.152.52.171 jenkins-build-server production --nginx --jenkins
```
*Result:* Prometheus begins scraping the 4 standard ports, **plus** ports `9113` (Nginx) and `9506` (Jenkins).

---

## 3. Using `remove-node.sh`

The `remove-node.sh` script safely removes a client node from the monitoring targets list.

### Syntax

```bash
cd ~/observability/server
./scripts/remove-node.sh <HOSTNAME>
```

### Arguments

| Argument | Requirement | Description |
|---|---|---|
| `<HOSTNAME>` | **Required** | The exact hostname provided when the node was added (e.g., `web-server-01`). |

### Examples

**Example 1: Removing a decommissioned server**
```bash
./scripts/remove-node.sh jenkins-build-server
```
*Result:* The node `jenkins-build-server` is purged from `clients.json`. Prometheus will stop scraping it within 30 seconds. Historical metrics already collected remain in Prometheus until the retention period expires.

---

## 4. Troubleshooting & Verification

**List all currently Monitored Nodes:**
To see exactly which hostnames are actively registered in the JSON file, use the following `jq` command:
```bash
jq '.[].labels.host' prometheus/targets/clients.json
```

**Check Prometheus Targets UI:**
Open `http://<Monitor-IP>:9090/targets` in your browser. 
- You should see the target groups (e.g., `file-sd-node-exporter`, `file-sd-alloy`) populated with your new endpoints.
- If the endpoints are `DOWN`, double-check the client node's AWS Security Group inbound rules to ensure the Monitor Server is permitted to reach those ports.

**Manual File Reset:**
If the `clients.json` file becomes corrupted, you can easily reset it to an empty state:
```bash
echo "[]" > prometheus/targets/clients.json
```
Then safely utilize `add-node.sh` to redeclare your nodes.
