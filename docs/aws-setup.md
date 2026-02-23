
# AWS Setup Guide

This guide covers two AWS integrations for the observability stack:
1. **S3 bucket** — persistent object storage for Loki logs
2. **EC2 Service Discovery** — automatic Prometheus scraping of EC2 instances via tags

> **Prerequisites**: AWS CLI installed and configured (`~/.aws/credentials` set).  
> Verify with: `aws sts get-caller-identity`

---

## Part 0 — IAM Policies (Attach Required Permissions)

Before creating any resources, make sure your IAM user/role has the correct permissions.

### What permissions are needed

| Integration | Required Actions |
|---|---|
| Loki S3 storage | `s3:PutObject`, `s3:GetObject`, `s3:DeleteObject`, `s3:ListBucket` |
| EC2 Service Discovery | `ec2:DescribeInstances` |

### Option A — Create and attach an inline policy (standard AWS accounts only)

> ⚠️ **This does NOT work with AWS Academy / assumed roles.**  
> If `aws sts get-caller-identity` shows `assumed-role` in the Arn, skip to Option B.

```bash
# Only works if you are authenticated as a real IAM user (not an assumed role)
IAM_USER=$(aws iam get-user --query 'User.UserName' --output text)

cat > /tmp/observability-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "LokiS3Access",
      "Effect": "Allow",
      "Action": ["s3:PutObject","s3:GetObject","s3:DeleteObject","s3:ListBucket","s3:GetBucketLocation"],
      "Resource": [
        "arn:aws:s3:::my-loki-logs-prod-janak0ff",
        "arn:aws:s3:::my-loki-logs-prod-janak0ff/*"
      ]
    },
    {
      "Sid": "EC2ServiceDiscovery",
      "Effect": "Allow",
      "Action": ["ec2:DescribeInstances","ec2:DescribeAvailabilityZones","ec2:DescribeTags"],
      "Resource": "*"
    }
  ]
}
EOF

aws iam put-user-policy \
  --user-name "$IAM_USER" \
  --policy-name "ObservabilityStackPolicy" \
  --policy-document file:///tmp/observability-policy.json

echo "✅ Policy attached to $IAM_USER"
```

Verify:
```bash
aws iam list-user-policies --user-name "$IAM_USER"
```

### Option B — AWS Academy / Vocareum (assumed role)

> ✅ **You are here** — your session is an assumed role (`voclabs`), confirmed by `assumed-role` in the Arn.  
> The `voclabs` Lab role already has **full S3 and EC2 permissions** pre-attached.  
> **No policy attachment needed — skip directly to the verify step below.**

If you ever need to attach managed policies to a regular IAM **role** (not Academy):
```bash
ROLE_NAME="your-role-name"

aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess
```

### Verify permissions are working

```bash
# Test S3 access
aws s3 ls 2>&1 && echo "✅ S3 access OK" || echo "❌ S3 access DENIED"

# Test EC2 access
aws ec2 describe-instances --max-results 5 --query 'Reservations[0].Instances[0].InstanceId' --output text \
  && echo "✅ EC2 access OK" || echo "❌ EC2 access DENIED"
```



By default Loki stores logs on the local filesystem (`/loki/chunks`). Switching to S3 gives you persistent, scalable storage that survives container restarts and server replacements.

### Step 1 — Create the S3 Bucket

```bash
# Create bucket (bucket names must be globally unique)
aws s3api create-bucket \
  --bucket my-loki-logs-prod-janak0ff \
  --region us-east-1

# Block all public access (security best practice)
aws s3api put-public-access-block \
  --bucket my-loki-logs-prod-janak0ff \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Enable versioning (optional but recommended)
aws s3api put-bucket-versioning \
  --bucket my-loki-logs-prod-janak0ff \
  --versioning-configuration Status=Enabled
```

Verify it was created:
```bash
aws s3 ls | grep loki
```

### Step 2 — Set S3 Lifecycle Policy (auto-delete old logs)

This matches your `LOKI_RETENTION_PERIOD=720h` (30 days):

```bash
aws s3api put-bucket-lifecycle-configuration \
  --bucket my-loki-logs-prod-janak0ff \
  --lifecycle-configuration '{
    "Rules": [{
      "ID": "loki-log-expiry",
      "Status": "Enabled",
      "Filter": {"Prefix": ""},
      "Expiration": {"Days": 30}
    }]
  }'
```

### Step 3 — Update `.env-cloud` on the Server

Edit `server/.env-cloud`:

```env
# Switch Loki from filesystem to S3
LOKI_STORAGE_TYPE=s3

# Your bucket name
LOKI_BUCKET_NAME=my-loki-logs-prod-janak0ff

# AWS credentials
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=<your-access-key-id>
AWS_SECRET_ACCESS_KEY=<your-secret-access-key>
```

> **Note for AWS Academy/Vocareum**: Session credentials expire every few hours.  
> You also need to set `AWS_SESSION_TOKEN` — add it to `.env-cloud`:
> ```env
> AWS_SESSION_TOKEN=<your-session-token>
> ```
> And add it to `loki/loki-config.yaml` under `storage_config.aws`:
> ```yaml
> session_token: ${AWS_SESSION_TOKEN:-}
> ```

### Step 4 — Restart Loki with S3 Storage

```bash
# On the server, from the server/ directory
docker compose --env-file .env-cloud up -d loki
```

Check Loki started cleanly:
```bash
docker compose logs loki --tail=30
```

You should see lines like:
```
level=info msg="Starting Loki" ...
level=info msg="compactor started" ...
```

### Step 5 — Verify Logs are Going to S3

After a few minutes of Loki running, check the bucket:
```bash
aws s3 ls s3://my-loki-logs-prod-janak0ff/ --recursive | head -20
```

You should see `index/` and `chunks/` prefixes appearing.

---

## Part 2 — EC2 Service Discovery for Prometheus

Instead of manually adding every EC2 instance to `clients.json`, EC2 SD lets Prometheus auto-discover instances using their AWS tags.

### Step 1 — Find and  Tag Your EC2 Instances

Find your EC2 instance ID:
```bash
aws ec2 describe-instances --query "Reservations[*].Instances[*].{ID:InstanceId,Name:Tags[?Key=='Name']|[0].Value,State:State.Name}" --output table
```

For each EC2 instance you want Prometheus to scrape, add these tags in the AWS Console or via CLI:

| Tag Key     | Tag Value         | Description                        |
|-------------|-------------------|------------------------------------|
| `Scrape`    | `true`            | Opt this instance into scraping    |
| `Name`      | `aws-node-01`     | Used as the `instance` label       |
| `Job`       | `node_exporter`   | Used as the `job` label            |
| `Environment` | `production`    | Used as the `environment` label    |

Tag via CLI (replace `i-XXXXXXXXXXXXXXXXX` with your instance ID):
```bash
aws ec2 create-tags \
  --resources i-00e3709156ffacec6 \
  --tags \
    Key=Scrape,Value=true \
    Key=Name,Value=aws-node-01 \
    Key=Job,Value=node_exporter \
    Key=Environment,Value=production
```

### Step 2 — Update `.env-cloud` with EC2 SD Credentials

Edit `server/.env-cloud`:

```env
# EC2 Service Discovery
AWS_EC2_SD_REGION=us-east-1
AWS_EC2_SD_ACCESS_KEY_ID=<your-access-key-id>
AWS_EC2_SD_SECRET_ACCESS_KEY=<your-secret-access-key>
```

> **IAM permission required**: The credentials must have `ec2:DescribeInstances` permission.  
> If your server runs on an EC2 instance with an IAM role, leave these blank — Prometheus will use the instance role automatically.

### Step 3 — Enable EC2 SD Jobs in `prometheus.yml`

The EC2 SD jobs are already in `server/prometheus/prometheus.yml` — just uncomment them.

> **Critical**: Prometheus does NOT expand `${VAR}` in `ec2_sd_configs`. Hardcode `region` directly and omit `access_key`/`secret_key` — the AWS SDK reads credentials from the container environment automatically.

The correct config (already applied in this repo):

```yaml
  - job_name: 'ec2-sd-node-exporter'
    ec2_sd_configs:
      - region: us-east-1          # hardcoded — ${VAR} does NOT work here
        port: 9100
        refresh_interval: 60s
        filters:
          - name: tag:Scrape
            values: ['true']
          - name: instance-state-name
            values: ['running']
    relabel_configs:
      # Use public IP if Monitor server is outside the VPC
      # Switch to __meta_ec2_private_ip if Monitor is in the same VPC
      - source_labels: [__meta_ec2_public_ip]
        regex: '(.+)'
        replacement: '$1:9100'
        target_label: __address__
      - source_labels: [__meta_ec2_tag_Name]
        regex: '(.+)'
        target_label: instance
      - source_labels: [__meta_ec2_region]
        target_label: region
      - source_labels: [__meta_ec2_availability_zone]
        target_label: availability_zone
      - source_labels: [__meta_ec2_instance_type]
        target_label: instance_type
      - source_labels: [__meta_ec2_tag_Environment]
        regex: '(.+)'
        target_label: environment
      - target_label: job
        replacement: 'node_exporter'

  - job_name: 'ec2-sd-alloy'
    ec2_sd_configs:
      - region: us-east-1
        port: 12345
        refresh_interval: 60s
        filters:
          - name: tag:Scrape
            values: ['true']
          - name: tag:Job
            values: ['alloy']
          - name: instance-state-name
            values: ['running']
    relabel_configs:
      - source_labels: [__meta_ec2_public_ip]
        regex: '(.*)'
        replacement: '$1:12345'
        target_label: __address__
      - source_labels: [__meta_ec2_tag_Name]
        regex: '(.+)'
        target_label: instance
      - source_labels: [__meta_ec2_region]
        target_label: region
      - target_label: job
        replacement: 'alloy'
      - source_labels: [__meta_ec2_tag_Environment]
        regex: '(.+)'
        target_label: environment
```

Also ensure the Prometheus container has standard AWS env vars in `docker-compose.yml`:

```yaml
  prometheus:
    environment:
      - AWS_ACCESS_KEY_ID=${AWS_EC2_SD_ACCESS_KEY_ID:-}
      - AWS_SECRET_ACCESS_KEY=${AWS_EC2_SD_SECRET_ACCESS_KEY:-}
      - AWS_SESSION_TOKEN=${AWS_SESSION_TOKEN:-}
      - AWS_DEFAULT_REGION=${AWS_EC2_SD_REGION:-us-east-1}
```

### Step 4 — Reload Prometheus

```bash
# Hot-reload (no restart needed)
curl -sf -XPOST http://localhost:9090/-/reload && echo "✅ Reloaded"
```

### Step 5 — Verify EC2 SD in Prometheus UI

Open: `http://<server-ip>:9090/service-discovery`

You should see `ec2-sd-node-exporter` and `ec2-sd-alloy` jobs with your instances listed.

Verify targets are UP:
```bash
curl -s 'http://localhost:9090/api/v1/targets?state=active' | python3 -c "
import json,sys
data=json.load(sys.stdin)
for t in data['data']['activeTargets']:
    if 'ec2' in t['scrapePool']:
        print(t['labels']['instance'], t['health'], t.get('lastError',''))
"
```

---

## Part 3 — Install Client Stack on EC2 Nodes

For each EC2 node that Prometheus will scrape, install the client observability stack (node_exporter, alloy, process-exporter, cadvisor).

### Step 1 — SSH into the EC2 instance

```bash
ssh -i <your-key.pem> ubuntu@<EC2-PUBLIC-IP>
```

### Step 2 — Install Docker

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER && newgrp docker
```

### Step 3 — Clone the repo and configure

```bash
git clone https://github.com/janak0ff/observability.git
cd observability/client

# Create .env from the cloud template
cp .env-cloud .env

# Set the unique hostname for this node
sed -i 's/NODE_HOSTNAME=.*/NODE_HOSTNAME=aws-node-01/' .env
# Set your Monitor server IP
sed -i 's|LOKI_URL=.*|LOKI_URL=http://<MONITOR-IP>:3100/loki/api/v1/push|' .env
sed -i 's|PROMETHEUS_URL=.*|PROMETHEUS_URL=http://<MONITOR-IP>:9090/api/v1/write|' .env
```

### Step 4 — Start the client stack

```bash
docker compose --env-file .env up -d

# Verify all containers are running
docker compose ps
```

### Step 5 — Open required ports in Security Group

Make sure the EC2 instance's security group allows inbound TCP from the Monitor server:

| Port  | Service          |
|-------|------------------|
| 9100  | node_exporter    |
| 12345 | alloy            |
| 9256  | process_exporter |
| 9338  | cadvisor         |

```bash
# Allow from specific Monitor IP (recommended)
aws ec2 authorize-security-group-ingress \
  --group-id <sg-xxxxxxxxx> \
  --protocol tcp --port 9100 --cidr <MONITOR-IP>/32

aws ec2 authorize-security-group-ingress \
  --group-id <sg-xxxxxxxxx> \
  --protocol tcp --port 12345 --cidr <MONITOR-IP>/32

aws ec2 authorize-security-group-ingress \
  --group-id <sg-xxxxxxxxx> \
  --protocol tcp --port 9256 --cidr <MONITOR-IP>/32

aws ec2 authorize-security-group-ingress \
  --group-id <sg-xxxxxxxxx> \
  --protocol tcp --port 9338 --cidr <MONITOR-IP>/32
```

---

## Troubleshooting

### Loki: `InvalidAccessKeyId` — credentials rejected

```
level=error msg="failed to build table names cache" err="InvalidAccessKeyId"
```

**Causes & fixes:**

| Symptom | Cause | Fix |
|---|---|---|
| `InvalidAccessKeyId` | `AWS_SESSION_TOKEN` is blank/missing | Add `AWS_SESSION_TOKEN` to Loki env in `docker-compose.yml` and `.env` |
| `InvalidAccessKeyId` | Session expired (~4h for AWS Academy) | Get fresh credentials from Lab portal, update `.env`, restart Loki |
| `AccessDenied` | Missing S3 permissions | Attach S3 policy (see Part 0) |
| `NoSuchBucket` | Wrong bucket name in `.env` | Verify `LOKI_BUCKET_NAME` matches actual bucket |

```bash
# Update credentials on server when session expires:
sed -i 's|^AWS_ACCESS_KEY_ID=.*|AWS_ACCESS_KEY_ID=<new>|' .env
sed -i 's|^AWS_SECRET_ACCESS_KEY=.*|AWS_SECRET_ACCESS_KEY=<new>|' .env
sed -i 's|^AWS_SESSION_TOKEN=.*|AWS_SESSION_TOKEN=<new>|' .env
docker compose --env-file .env up -d --force-recreate loki
```

### EC2 SD: `invalid input region ${AWS_EC2_SD_REGION}`

```
failed to bind endpoint params, invalid input region ${AWS_EC2_SD_REGION}
```

**Cause**: Prometheus does NOT expand `${VAR}` in `ec2_sd_configs`.  
**Fix**: Hardcode the region and remove `access_key`/`secret_key` — use container env vars instead:

```yaml
# WRONG — ${VAR} is not expanded in ec2_sd_configs
ec2_sd_configs:
  - region: ${AWS_EC2_SD_REGION}
    access_key: ${AWS_EC2_SD_ACCESS_KEY_ID}

# CORRECT
ec2_sd_configs:
  - region: us-east-1   # hardcoded
    # no access_key/secret_key — SDK reads from container env
```

And add to `docker-compose.yml` Prometheus environment:
```yaml
- AWS_ACCESS_KEY_ID=${AWS_EC2_SD_ACCESS_KEY_ID:-}
- AWS_SECRET_ACCESS_KEY=${AWS_EC2_SD_SECRET_ACCESS_KEY:-}
- AWS_SESSION_TOKEN=${AWS_SESSION_TOKEN:-}
- AWS_DEFAULT_REGION=us-east-1
```

### EC2 SD: `0 / 0` targets — nothing discovered

```bash
# Check for errors
docker compose logs prometheus 2>&1 | grep -i "ec2\|error" | tail -10

# Verify instance has Scrape=true tag
aws ec2 describe-tags \
  --filters "Name=resource-id,Values=<instance-id>" \
  --query 'Tags[*].{Key:Key,Value:Value}' --output table

# List all your instances with their state
aws ec2 describe-instances \
  --query "Reservations[*].Instances[*].{ID:InstanceId,Name:Tags[?Key=='Name']|[0].Value,State:State.Name,IP:PublicIpAddress}" \
  --output table
```

Common causes:
- Instance not tagged with `Scrape=true`
- Instance is stopped (filter requires `instance-state-name=running`)
- Wrong region hardcoded in `prometheus.yml`
- `AWS_SESSION_TOKEN` missing from Prometheus container env

### EC2 SD: targets discovered but `context deadline exceeded` (DOWN)

```
Get "http://172.31.x.x:9100/metrics": context deadline exceeded
```

**Cause**: Prometheus is using the **private IP** but the Monitor server is outside the VPC.  
**Fix**: Switch relabel from `__meta_ec2_private_ip` → `__meta_ec2_public_ip`:

```yaml
relabel_configs:
  # If Monitor is OUTSIDE the VPC (different network/on-prem)
  - source_labels: [__meta_ec2_public_ip]
    regex: '(.+)'
    replacement: '$1:9100'
    target_label: __address__

  # If Monitor is INSIDE the same VPC
  - source_labels: [__meta_ec2_private_ip]
    regex: '(.+)'
    replacement: '$1:9100'
    target_label: __address__
```

### EC2 SD: targets DOWN with `connection refused`

```
Get "http://54.x.x.x:9100/metrics": dial tcp: connect: connection refused
```

**Cause**: Public IP is reachable but node_exporter is not running on the target.  
**Fix**: SSH into the EC2 instance and start the client stack (see Part 3).

Also check the instance's **security group** allows inbound on the required ports.

### Multiple instances with same `instance` label

If you accidentally tagged multiple instances with the same `Name` tag, they'll all appear as the same instance in Grafana and metrics will conflict.

```bash
# Remove Scrape tag from instances you don't want to monitor
aws ec2 delete-tags \
  --resources <instance-id-1> <instance-id-2> \
  --tags Key=Scrape

# Rename an instance
aws ec2 create-tags \
  --resources <instance-id> \
  --tags Key=Name,Value=aws-node-02
```

### Prometheus config duplicated / crash-looping (exit code 2)

```
yaml: unmarshal errors: line 224: field global already set in type config.plain
```

**Cause**: The full config file was appended to itself (git conflict or manual edit gone wrong).  
**Fix**: Truncate the file to the first valid copy:

```bash
# Find where the duplicate starts
grep -n "^global:" prometheus/prometheus.yml
# E.g. output: 1:global:  and  224:global:
# Keep only the first copy:
head -n 219 prometheus/prometheus.yml > /tmp/prom.yml && mv /tmp/prom.yml prometheus/prometheus.yml

# Reload
curl -sf -XPOST http://localhost:9090/-/reload
```

### Check IAM permissions

```bash
# Verify your identity
aws sts get-caller-identity

# Test S3 access
aws s3 ls s3://my-loki-logs-prod-janak0ff/ && echo "✅ S3 OK" || echo "❌ S3 DENIED"

# Test EC2 describe access
aws ec2 describe-instances --max-results 1 --query 'Reservations[0].Instances[0].InstanceId' --output text \
  && echo "✅ EC2 OK" || echo "❌ EC2 DENIED"
```

> **AWS Academy note**: You are an assumed role (`voclabs`), not an IAM user. `aws iam get-user` will fail — this is expected. The role already has broad S3 and EC2 permissions. No policy attachment needed.
