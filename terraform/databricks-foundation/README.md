# Databricks Foundation Infrastructure

Foundational Databricks resources for the Customer 360 project. Deploy this **first** before deploying workflows.

## What This Creates

- **Compute Cluster**: Customer 360 cluster for dbt transformations
- **Database Schema**: `customer_360_db` for all data tables
- **SQL Warehouse**: For monitoring queries and alerts

## Prerequisites

1. Databricks workspace access
2. Personal access token with admin permissions
3. Terraform installed (`brew install terraform`)
4. `~/.databrickscfg` configured:
   ```ini
   [DEFAULT]
   host = https://your-workspace.cloud.databricks.com
   token = your-access-token
   ```

## Input Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `databricks_host` | Workspace URL | Yes |
| `databricks_token` | Personal access token | Yes |

## Outputs

| Output | Description | Used By |
|--------|-------------|---------|
| `cluster_id` | Cluster ID | Workflows module |
| `sql_warehouse_id` | SQL warehouse data source ID | Workflows module |
| `schema_name` | Database schema name | Documentation |

## Deployment

### 1. Create `terraform.tfvars`

```bash
cat > terraform.tfvars <<EOF
databricks_host  = "https://your-workspace.cloud.databricks.com"
databricks_token = "dapi..."
EOF
```

**Important**: Add `terraform.tfvars` to `.gitignore` - contains secrets!

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Review Plan

```bash
terraform plan
```

### 4. Apply

```bash
terraform apply
```

### 5. Capture Outputs

```bash
terraform output cluster_id
terraform output sql_warehouse_id
```

Save these values - you'll need them for the workflows module.

## Resource Configuration

### Cluster Settings
- **Auto-termination**: 20 minutes
- **Workers**: 1 node
- **Spark version**: 13.3.x-scala2.12
- **Node type**: i3.xlarge

### SQL Warehouse Settings
- **Size**: Small
- **Max clusters**: 1
- **Auto-stop**: 20 minutes

## Cost Optimization

- Cluster auto-terminates after 20 minutes of inactivity
- SQL warehouse auto-stops after 20 minutes
- Use Community Edition for development/testing

## Updating

Foundation changes rarely. When needed:

```bash
terraform plan  # Review changes carefully
terraform apply
```

**Warning**: Recreating the cluster will terminate running jobs.

## State Management

- State stored locally by default (`terraform.tfstate`)
- For teams, use remote state (S3, Terraform Cloud)
- Never commit state files to git

## Next Steps

After deployment, proceed to `../databricks-workflows/` and use the output values.
