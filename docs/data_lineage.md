# Data Lineage

Visual diagram: [`data_lineage.svg`](data_lineage.svg)

The diagram is color-coded by layer (grey = source, orange = bronze, blue = silver, yellow = gold) and shows materialization type and ingestion frequency on each node.

---

## 1. Source-to-Target Mapping

| Source Table | Bronze Model | Silver Model | Gold Model |
|---|---|---|---|
| `customer_raw` | `bronze_customer_raw` | `silver_customers` | `customer_360` |
| `product_enrollments` | `bronze_product_enrollments` | `silver_customer_products` | `customer_360` |
| `crm_interactions` | `bronze_crm_interactions` | `silver_customer_interactions` | `customer_360` |
| `transaction_history` | `bronze_transaction_history` | `silver_customer_transactions` | `customer_360` |

> **Note**: `silver_customer_transactions` is the exception — it joins both `bronze_transaction_history` (primary) and `bronze_product_enrollments` (LEFT JOIN on `product_id`) to resolve product-type breakdowns (credit card vs savings transaction values). All other silver models have exactly one bronze source.

---

## 2. Transformation Flow Per Layer

### Source → Bronze
- No transformation. Bronze models are thin `SELECT *` views over raw Delta tables.
- Adds `_ingested_at` (load timestamp) as a freshness and watermark sentinel.
- Purpose: decouple downstream models from raw table names; if a source table is renamed, only the bronze model changes.

### Bronze → Silver
| Model | Transformation |
|-------|---------------|
| `silver_customers` | TRIM names, LOWER email, strip non-numeric from mobile, derive `age` and `days_since_signup` |
| `silver_customer_products` | GROUP BY customer_id — COUNT, MAX(limit), MIN(enrollment_date) per product type |
| `silver_customer_interactions` | GROUP BY customer_id — COUNT by type, MAX(interaction_date), derive `days_since_last_interaction` |
| `silver_customer_transactions` | GROUP BY customer_id from `bronze_transaction_history` LEFT JOIN `bronze_product_enrollments` — SUM, COUNT, AVG, MAX, MIN; product-type breakdowns resolved via `product_id` FK |

### Silver → Gold
- `customer_360` LEFT JOINs all four silver models on `customer_id`.
- Derives `customer_status` (Active / Inactive) and `customer_segment` (Premium / Standard / Basic).
- COALESCE nulls (customers with no products / interactions / transactions) to 0.

Full business logic for each derived field: [`business_metrics.md`](business_metrics.md)

---

## 3. Model Dependencies

```
bronze_customer_raw
    └── silver_customers
            └── customer_360

bronze_product_enrollments
    ├── silver_customer_products
    │       └── customer_360
    └── silver_customer_transactions (LEFT JOIN on product_id)
            └── customer_360

bronze_crm_interactions
    └── silver_customer_interactions
            └── customer_360

bronze_transaction_history
    └── silver_customer_transactions
            └── customer_360
```

dbt `ref()` calls make these dependencies explicit and enforce execution order. Run `dbt ls --select customer_360+` to see the full DAG.

---

## 4. Incremental Watermarks

Incremental models filter on `_ingested_at` (not the business timestamp) to avoid reprocessing issues from late-arriving records or timezone-ambiguous event times.

| Model | Watermark Column | Strategy |
|-------|-----------------|----------|
| `silver_customer_interactions` | `_ingested_at` | merge on `customer_id` |
| `silver_customer_transactions` | `_ingested_at` | merge on `customer_id` |
| `customer_360` | `_interactions_ingested_at`, `_transactions_ingested_at` | merge on `customer_id` (two independent watermarks) |

The gold layer carries two separate watermarks to avoid cross-contamination — a new batch of transactions should not force reprocessing of all customers just because the interaction watermark hasn't advanced.
