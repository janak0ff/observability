# AWS Setup Guide

This guide covers two powerful AWS integrations available for the observability stack:
1. **S3 Bucket** — Persistent object storage for Loki logs.
2. **EC2 Service Discovery** — Automatic Prometheus scraping of EC2 instances via resource tags.

> **Prerequisites**: AWS CLI installed and configured on your Server instance (or local machine working with AWS).
> Verify your current authentication context with: `aws sts get-caller-identity`

---

## Part 1: IAM Policies & Permissions

Before enabling either integration, ensure your IAM user/role has the correct permissions attached. 

### Required Actions

| Integration | Required Policy Actions |
|---|---|
| Loki S3 storage | `s3:PutObject`, `s3:GetObject`, `s3:DeleteObject`, `s3:ListBucket`, `s3:GetBucketLocation` |
| EC2 Service Discovery | `ec2:DescribeInstances`, `ec2:DescribeAvailabilityZones`, `ec2:DescribeTags` |

### Option A: Standard AWS Account
If you are authenticated as a real IAM user, create and attach an inline policy granting access to your specific S3 bucket and EC2 read resources.

```bash
# Replace with your IAM Username
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
        "arn:aws:s3:::<YOUR-BUCKET-NAME>",
        "arn:aws:s3:::<YOUR-BUCKET-NAME>/*"
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
```

### Option B: AWS Academy / Vocareum (Assumed Role)

If you are using an AWS Academy lab session, you are utilizing an assumed role (`voclabs`). **The `voclabs` Lab role already has full S3 and EC2 permissions pre-attached.** You do *not* need to attach any custom policies. 

Verify access directly:
```bash
# Test S3 access
aws s3 ls 2>&1 && echo "✅ S3 access OK" || echo "❌ S3 access DENIED"

# Test EC2 access
aws ec2 describe-instances --max-results 1 --query 'Reservations[0].Instances[0].InstanceId' --output text \
  && echo "✅ EC2 access OK" || echo "❌ EC2 access DENIED"
```

---

## Part 2: Loki S3 Storage Setup

By default, Loki stores logs on the local filesystem (`/loki/chunks`). Switching to S3 gives you persistent, scalable storage that survives Docker container rebuilds and volume wipes.

### Step 2.1 — Create the S3 Bucket

Bucket names must be globally unique across all of AWS. Replace `<YOUR-BUCKET-NAME>` with your unique identifier.
```bash
# Create the bucket
aws s3api create-bucket \
  --bucket <YOUR-BUCKET-NAME> \
  --region us-east-1

# Optional but Recommended: Set S3 Lifecycle Policy (Auto-delete logs older than 30 days)
aws s3api put-bucket-lifecycle-configuration \
  --bucket <YOUR-BUCKET-NAME> \
  --lifecycle-configuration '{
    "Rules": [{
      "ID": "loki-log-expiry",
      "Status": "Enabled",
      "Filter": {"Prefix": ""},
      "Expiration": {"Days": 30}
    }]
  }'
```

### Step 2.2 — Configure `.env` on your Server

Navigate to your server directory and edit your environment variables (`.env`).
```env
# Switch Loki from filesystem to S3
LOKI_STORAGE_TYPE=s3

# Match the bucket name you created
LOKI_BUCKET_NAME=<YOUR-BUCKET-NAME>

# AWS credentials
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=<your-access-key-id>
AWS_SECRET_ACCESS_KEY=<your-secret-access-key>
```

> **AWS Academy Note:** Session credentials expire every 4 hours. You must continuously update your `.env` with a fresh `AWS_SESSION_TOKEN`.
> 
> Add it to your `.env`:
> `AWS_SESSION_TOKEN=<your-session-token>`

### Step 2.3 — Restart Loki
```bash
# Recreate the container to pass new environment variables
docker compose up -d loki

# Verify logs
docker compose logs loki --tail=30
```
Check the S3 bucket using the AWS console or CLI in ~5-10 minutes. You should notice `index/` and `chunks/` prefixes populated with binary data.

---

## Part 3: EC2 Service Discovery for Prometheus

EC2 Service Discovery allows Prometheus to automatically add client nodes to its scraping targets dynamically using AWS instance tags, avoiding the need for `clients.json` management.

### Step 3.1 — Tag Your EC2 Instances

Find your EC2 instance ID and apply the required Tags. Set these tags for **every EC2 client node** you intend to monitor.

| Tag Key | Tag Value | Description |
|---|---|---|
| `Scrape` | `true` | Opts this instance into Prometheus scraping. |
| `Name` | e.g. `aws-node-01` | Used as the `instance` label. |
| `Job` | e.g. `node_exporter` | Used as the `job` label snippet. |
| `Environment` | e.g. `production` | Used as the `environment` label. |

You can tag via the AWS UI, or the CLI:
```bash
aws ec2 create-tags \
  --resources i-XXXXXXXXXXXXXXX \
  --tags \
    Key=Scrape,Value=true \
    Key=Name,Value=aws-node-01 \
    Key=Job,Value=node_exporter \
    Key=Environment,Value=production
```

### Step 3.2 — Configure `.env` for Prometheus Discovery

Prometheus' configuration (`prometheus.yml`) is already set up to perform EC2 Service Discovery looking for the `Scrape=true` tag. 

However, Prometheus requires standard AWS credentials populated in its environment to query the AWS API. Ensure these are set in your `.env` file (the same ones utilized for Loki optionally):

```env
# Standard AWS SDK variables mapped to the Prometheus container
AWS_EC2_SD_REGION=us-east-1
AWS_EC2_SD_ACCESS_KEY_ID=<your-access-key-id>
AWS_EC2_SD_SECRET_ACCESS_KEY=<your-secret-access-key>
# Include AWS_SESSION_TOKEN if using AWS Academy
```

### Step 3.3 — Reload and Verify

Because we altered the credentials provided to the container, restart the Prometheus service:
```bash
docker compose up -d prometheus
```

**Verify the UI:**
1. Open the Service Discovery page: `http://<SERVER-IP>:9090/service-discovery`
2. You will see definitions for `ec2-sd-node-exporter` and `ec2-sd-alloy`. You should observe your instance IP populated.
3. Open `http://<SERVER-IP>:9090/targets` to verify the state transitions to `UP`.

### Troubleshooting EC2 SD: 'Context Deadline Exceeded'
If targets are discovered but remain in a `DOWN` state reading `Get http://<ip>:9100/metrics: context deadline exceeded`:
It indicates Prometheus is attempting to route to the private VPC IP of the instance, but the Monitor Server is outside that VPC. You must adjust the relabel configuration in `server/prometheus/prometheus.yml` to track public IPs.

```yaml
# In prometheus/prometheus.yml -> ec2_sd_configs -> relabel_configs
- source_labels: [__meta_ec2_public_ip]    # Switch this from __meta_ec2_private_ip
  regex: '(.+)'
  replacement: '$1:9100'
  target_label: __address__
```

Reload Prometheus to apply modifications:
```bash
curl -XPOST http://localhost:9090/-/reload
```
