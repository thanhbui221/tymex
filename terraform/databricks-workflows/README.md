# Customer 360 - Databricks Workflows (Terraform)

Production-grade orchestration for the Customer 360 dbt project using Databricks Workflows.

## Overview

This Terraform configuration automates:

1. **Daily refresh** - Slow-changing dimensions (customers, products)
2. **Hourly refresh** - Incremental models (interactions, transactions, customer_360)
3. **Weekly maintenance** - OPTIMIZE and VACUUM Delta tables
4. **Monitoring** - Job duration alerts and row count tracking

## Architecture

```
Workflows:
├── Daily (2 AM UTC)
│   ├── silver_customers (full refresh)
│   ├── silver_customer_products (full refresh)
│   └── data quality tests
│
├── Hourly (every hour)
│   ├── silver_customer_interactions (incremental)
│   ├── silver_customer_transactions (incremental)
│   ├── customer_360 (incremental)
│   └── data quality tests
│
└── Weekly (Sunday 3 AM UTC)
    ├── OPTIMIZE tables (interactions, transactions, customer_360)
    └── VACUUM old files (7-day retention)

Monitoring:
├── Job duration alerts (> 60 min)
└── Row count monitoring (detect drops)
```

## Prerequisites

1. **Databricks Workspace** (Community Edition or paid tier)
2. **Existing Databricks Cluster** (for running dbt jobs)
3. **SQL Warehouse** (for monitoring queries)
4. **dbt Project** deployed to DBFS at `/dbfs/dbt/customer_360`
5. **Terraform** installed locally (`brew install terraform`)

## Setup

### 1. Upload Helper Scripts to DBFS

Upload the maintenance scripts to Databricks:

```bash
# Upload dbt runner
databricks fs cp ../../databricks-scripts/run_dbt.py dbfs:/dbt/customer_360/run_dbt.py

# Upload maintenance scripts
databricks fs cp ../../databricks-scripts/maintenance/optimize_tables.py dbfs:/dbt/customer_360/maintenance/optimize_tables.py
databricks fs cp ../../databricks-scripts/maintenance/vacuum_tables.py dbfs:/dbt/customer_360/maintenance/vacuum_tables.py
```

### 2. Get Required IDs from Databricks

**Cluster ID:**
- Go to **Compute** → Click your cluster
- Copy the cluster ID from the URL: `https://.../#setting/clusters/YOUR-CLUSTER-ID/configuration`

**SQL Warehouse ID:**
- Go to **SQL Warehouses**
- Click your warehouse
- Copy the ID from the URL

**Access Token:**
- Click profile icon → **User Settings** → **Developer** → **Access Tokens**
- Generate new token and save it securely

### 3. Configure Terraform Variables

```bash
# Copy example file
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
nano terraform.tfvars
```

Fill in your actual values:
```hcl
databricks_host      = "https://your-workspace.cloud.databricks.com"
databricks_token     = "dapi..."
cluster_id           = "1234-567890-abcdef12"
sql_warehouse_id     = "abcdef1234567890"
notification_emails  = ["your-email@company.com"]
```

### 4. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Preview changes
terraform plan

# Deploy workflows
terraform apply
```

## Usage

### View Deployed Workflows

After deployment, get workflow URLs:

```bash
terraform output workflow_urls
```

Or view in Databricks:
- Go to **Workflows** → **Jobs**
- Look for jobs starting with "Customer360"

### Manual Workflow Trigger

To test a workflow before schedule:

```bash
# Get job ID
terraform output daily_workflow_id

# Trigger in Databricks UI: Workflows → Jobs → [Job Name] → Run Now
```

### Verify Workflows

Check that workflows are scheduled:

1. **Daily Dimensions Refresh**: 2 AM UTC daily
2. **Hourly Incremental Refresh**: Every hour
3. **Weekly Maintenance**: Sunday 3 AM UTC

## Monitoring

### Job Duration Tracking

The monitoring configuration tracks job execution times:
- **Alert threshold**: Jobs running > 60 minutes
- **Location**: Databricks SQL → Queries → "Customer360 - Job Duration Monitor"

### Row Count Monitoring

Tracks row counts across all tables to detect anomalies:
- **Alert**: Row count drops below expected minimum
- **Location**: Databricks SQL → Queries → "Customer360 - Row Count Monitor"

### Email Alerts

Configured email notifications for:
- ✉️ Job failures (immediate)
- ✉️ Long-running jobs (> 60 min)
- ✉️ Row count anomalies

## Troubleshooting

**"Cluster not found"**
- Verify cluster_id in terraform.tfvars
- Ensure cluster is running or has auto-start enabled

**"Path does not exist: /dbfs/dbt/customer_360"**
- Upload dbt project and helper scripts first (see Setup step 1)

**"SQL Warehouse not accessible"**
- Verify sql_warehouse_id in terraform.tfvars
- Start the SQL Warehouse in Databricks

**Job fails with "dbt command not found"**
- Install dbt in cluster libraries: Compute → Cluster → Libraries → Install New → PyPI → `dbt-databricks`

## Maintenance

**Adjusting schedules:**

Edit the cron expressions in workflow files:
- Daily: `workflow_daily_dimensions.tf` line 6
- Hourly: `workflow_hourly_incremental.tf` line 6
- Weekly: `workflow_weekly_maintenance.tf` line 6

Then run `terraform apply` to update.

**Cleanup:**

```bash
# Remove all workflows
terraform destroy
```

## Files Structure

```
terraform/databricks-workflows/
├── provider.tf                     # Databricks provider config
├── variables.tf                    # Input variables
├── terraform.tfvars.example        # Example values
├── workflow_daily_dimensions.tf    # Daily slow-changing refresh
├── workflow_hourly_incremental.tf  # Hourly incremental refresh
├── workflow_weekly_maintenance.tf  # Weekly OPTIMIZE/VACUUM
├── monitoring.tf                   # Alerts and metrics
├── outputs.tf                      # Workflow IDs and URLs
└── README.md                       # This file
```

## Production Checklist

- [ ] Helper scripts uploaded to DBFS
- [ ] terraform.tfvars configured with actual values
- [ ] Cluster has dbt-databricks installed
- [ ] SQL Warehouse is running
- [ ] Email notifications configured
- [ ] Test manual run of each workflow
- [ ] Verify alerts are working
- [ ] Document on-call procedures

---

**Support:** For issues, check Databricks job run logs: Workflows → Jobs → [Job Name] → Runs → [Run] → View Logs
