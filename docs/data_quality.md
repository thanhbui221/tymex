# Data Quality

Profiled against the actual source CSVs: 100k customers, 140k product enrollments, 243k CRM interactions, 887k transactions.

Full profiling notebook: [`databricks-scripts/data_quality.py`](../databricks-scripts/data_quality.py)

---

## 1. Tests Implemented and Their Purpose

Tests are defined in three `schema.yml` files (one per layer) plus three custom SQL tests under `tests/`. All tests run with `store_failures: true` — failures are written to a dbt audit table in Databricks and queryable without re-running the pipeline.

### Bronze layer

Purpose: catch bad source data before any transformation runs.

| Model | Column | Test | Guards against |
|---|---|---|---|
| `bronze_customer_raw` | `customer_id` | `unique` + `not_null` | Duplicate or missing PKs from the source CRM |
| | `email` | `not_null` | Missing emails that break downstream deduplication checks |
| | `gender` | `accepted_values` (`Male`, `Female`) | Unexpected enum values that would silently pass through to gold |
| | `_ingested_at` | `not_null` | NULL watermark — incremental models would reprocess everything on the next run |
| `bronze_product_enrollments` | `product_id` | `unique` + `not_null` | Duplicate enrollment records inflating product counts |
| | `customer_id` | `not_null` + `relationships → bronze_customer_raw` | Orphan enrollments for unknown customers |
| | `product_type` | `not_null` + `accepted_values` (`Savings`, `Credit Card`) | Unknown types silently dropped from credit card / savings breakdowns in silver |
| | `_ingested_at` | `not_null` | NULL watermark |
| `bronze_crm_interactions` | `interaction_id` | `unique` + `not_null` | Duplicate interaction records inflating interaction counts |
| | `customer_id` | `not_null` + `relationships → bronze_customer_raw` | Orphan interactions skewing `days_since_last_interaction` |
| | `interaction_type` | `not_null` + `accepted_values` (`Email`, `Chat`, `Call`) | Unknown types silently missing from channel breakdowns |
| | `_ingested_at` | `not_null` | NULL watermark |
| `bronze_transaction_history` | `transaction_id` | `unique` + `not_null` | Duplicate transaction records inflating totals |
| | `customer_id` | `not_null` + `relationships → bronze_customer_raw` | Orphan transactions |
| | `product_id` | `not_null` + `relationships → bronze_product_enrollments` | NULL product_id breaks the JOIN in `silver_customer_transactions` — credit card / savings breakdowns would be wrong |
| | `_ingested_at` | `not_null` | NULL watermark |

### Silver layer

Purpose: enforce one-row-per-customer grain and referential integrity after aggregation.

| Model | Column | Test | Guards against |
|---|---|---|---|
| `silver_customers` | `customer_id` | `unique` + `not_null` | Duplicates here fan out into wrong counts in gold |
| | `email` | `unique` + `not_null` | Flags suspicious merges; failures stored in audit table for investigation (see Issue 2) |
| | `first_name`, `last_name`, `age`, `days_since_signup` | `not_null` | Core demographics — NULL here propagates directly to gold |
| `silver_customer_products` | `customer_id` | `unique` + `not_null` + `relationships → silver_customers` | Grain check; no products for unknown customers |
| | `total_products`, `credit_card_count`, `savings_count` | `not_null` | Aggregated counts must always resolve |
| `silver_customer_interactions` | `customer_id` | `unique` + `not_null` + `relationships → silver_customers` | Grain check |
| | `total_interactions`, `last_interaction_date` | `not_null` | Used in `customer_status` — NULL breaks the 90-day activity check |
| `silver_customer_transactions` | `customer_id` | `unique` + `not_null` + `relationships → silver_customers` | Grain check |
| | `total_transactions`, `last_transaction_date` | `not_null` | Used in `customer_status` |

### Gold layer

Purpose: validate completeness and correctness of the final reporting table.

| Column | Test | Guards against |
|---|---|---|
| `customer_id` | `unique` + `not_null` + `relationships → silver_customers` | Every customer in silver must appear exactly once in gold |
| `first_name`, `last_name`, `email`, `age`, `days_since_signup` | `not_null` | Mandatory demographics must survive the JOIN |
| `total_products`, `total_interactions`, `total_transactions` | `not_null` | COALESCE'd to 0 in gold — NULL here means the COALESCE failed |
| `customer_status` | `not_null` + `accepted_values` (`Active`, `Inactive`) | Segmentation must always resolve to a known value |
| `customer_segment` | `not_null` + `accepted_values` (`Premium`, `Standard`, `Basic`) | Unknown segments would break BI filters and dashboards |

### Custom business rule tests (`tests/`)

Purpose: verify that business logic is correctly implemented, not just that columns are populated. These tests fail if any rows are returned.

**`assert_active_customers_have_recent_activity`**
- Selects any customer where `customer_status = 'Active'` but both `days_since_last_interaction > 90` (or NULL) and `days_since_last_transaction > 90` (or NULL).
- Guards against a regression in the `customer_status` logic — a customer with no recent activity must never be marked Active.

**`assert_premium_customers_meet_criteria`**
- Selects any customer where `customer_segment = 'Premium'` but `total_products < 3` or `total_transaction_value <= 100,000`.
- Guards against a regression in the segmentation logic — Premium must require both conditions simultaneously.

**`assert_no_negative_counts`**
- Selects any customer where `age`, `days_since_signup`, `total_products`, `total_interactions`, `total_transactions`, `credit_card_count`, or `savings_count` is negative.
- Guards against bad DATEDIFF results (e.g. future dates in source), sign inversion bugs, or aggregation errors producing impossible counts.

---

## 2. Known Data Quality Issues

### Issue 1 — Timezone-Naive Timestamps `[HIGH]`

**Finding:** All 886,971 `transaction_date` values carry no timezone indicator (e.g. `2025-06-10 12:20:06`). Source timezone is unknown.

**Impact on business metrics:**
- `days_since_last_transaction` — if source is UTC+8 and Databricks cluster runs UTC, a transaction at `2025-06-10 23:30` local time is recorded as `2025-06-10 15:30 UTC`, shifting the date and potentially moving a customer across the 90-day active window.
- `customer_status` (Active/Inactive) — customers near the 90-day boundary could be misclassified, inflating or deflating the active customer count.
- All `days_since_*` calculations in silver and gold layers are affected.

**Remediation:**
1. Confirm source system timezone with data engineering / source system owners.
2. Standardise all timestamps to UTC at ingestion in `ingest_bronze.py` using `CONVERT_TIMEZONE`.
3. Update silver models to cast `transaction_date` to DATE before diff calculations to eliminate sub-day timezone drift.
4. Document confirmed timezone in `sources.yml` as a metadata field.

---

### Issue 2 — Duplicate Emails in `customer_raw` `[MEDIUM]`

**Finding:** 3 email addresses are each shared by 2 distinct customers (6 rows total). These are different people — different names, genders, dates of birth, and phone numbers. Example: `adavis24144@gmail.com` is shared by Ashley Davis (F, born 1997) and Aaron Davis (M, born 1962).

**Impact on business metrics:**
- Email-based deduplication or customer matching downstream will incorrectly merge these customers, collapsing their separate product holdings, transactions, and interaction histories into one record.
- Marketing campaigns targeting by email will reach the wrong person for at least one of the two customers.
- `customer_segment` and `customer_status` of a merged record would be incorrect — e.g. a Basic customer could appear Premium if their twin's transactions are combined.

**Remediation:**
1. Raise with source system (CRM) team to correct the duplicate email entries.
2. In the interim, `silver_customers` has a `unique` test with `store_failures: true` — failing rows are written to the dbt audit table and queryable for investigation.
3. Do not deduplicate by email — `customer_id` is the true PK and both customers are valid.

---

### Issue 3 — `'Call'` Interaction Type Unhandled in Silver `[MEDIUM]`

**Finding:** `crm_interactions.interaction_type` contains three values: Chat (65%), Email (25%), Call (10%). `silver_customer_interactions` only breaks down `Email` and `Chat` — `Call` interactions are not counted in any breakdown column.

**Impact on business metrics:**
- `total_interactions` is correct (counts all rows regardless of type).
- There is no `call_interactions` column — 10% of interaction volume is invisible in channel reporting.
- Customers who only contacted the bank via phone will show `email_interactions = 0` and `chat_interactions = 0`, giving a false impression of zero channel-specific engagement.

**Remediation:**
1. Add `call_interactions` column to `silver_customer_interactions` and propagate to `customer_360`.
2. Consider a more flexible pattern (pivot macro or dynamic `COUNT(CASE WHEN)` per type) so new interaction types don't require model changes.

---

### Issue 4 — High Rate of Negative Closing Balances `[MEDIUM]`

**Finding:** 59.1% of transactions (524,585 / 886,971) have a negative `closing_balance`. Range: -822,708 to +144,706.

**Impact on business metrics:**
- `min_balance` in `silver_customer_transactions` will be deeply negative for most customers — limited usefulness as a metric if overdraft is the norm.
- Risk/credit scoring downstream would be significantly affected if negative balance is misread as a data error rather than legitimate overdraft.

**Remediation:**
1. Confirm with source system whether negative closing balance represents overdraft (expected) or a loading error.
2. If overdraft is expected, document it and consider adding a `max_overdraft_amount` metric to the gold layer.
3. If it is a data error, investigate the ingestion pipeline for sign inversion bugs.

---

### Issue 5 — ~1,120 Non-Standard Phone Numbers `[LOW]`

**Finding:** 1,120 phone numbers (1.1%) are neither `09...` (local format) nor `+63...` (international Philippines format).

**Impact on business metrics:**
- No direct impact on current metrics — phone is not used in any calculation.
- If phone format is used downstream for SMS campaigns or customer location inference, these records would fail formatting validation.

**Remediation:**
1. Investigate the 1,120 records — likely a mix of international customers or data entry errors.
2. Add a stricter normalisation step in `silver_customers` if phone format becomes a reporting or operational requirement.

---

### Issue 6 — Coverage Gaps (Customers with No Activity) `[LOW / EXPECTED]`

**Finding:** 27,385 customers (27.4%) have no CRM history; 23,120 customers (23.1%) have no transaction history.

**Impact on business metrics:**
- `last_interaction_date` and `last_transaction_date` are NULL for these customers.
- NULL values evaluate as false in the 90-day active window, so these customers are correctly classified as `Inactive`.
- `total_interactions` and `total_transactions` are COALESCE'd to 0 — aggregate metrics are not skewed.
- A customer with no transactions and no CRM history will always be `Basic` regardless of product count — this may warrant a separate `Dormant` segment.

**Remediation:**
1. Confirm with business whether "enrolled but never transacted" customers should be a distinct segment (e.g. `Dormant`) separate from `Inactive`.
2. No data fix required — this reflects real customer behaviour; NULL handling is correct in current models.

---

## 3. Assumptions and Limitations

### Assumptions

| # | Assumption | Basis |
|---|---|---|
| 1 | `customer_id` is the true primary key for customers — email is not unique per customer | Confirmed by Issue 2: 3 duplicate emails map to different people |
| 2 | `product_type` values are case-insensitive; canonical forms are `'Credit Card'` and `'Savings'` | `accepted_values` test enforces this at bronze; silver uses `UPPER(TRIM(...))` for defensive matching |
| 3 | A customer is Active if they have any interaction OR transaction within 90 days | Business definition; 90 days = one calendar quarter |
| 4 | `transaction_amount` sign convention: positive = credit (money in), negative = debit (money out) | Derived from field name and confirmed by `debit_count` / `credit_count` logic in silver |
| 5 | Negative `closing_balance` represents a legitimate overdraft, not a data error | Assumed pending confirmation from source system team (see Issue 4) |
| 6 | Source timezone for `transaction_date` matches the Databricks cluster timezone | Unconfirmed — treat all `days_since_*` calculations as approximate until resolved (see Issue 1) |
| 7 | Bronze ingestion is a one-time manual seed for this implementation; production would use continuous ingestion | Documented in `design_decisions.md` Section 6 |

### Limitations

| # | Limitation | Impact |
|---|---|---|
| 1 | No `call_interactions` breakdown | 10% of CRM interaction volume is invisible in channel reporting (see Issue 3) |
| 2 | `customer_status` and `days_since_*` metrics are timezone-sensitive | Customers near the 90-day boundary may be misclassified until Issue 1 is resolved |
| 3 | No `Dormant` segment | Customers with products but zero activity are lumped into `Basic` or `Inactive` — may not reflect business intent |
| 4 | `silver_customers` and `silver_customer_products` are full-refresh — no historical snapshots | Point-in-time customer demographics or product history cannot be reconstructed from the current model |
| 5 | `assert_no_negative_counts` does not cover `days_since_last_interaction` or `days_since_last_transaction` | These could go negative if source timestamps are in the future; not currently tested |

---

## Clean Areas

| Dimension | Finding |
|-----------|---------|
| Completeness | No null values in any field across all four source tables |
| PK Uniqueness | No duplicate primary keys anywhere |
| Referential Integrity | All `customer_id` and `product_id` FK relationships resolve cleanly |
| Outliers | No statistical outliers in `transaction_amount` (0 rows beyond 3σ) |
| Age validity | Range 18–66, no underage customers |
| Credit limits | No negative credit limits |
