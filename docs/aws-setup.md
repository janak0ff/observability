
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
  --resources i-XXXXXXXXXXXXXXXXX \
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

Uncomment the EC2 SD blocks in `server/prometheus/prometheus.yml` (lines 139–219).

Remove the `#` prefix from these two job blocks:

```yaml
  - job_name: 'ec2-sd-node-exporter'
    ec2_sd_configs:
      - region: ${AWS_EC2_SD_REGION}
        access_key: ${AWS_EC2_SD_ACCESS_KEY_ID}
        secret_key: ${AWS_EC2_SD_SECRET_ACCESS_KEY}
        port: 9100
        refresh_interval: 60s
        filters:
          - name: tag:Scrape
            values: ['true']
          - name: instance-state-name
            values: ['running']
    relabel_configs:
      - source_labels: [__meta_ec2_private_ip]
        regex: '(.*)'
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
      - region: ${AWS_EC2_SD_REGION}
        access_key: ${AWS_EC2_SD_ACCESS_KEY_ID}
        secret_key: ${AWS_EC2_SD_SECRET_ACCESS_KEY}
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
      - source_labels: [__meta_ec2_private_ip]
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

### Step 4 — Reload Prometheus

```bash
# Hot-reload (no restart needed)
curl -sf -XPOST http://localhost:9090/-/reload

# Or via docker compose
docker compose --env-file .env-cloud up -d prometheus
```

### Step 5 — Verify EC2 SD in Prometheus UI

Open: `http://<server-ip>:9090/service-discovery`

You should see `ec2-sd-node-exporter` and `ec2-sd-alloy` jobs with your instances listed, and labels like `__meta_ec2_tag_Name`, `__meta_ec2_private_ip`, etc.

Check `http://<server-ip>:9090/targets` — EC2 instances tagged with `Scrape=true` should appear as **UP**.

---

## Troubleshooting

### Loki S3 errors

```bash
docker compose logs loki 2>&1 | grep -i "error\|s3\|denied"
```

Common causes:
- `AccessDenied` — IAM credentials lack `s3:PutObject` / `s3:GetObject` on the bucket
- `NoSuchBucket` — bucket name in `.env-cloud` doesn't match created bucket
- Session token expired (AWS Academy credentials last ~4 hours)

### EC2 SD not discovering instances

```bash
docker compose logs prometheus 2>&1 | grep -i "ec2\|error"
```

Common causes:
- Missing `ec2:DescribeInstances` IAM permission
- Instances not tagged with `Scrape=true`
- Wrong region in `AWS_EC2_SD_REGION`
- Instances use private IPs — Prometheus server must be in the same VPC, or use public IPs

### Check IAM permissions

```bash
aws iam simulate-principal-policy \
  --policy-source-arn $(aws sts get-caller-identity --query Arn --output text) \
  --action-names s3:PutObject s3:GetObject ec2:DescribeInstances \
  --resource-arns "arn:aws:s3:::my-loki-logs-prod-janak0ff/*" "arn:aws:ec2:us-east-1:*:instance/*"
```
