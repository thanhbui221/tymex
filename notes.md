# Customer 360 — Setup Playbook

End-to-end guide for getting the full pipeline running from scratch. Follow steps in order.

---

## Prerequisites

Install these before starting:

```bash
# Terraform
brew install hashicorp/tap/terraform

# Databricks CLI
brew tap databricks/tap && brew install databricks

# dbt
pip install dbt-databricks
```

You also need:
- A Databricks workspace (see Step 1)
- A personal access token (generated inside Databricks — used in Steps 2, 4, and 5)

---

## Step 1 — Get Databricks Access

**Community Edition (free, sufficient for this case study):**
1. Sign up at https://community.cloud.databricks.com/
2. Verify email and log in
3. Note your workspace URL (e.g. `https://dbc-xxxxx.cloud.databricks.com`)

**Generate a personal access token:**
- Click profile icon → **User Settings** → **Developer** → **Access Tokens** → **Generate New Token**
- Save it — you'll use it in every step below

---

## Step 2 — Deploy Foundation Infrastructure

Creates the Databricks cluster, SQL Warehouse, and `customer_360_db` schema.

```bash
cd terraform/databricks-foundation
cp terraform.tfvars.example terraform.tfvars  # if present, or create manually
```

Edit `terraform.tfvars`:
```hcl
databricks_host  = "https://your-workspace.cloud.databricks.com"
databricks_token = "dapi..."
```

Deploy:
```bash
terraform init
terraform plan
terraform apply
```

Capture outputs — you'll need these in Step 5:
```bash
terraform output cluster_id
terraform output sql_warehouse_id
```

> Full details: [`terraform/databricks-foundation/README.md`](terraform/databricks-foundation/README.md)

---

## Step 3 — Load Raw Data (One-time Seed)

Uploads the CSV files from `./data/` to your Databricks workspace and creates the raw Delta tables.

### 3a. Upload CSVs to workspace

```bash
# Create workspace directory
databricks workspace mkdirs /Users/<your-email>/customer_360

# Upload source files
databricks workspace import /Users/<your-email>/customer_360/customer_raw.csv \
  --file ./data/customer_raw.csv --format RAW --overwrite

databricks workspace import /Users/<your-email>/customer_360/product_enrollments.csv \
  --file ./data/product_enrollments.csv --format RAW --overwrite

databricks workspace import /Users/<your-email>/customer_360/crm_interactions.csv \
  --file ./data/crm_interactions.csv --format RAW --overwrite

# transaction_history is large — upload in chunks
for file in data/split_transaction_history/*.csv; do
  filename=$(basename "$file")
  databricks workspace import /Users/<your-email>/customer_360/transaction_history/$filename \
    --file "$file" --format RAW --overwrite
done
```

> The split files in `data/split_transaction_history/` were pre-generated (200k rows each).
> To re-split from the original: `awk 'NR==1{h=$0;next} (NR-2)%200000==0{if(o)close(o); o=sprintf("data/split_transaction_history/transaction_history_%03d.csv",++i); print h>o} {print>o}' data/transaction_history.csv`

### 3b. Run the ingestion notebook

The foundation terraform (Step 2) already created the notebook at:
`/Workspace/Users/thanhbui22198@gmail.com/customer_360/ingest_bronze`

Open it in Databricks and run it. It reads the CSVs from the workspace path above and writes them as Delta tables into `customer_360_db`:

- `customer_360_db.customer_raw`
- `customer_360_db.product_enrollments`
- `customer_360_db.crm_interactions`
- `customer_360_db.transaction_history`

---

## Step 4 — Set Up and Run dbt

### 4a. Configure connection

Create `~/.dbt/profiles.yml`:

```yaml
customer_360:
  target: dev
  outputs:
    dev:
      type: databricks
      host: <server-hostname>         # Compute → Cluster → Advanced Options → JDBC/ODBC
      http_path: <http-path>          # same location
      token: <personal-access-token>
      schema: customer_360_db
      threads: 4
```

Verify:
```bash
cd customer_360
dbt debug   # should print "All checks passed!"
```

### 4b. Run transformations

```bash
# First run (builds all layers)
dbt build

# Incremental updates (subsequent runs)
dbt build --select silver_customer_interactions silver_customer_transactions customer_360

# Run tests
dbt test

# Browse docs and lineage
dbt docs generate && dbt docs serve   # opens http://localhost:8080
```

> Full model details and materialization strategy: [`customer_360/README.md`](customer_360/README.md)

---

## Step 5 — Deploy Workflows (Scheduled Automation)

Sets up four Databricks jobs that keep the gold table current:
- **Hourly (every hour except 2 AM)** — incremental merge of interactions and transactions; full refresh of customer_360. The 2 AM run is intentionally skipped here and triggered by the daily job instead (see below), so the 2 AM gold build always runs on freshly rebuilt dimensions.
- **Daily (2 AM UTC)** — full refresh of slow-changing dimensions (silver_customers, silver_customer_products); OPTIMIZE of incremental silver tables to compact the day's small files; drop stale dbt audit tables to prevent Unity Catalog table quota exhaustion; then triggers the hourly pipeline (`run_job_task`) once dimensions are fresh, enforcing daily→hourly ordering at 2 AM
- **Weekly (Sun 3 AM UTC)** — OPTIMIZE + VACUUM on all tables; VACUUM is critical for customer_360 to purge stale file versions left by hourly full refreshes
- **Backfill (manual trigger only)** — windowed or full reprocess for schema changes, bug fixes, or business rule updates

### 5a. Upload helper scripts to Workspace

DBFS root is disabled on this workspace (Unity Catalog security default) — use `databricks workspace import` instead of `databricks fs cp`:

```bash
databricks workspace mkdirs /Workspace/Shared/dbt/customer_360/maintenance

databricks workspace import --file databricks-scripts/run_dbt.py \
  --format SOURCE --language PYTHON --overwrite \
  /Workspace/Shared/dbt/customer_360/run_dbt.py

databricks workspace import --file databricks-scripts/maintenance/optimize_tables.py \
  --format SOURCE --language PYTHON --overwrite \
  /Workspace/Shared/dbt/customer_360/maintenance/optimize_tables.py

databricks workspace import --file databricks-scripts/maintenance/vacuum_tables.py \
  --format SOURCE --language PYTHON --overwrite \
  /Workspace/Shared/dbt/customer_360/maintenance/vacuum_tables.py

databricks workspace import --file databricks-scripts/maintenance/cleanup_audit_tables.py \
  --format SOURCE --language PYTHON --overwrite \
  /Workspace/Shared/dbt/customer_360/maintenance/cleanup_audit_tables.py
```

### 5b. Deploy

```bash
cd terraform/databricks-workflows
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with the values captured from Step 2:
```hcl
databricks_host      = "https://your-workspace.cloud.databricks.com"
databricks_token     = "dapi..."
cluster_id           = "<from Step 2>"
sql_warehouse_id     = "<from Step 2>"
notification_emails  = ["your-email@example.com"]
```

```bash
terraform init
terraform plan
terraform apply
```

> Full details including monitoring and troubleshooting: [`terraform/databricks-workflows/README.md`](terraform/databricks-workflows/README.md)

---

## Step 6 — Verify

Run this in Databricks SQL Editor to confirm the gold table is populated:

```sql
USE customer_360_db;

SELECT customer_status, customer_segment, COUNT(*) AS customer_count
FROM customer_360
GROUP BY customer_status, customer_segment
ORDER BY 1, 2;
```

Expected: rows for Active/Inactive × Premium/Standard/Basic.

---

## Assumptions & Open Questions

**Timezone (unresolved)**
- Raw `transaction_date` timestamps (e.g. `2025-06-10 12:20:06`) have no timezone indicator.
- **Current assumption**: all timestamps are UTC.
- **Risk**: the 90-day active customer window and all `days_since_*` calculations will be wrong if the source emits local time.
- **Action needed**: confirm timezone with source system owners before production use.

**Phone number format**
- Mixed formats (`09...` vs `+63...`) suggest possible multi-country data or inconsistent entry.
- `silver_customers` strips to digits only; no timezone derivation is attempted from phone.

**Email uniqueness**
- One email assumed per customer. Enforced via dbt `unique` test on `bronze_customer_raw`. Violations should be investigated and resolved upstream.

**Bronze layer ingestion (case study vs production)**
- The current implementation treats ingestion as a one-time manual seed (Step 3).
- In production this is not the case — each source table should have a continuous ingestion pattern appropriate to its source system: batch, streaming, near real-time, or micro-batch.
- The bronze models and ingestion scripts would need to be redesigned once source system details are confirmed (e.g. does the CRM expose a Kafka topic or a REST API? Is the transaction system CDC-enabled? What is the SLA for each feed?).
- Until those details are known, the ingestion layer should be treated as a placeholder.
