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
| `customer_status` | `not_null` + `accepted_values` (`Never Active`, `Active`, `At Risk`, `Dormant`) | Segmentation must always resolve to a known value |
| `customer_segment` | `not_null` + `accepted_values` (`Premium`, `Standard`, `Basic`) | Unknown segments would break BI filters and dashboards |

### Custom business rule tests (`tests/`)

Purpose: verify that business logic is correctly implemented, not just that columns are populated. dbt's built-in tests (`unique`, `not_null`, `accepted_values`) check column-level properties — they cannot express cross-column or cross-table business rules. These tests fill that gap. They fail if any rows are returned. Tests are split by layer and run as dedicated tasks in the pipeline — bronze tests gate silver builds, silver tests gate the gold build, gold tests run last.

**Bronze** (`test_bronze` task)

**`assert_transaction_product_customer_match`**
- **What it checks**: Returns any transaction where the `product_id` either doesn't exist in `bronze_product_enrollments` (`p.customer_id IS NULL`) or belongs to a different customer (`t.customer_id <> p.customer_id`). Test passes when zero rows are returned.
- **Why needed**: A transaction row has both a `customer_id` and a `product_id`. The bronze `relationships` test on `product_id` only confirms the product *exists* — it cannot confirm the product belongs to the *same customer*. If customer A has a transaction on a product enrolled to customer B, the silver model would silently attribute customer B's credit card activity to customer A when joining on `product_id`. The bronze FK test would pass and never catch it.

**Silver** (`test_silver` task)

**`assert_customer_360_transaction_values_consistent`**
- **What it checks**: Returns any customer in `silver_customer_transactions` where `round(total_transaction_value, 2) <> round(total_debit_value + total_credit_value, 2)`. Test passes when zero rows are returned.
- **Why needed**: `total_transaction_value = SUM(ABS(amount))`, `total_debit_value = SUM(ABS(amount)) WHERE amount < 0`, `total_credit_value = SUM(ABS(amount)) WHERE amount > 0` — mathematically, `total` must equal `debit + credit`. If a CASE condition is wrong or zero-amount transactions are handled differently, all three columns can be individually non-null and `accepted_values`-clean while their relationship is broken. No built-in test can express "column A must equal column B + column C".

**Gold** (`test_gold` task)

**`assert_active_customers_have_recent_activity`**
- **What it checks**: Returns any customer from `customer_360` that hits one of three contradiction cases: (1) `customer_status = 'Active'` but `last_activity_date IS NULL`, `days_since_last_activity > 90`, or `is_active_customer <> true`; (2) `is_active_customer = true` but `last_activity_date IS NULL`, `days_since_last_activity > 90`, or `customer_status <> 'Active'`; (3) `customer_status = 'Never Active'` but `last_activity_date IS NOT NULL`. Test passes when zero rows are returned.
- **Why needed**: `customer_status`, `is_active_customer`, and `last_activity_date` are three separate derived fields that must be internally consistent. A `not_null` or `accepted_values` test on each individually would pass even if they contradict each other — e.g. `customer_status = 'Active'` but `is_active_customer = false`. If the 90-day threshold logic is ever edited incorrectly, this test catches the regression before it reaches BI consumers.

**`assert_premium_customers_meet_criteria`**
- **What it checks**: Returns any customer from `customer_360` where `customer_segment = 'Premium'` but either `has_credit_card <> true` or `total_transaction_value < 100,000`. Test passes when zero rows are returned.
- **Why needed**: The `accepted_values` test confirms `customer_segment` is always one of `Premium/Standard/Basic` — but cannot verify that the right customers landed in the right bucket. If the CASE evaluation order is broken (e.g. Standard evaluated before Premium), a high-value credit card holder would be misclassified as Standard and the schema test would never flag it. This test directly audits the segmentation rule itself.

**`assert_no_negative_counts`**
- **What it checks**: Returns any customer from `customer_360` where any of these 19 columns is negative: `age`, `days_since_signup`, `days_since_last_activity`, `total_products`, `credit_card_count`, `savings_count`, `total_interactions`, `email_interactions`, `chat_interactions`, `call_interactions`, `total_transactions`, `debit_count`, `credit_count`, `total_transaction_value`, `total_debit_value`, `total_credit_value`, `credit_card_transaction_value`, `savings_transaction_value`, `credit_card_transaction_count`. Test passes when zero rows are returned.
- **Why needed**: Counts and durations are physically impossible to be negative, but `not_null` passes for `-5`. They can go negative due to future dates in source data (`days_since_signup` negative if `signup_date > CURRENT_DATE`), a sign inversion bug in aggregation, or a DATEDIFF direction flip. This test adds the lower-bound constraint that `not_null` cannot express, and serves as an early warning for dirty source data before it silently distorts downstream metrics.

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

### Issue 3 — High Rate of Negative Closing Balances `[MEDIUM]`

**Finding:** 59.1% of transactions (524,585 / 886,971) have a negative `closing_balance`. Range: -822,708 to +144,706.

**Impact on business metrics:**
- `min_balance` in `silver_customer_transactions` will be deeply negative for most customers — limited usefulness as a metric if overdraft is the norm.
- Risk/credit scoring downstream would be significantly affected if negative balance is misread as a data error rather than legitimate overdraft.

**Remediation:**
1. Confirm with source system whether negative closing balance represents overdraft (expected) or a loading error.
2. If overdraft is expected, document it and consider adding a `max_overdraft_amount` metric to the gold layer.
3. If it is a data error, investigate the ingestion pipeline for sign inversion bugs.

---

### Issue 4 — ~1,120 Non-Standard Phone Numbers `[MEDIUM]`

**Finding:** 1,120 phone numbers (1.1%) are neither `09...` (local format) nor `+63...` (international Philippines format).

**Impact on business metrics:**
- No direct impact on current metrics — phone is not used in any calculation.
- If phone format is used downstream for SMS campaigns or customer location inference, these records would fail formatting validation.

**Remediation:**
1. Investigate the 1,120 records — likely a mix of international customers or data entry errors.
2. Add a stricter normalisation step in `silver_customers` if phone format becomes a reporting or operational requirement.

---

### Issue 5 — Coverage Gaps (Customers with No Activity) `[LOW / EXPECTED]`

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

### Issue 6 — `mobile_clean` Empty String Not Tested `[LOW]`

**Finding:** `silver_customers.mobile_clean` strips all non-numeric characters via `REGEXP_REPLACE(mobile, '[^0-9]', '')`. If the raw value contains only formatting characters (e.g. `+`, `-`, spaces), the output is an empty string (`''`) rather than NULL. Approximately 1.1% of records have non-standard mobile formatting and are candidates for this edge case.

**Impact on business metrics:**
- No impact on current metrics — `mobile_clean` is not used in any aggregation or segmentation logic.
- Downstream outreach systems that guard against NULL with `IS NOT NULL` will receive an empty string and attempt contact on a blank number, causing silent delivery failures.

**Remediation:**
1. Add an `expression_is_true` test on `silver_customers.mobile_clean: "mobile_clean != ''"` (or a custom singular test).
2. Consider converting empty strings to NULL at source: `NULLIF(REGEXP_REPLACE(mobile, '[^0-9]', ''), '')` in `silver_customers.sql`.

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
| 1 | `customer_status` and `days_since_*` metrics are timezone-sensitive | Customers near the 90-day / 180-day boundary may be misclassified until Issue 1 is resolved |
| 2 | `silver_customers` and `silver_customer_products` are full-refresh — no historical snapshots | Point-in-time customer demographics or product history cannot be reconstructed from the current model |
| 3 | `assert_no_negative_counts` does not cover `days_since_last_interaction` or `days_since_last_transaction` | These could go negative if source timestamps are in the future; not currently tested |
| 4 | `mobile_clean` empty string not tested | Downstream outreach systems using `IS NOT NULL` will receive a blank number and fail silently (see Issue 7) |

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
