# Business Logic & Design Decisions

> This file is an index. Each topic is covered in a dedicated doc below.

| Requirement | Document |
|-------------|----------|
| Data Model Design (ERD, schemas, grain) | [`data_model_design.md`](data_model_design.md) |
| Data Lineage (flow, source-to-target, dependencies) | [`data_lineage.md`](data_lineage.md) · [`data_lineage.svg`](data_lineage.svg) |
| Data Quality (tests, findings, impact, remediation) | [`data_quality.md`](data_quality.md) |
| Business Metrics (definitions, rationale, edge cases) | [`business_metrics.md`](business_metrics.md) |
| Design Decisions (architecture, trade-offs, performance) | [`design_decisions.md`](design_decisions.md) · [`clustering_comparison.md`](clustering_comparison.md) |

---

## Layer Grain & Cardinality

| Layer | Model | Grain | Cardinality |
|-------|-------|-------|-------------|
| Bronze | `bronze_customer_raw` | 1 row per customer | = source |
| Bronze | `bronze_product_enrollments` | 1 row per product enrollment | many per customer |
| Bronze | `bronze_crm_interactions` | 1 row per CRM interaction | many per customer |
| Bronze | `bronze_transaction_history` | 1 row per financial transaction | highest volume, many per customer per product |
| Silver | `silver_customers` | 1 row per customer | = bronze_customer_raw |
| Silver | `silver_customer_products` | 1 row per customer (aggregated) | ≤ bronze_customer_raw |
| Silver | `silver_customer_interactions` | 1 row per customer (aggregated) | ≤ bronze_crm_interactions |
| Silver | `silver_customer_transactions` | 1 row per customer (aggregated) | ≤ bronze_transaction_history (+ LEFT JOIN bronze_product_enrollments) |
| Gold | `customer_360` | 1 row per customer | = silver_customers |

Bronze uses `LEFT JOIN` at the gold layer so every customer in `silver_customers` appears in `customer_360`, even if they have no products, interactions, or transactions.

---

## Business Metric Definitions

### Active Customer

| | |
|---|---|
| **Definition** | Customer status based on recency of last CRM interaction or financial transaction |
| **Field** | `customer_status` = `'Never Active'` / `'Active'` / `'At Risk'` / `'Dormant'` |
| **Boolean** | `is_active_customer` = TRUE when `customer_status = 'Active'` |
| **Logic** | No activity ever → `'Never Active'`; last activity ≤ 90 days → `'Active'`; ≤ 180 days → `'At Risk'`; else → `'Dormant'` |
| **Rationale** | 90 days = one quarter (retained); 180 days = two quarters (at-risk before churn action); beyond = dormant |
| **Edge case** | Customer with no interactions AND no transactions → `last_activity_date` is NULL → `'Never Active'` |

### Customer Segmentation

| Segment | Criteria | Rationale |
|---------|----------|-----------|
| `Premium` | `has_credit_card = true` AND `total_transaction_value >= 100,000` | Credit card holders with high transaction activity — highest-value relationship type |
| `Standard` | `is_multi_product = true` (2+ products of any type) | Multi-product customers with growth potential, regardless of transaction volume |
| `Basic` | All others | New or single-product customers |

Rules are evaluated top-down; a customer meeting Premium criteria is not re-evaluated for Standard.

**Edge case**: A customer with a credit card but low transaction activity (`total_transaction_value < 100,000`) falls into Standard, not Premium. `total_transaction_value` is the sum of absolute transaction amounts — it is always >= 0 and represents activity volume, not net position. `net_transaction_amount` (signed sum) can be negative but is not used in segmentation.

**Why `total_transaction_value` and not `net_transaction_amount` for the Premium threshold**: `total_transaction_value` captures throughput — a customer who moves 200k through their account is treated as high-value even if debits and credits roughly cancel out. Using `net_transaction_amount` would penalise active credit card spenders (net debit position) and reward passive savers with a single large deposit, which does not reflect engagement. `net_transaction_amount` is more appropriate for liquidity or risk analysis. If the business intent is specifically to reward net depositors, an additional condition on `net_transaction_amount > 0` could be added — confirm with business stakeholders.

### Customer Value Segment

| Segment | Criteria | Rationale |
|---------|----------|-----------|
| `High Value` | `total_transaction_value >= 150,000` | Top-tier activity volume |
| `Medium Value` | `total_transaction_value >= 50,000` | Mid-tier activity volume |
| `Low Value` | `total_transaction_value > 0` | Some activity but below medium threshold |
| `No Transaction` | `total_transaction_value = 0` | No recorded financial activity |

Field: `customer_value_segment`. Evaluated from `total_transaction_value` (absolute sum). Thresholds are configurable via dbt vars (`high_value_transaction_threshold`, `medium_value_transaction_threshold`).

### Engagement Segment

| Segment | Criteria | Rationale |
|---------|----------|-----------|
| `Highly Engaged` | `total_interactions >= 10` | Frequent CRM contact — active service relationship |
| `Moderately Engaged` | `total_interactions >= 3` | Regular but not frequent contact |
| `Low Engagement` | `total_interactions > 0` | Some CRM history |
| `No CRM Engagement` | `total_interactions = 0` | No recorded CRM interactions |

Field: `engagement_segment`. Thresholds configurable via `highly_engaged_interaction_threshold`, `moderately_engaged_interaction_threshold`.

### Product Metrics

| Metric | Calculation | Notes |
|--------|-------------|-------|
| `total_products` | COUNT(*) of enrollments per customer | COALESCE to 0 in gold for customers with no enrollments |
| `credit_card_count` | COUNT of enrollments where product_type = 'CREDIT CARD' | Case-insensitive match |
| `savings_count` | COUNT of enrollments where product_type = 'SAVINGS' | Case-insensitive match |
| `max_credit_limit` | MAX(limit) across credit card enrollments | NULL for customers with no credit card; 0.0 for savings-only |
| `total_credit_limit` | SUM(limit) across credit card enrollments | 0 for customers with no credit card |
| `first_product_date` | MIN(enrollment_date) | Earliest product relationship with the bank |
| `latest_product_date` | MAX(enrollment_date) | Most recent product enrollment |
| `product_segment` | Derived from `has_credit_card` and `has_savings` | `'Savings + Credit Card'`, `'Credit Card Only'`, `'Savings Only'`, `'No Product'` |

### Transaction Metrics

| Metric | Calculation | Notes |
|--------|-------------|-------|
| `total_transactions` | COUNT(*) | COALESCE to 0 in gold |
| `total_transaction_value` | SUM(ABS(transaction_amount)) | Always >= 0; represents activity volume, not net position |
| `net_transaction_amount` | SUM(transaction_amount) | Signed sum — positive = net inflow, negative = net outflow |
| `avg_transaction_value` | AVG(ABS(transaction_amount)) | Always >= 0 |
| `max_balance` / `min_balance` | MAX/MIN(closing_balance) | Range of account balance experienced |
| `last_transaction_date` | MAX(transaction_date) | Most recent financial activity |
| `days_since_last_transaction` | DATEDIFF(DAY, last_transaction_date, CURRENT_DATE()) | Used in active customer definition |
| `first_transaction_date` | MIN(transaction_date) | Earliest financial activity |
| `credit_card_transaction_value` | SUM(ABS(amount)) where product_type = 'CREDIT CARD' | Resolved via JOIN to bronze_product_enrollments |
| `savings_transaction_value` | SUM(ABS(amount)) where product_type = 'SAVINGS' | Resolved via JOIN to bronze_product_enrollments |

### Interaction Metrics

| Metric | Calculation | Notes |
|--------|-------------|-------|
| `total_interactions` | COUNT(*) | COALESCE to 0 in gold |
| `email_interactions` | COUNT where interaction_type = 'EMAIL' | Case-insensitive |
| `chat_interactions` | COUNT where interaction_type = 'CHAT' | Case-insensitive |
| `call_interactions` | COUNT where interaction_type = 'CALL' | Case-insensitive |
| `first_interaction_date` | MIN(interaction_date) | Earliest CRM contact |
| `last_interaction_date` | MAX(interaction_date) | Most recent CRM contact |
| `last_interaction_type` | MAX_BY(interaction_type, STRUCT(interaction_date, interaction_id)) | Channel of most recent interaction; same-day ties broken deterministically by interaction_id |
| `days_since_last_interaction` | DATEDIFF(DAY, last_interaction_date, CURRENT_DATE()) | Used in active customer definition |

---

## Design Decisions

### Medallion Architecture (Bronze → Silver → Gold)

Bronze models are thin views directly over raw source tables — no transformation, just a stable contract so downstream models aren't coupled to raw table names. Silver models clean, standardise, and aggregate to one row per customer. Gold joins all silver models into the final reporting table.

**Trade-off**: An extra layer adds query hops, but it isolates concerns — if a source table is renamed, only the bronze model changes.

### Incremental Materialization

`silver_customer_interactions` and `silver_customer_transactions` are incremental (merge on `customer_id`). `customer_360` is a full-refresh table — it is rebuilt on every run by joining all silver models. `silver_customers` and `silver_customer_products` are also full-refresh tables because the source data is relatively small and slow-changing.

Incremental models use `_ingested_at` as the watermark rather than the business timestamp (`interaction_date`, `transaction_date`). This avoids reprocessing issues caused by late-arriving records or timezone ambiguity in business timestamps.

**Gold layer uses two separate watermarks** (`_interactions_ingested_at`, `_transactions_ingested_at`) to avoid cross-contamination — a new batch of transactions should not force reprocessing of the entire customer set just because the interaction watermark hasn't advanced.

### Clustering Strategy

The incremental silver tables (`silver_customer_interactions`, `silver_customer_transactions`) use Liquid Clustering on `customer_id`. This improves hourly MERGE performance (cluster key matches the merge key) and the gold full-refresh join. The gold table does not use Liquid Clustering — it is a full refresh that rewrites all files each run, so clustering provides no benefit at current scale. See [`clustering_comparison.md`](clustering_comparison.md) and [`design_decisions.md`](design_decisions.md) §4 for detail.

### Bronze Sources per Silver Model

Most silver models source from exactly one bronze model. The exception is `silver_customer_transactions`, which LEFT JOINs `bronze_product_enrollments` on `product_id` to resolve product-type breakdowns (credit card vs savings transaction values and counts). All other cross-model joins happen only at the gold layer on `customer_id`. See [`design_decisions.md`](design_decisions.md).

