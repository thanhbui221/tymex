# Databricks Terraform - Separated Infrastructure

## Structure

```
terraform/
├── databricks-foundation/     # Deploy FIRST (foundational resources)
│   ├── provider.tf
│   ├── variables.tf
│   ├── cluster.tf
│   ├── schema.tf
│   └── outputs.tf
│
└── databricks-workflows/      # Deploy SECOND (operational jobs)
    ├── provider.tf
    ├── variables.tf
    ├── workflow_daily_dimensions.tf
    ├── workflow_hourly_incremental.tf
    ├── workflow_weekly_maintenance.tf
    ├── monitoring.tf
    └── outputs.tf
```

## Why Separated?

- **Different lifecycles**: Foundation changes rarely, workflows change often
- **Risk isolation**: Workflow updates won't risk recreating clusters
- **Team ownership**: Platform owns foundation, data team owns workflows
- **State safety**: Isolated blast radius per module

## Deployment Steps

### Step 1: Deploy Foundation

```bash
cd terraform/databricks-foundation

# Create terraform.tfvars
cat > terraform.tfvars <<EOF
databricks_host  = "https://your-workspace.cloud.databricks.com"
databricks_token = "your-token-here"
EOF

# Initialize and apply
terraform init
terraform plan
terraform apply

# Capture outputs
terraform output cluster_id
terraform output sql_warehouse_id
```

### Step 2: Deploy Workflows

```bash
cd ../databricks-workflows

# Create terraform.tfvars using foundation outputs
cat > terraform.tfvars <<EOF
databricks_host     = "https://your-workspace.cloud.databricks.com"
databricks_token    = "your-token-here"
cluster_id          = "<from foundation output>"
sql_warehouse_id    = "<from foundation output>"
dbt_project_path    = "/dbfs/dbt/customer_360"
notification_emails = ["your-email@example.com"]
EOF

# Initialize and apply
terraform init
terraform plan
terraform apply
```

## Workflow Wiring

Workflows consume foundation outputs:

```hcl
# Foundation creates and outputs
output "cluster_id" {
  value = databricks_cluster.customer_360_cluster.id
}

# Workflows consume as variable
variable "cluster_id" {
  type = string
}

# Used in workflow tasks
existing_cluster_id = var.cluster_id
```

## Updating Infrastructure

**Foundation updates** (rare):
```bash
cd terraform/databricks-foundation
terraform apply
```

**Workflow updates** (frequent):
```bash
cd terraform/databricks-workflows
terraform apply
```

Each module has its own state file - changes are isolated.
