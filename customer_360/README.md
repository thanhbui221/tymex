# customer_360 — dbt Project

dbt transformations for the Customer 360 data mart. Implements a medallion architecture (Bronze → Silver → Gold) on Databricks.

## Project Structure

```
customer_360/
├── dbt_project.yml
└── models/
    ├── bronze/
    │   ├── sources.yml                      # Source freshness config
    │   ├── schema.yml                       # Bronze-layer tests
    │   ├── bronze_customer_raw.sql
    │   ├── bronze_product_enrollments.sql
    │   ├── bronze_crm_transactions.sql
    │   └── bronze_transaction_history.sql
    ├── silver/
    │   ├── silver_customers.sql             # Cleaned demographics (table)
    │   ├── silver_customer_products.sql     # Aggregated product holdings (table)
    │   ├── silver_customer_interactions.sql # Aggregated CRM metrics (incremental)
    │   └── silver_customer_transactions.sql # Aggregated tx metrics (incremental)
    └── gold/
        └── customer_360.sql                 # Unified customer view (incremental)
```

## Materialization Strategy

| Model | Materialization | Reason |
|-------|----------------|--------|
| `bronze_*` | view | Pass-through from raw source; no storage cost |
| `silver_customers` | table | Slow-changing, full refresh acceptable |
| `silver_customer_products` | table | Slow-changing, full refresh acceptable |
| `silver_customer_interactions` | incremental (merge) | High-volume events; only process new rows |
| `silver_customer_transactions` | incremental (merge) | High-volume events; only process new rows |
| `customer_360` | incremental (merge) | Recalculate only customers with upstream changes |

## Setup

### 1. Install dbt-databricks

```bash
pip install dbt-databricks
```

### 2. Configure `~/.dbt/profiles.yml`

```yaml
customer_360:
  target: dev
  outputs:
    dev:
      type: databricks
      host: <server-hostname>         # From Compute → Cluster → JDBC/ODBC
      http_path: <http-path>          # From Compute → Cluster → JDBC/ODBC
      token: <personal-access-token>  # From User Settings → Developer → Access Tokens
      schema: customer_360_db
      threads: 4
```

### 3. Verify connection

```bash
dbt debug
```

## Running

```bash
# Build all models
dbt run

# Build a specific layer
dbt run --select bronze.*
dbt run --select silver.*
dbt run --select gold.*

# Full refresh (ignore incremental state)
dbt run --full-refresh

# Run tests
dbt test

# Generate and serve docs
dbt docs generate && dbt docs serve
```

## Data Quality Tests

Bronze layer validates raw source integrity (not_null, unique on primary keys, referential integrity between `transaction_history` and `product_enrollments`). Source freshness alerts after 24h (warn) / 48h (error).

See `models/bronze/schema.yml` for test definitions.

## Business Logic

**Active Customer**: interaction or transaction within 90 days.

**Customer Segment**:
- `Premium` — 3+ products AND total transaction value > 100,000
- `Standard` — 2+ products
- `Basic` — all others

For full metric definitions, rationale, edge cases, and design decisions see [`docs/business_logic.md`](../docs/business_logic.md).

**Timezone assumption**: all raw timestamps treated as UTC. See [`notes.md`](../notes.md) for open questions.
