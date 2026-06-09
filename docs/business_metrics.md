# Business Metrics

Full SQL implementation: [`customer_360/models/`](../customer_360/models/)
Design decisions behind the modeling approach: [`design_decisions.md`](design_decisions.md)

---

## Active Customer

| | |
|---|---|
| **Definition** | Customer with at least one CRM interaction **or** financial transaction in the past 90 days |
| **Field** | `customer_status` = `'Active'` / `'Inactive'` |
| **Logic** | `days_since_last_interaction <= 90 OR days_since_last_transaction <= 90` |
| **Rationale** | 90 days = one quarter; a customer engaging at least once per quarter is considered retained |
| **Edge case** | No interactions AND no transactions → both fields are NULL → treated as Inactive |

---

## Customer Segmentation

| Segment | Criteria | Rationale |
|---------|----------|-----------|
| `Premium` | `has_credit_card = true` AND `total_transaction_value >= 100,000` | Credit card holders with high transaction activity — highest-value relationship type |
| `Standard` | `is_multi_product = true` (2+ products of any type) | Multi-product customers with growth potential, regardless of transaction volume |
| `Basic` | All others | New or single-product customers |

Rules are evaluated top-down; a customer meeting Premium criteria is not re-evaluated for Standard.

**Edge case**: A customer with a credit card but low transaction activity (`total_transaction_value < 100,000`) falls into Standard. `total_transaction_value` is the sum of absolute transaction amounts — always >= 0, representing activity volume. `net_transaction_amount` (signed sum) can be negative but is not used in segmentation. See [Transaction Metrics](#transaction-metrics) for the distinction.

---

## Product Metrics

Calculated in [`silver_customer_products.sql`](../customer_360/models/silver/silver_customer_products.sql), propagated to gold.

| Metric | Calculation | Rationale | Notes |
|--------|-------------|-----------|-------|
| `total_products` | COUNT(*) of enrollments per customer | Measures depth of banking relationship; drives `is_multi_product` flag and Standard segment | COALESCE to 0 in gold |
| `credit_card_count` | COUNT of enrollments where `product_type = 'Credit Card'` | Enables `has_credit_card` flag used in Premium segmentation | Case-insensitive match |
| `savings_count` | COUNT of enrollments where `product_type = 'Savings'` | Enables `has_savings` flag; savings customers have different transaction behaviour from card-only customers | Case-insensitive match |
| `max_credit_limit` | MAX(limit) across credit card enrollments | Denominator for `credit_card_spend_to_limit_ratio`; MAX chosen over SUM because limits are per-product caps, not additive | NULL for customers with no credit card; 0.0 for savings-only |
| `first_product_date` | MIN(enrollment_date) | Marks the start of the product relationship; used alongside `signup_date` to measure time-to-first-product | Earliest enrollment across all product types |
| `latest_product_date` | MAX(enrollment_date) | Recency-of-product signal; a recent acquisition suggests an active cross-sell motion | Most recent enrollment across all product types |

**Edge cases:**
- A customer enrolled in the same `product_id` more than once (e.g. re-opened account) will be counted multiple times in `total_products` and type-specific counts. Deduplication is not applied at the silver layer — raw enrollment count is the intended measure of activity.
- `max_credit_limit` is NULL (not 0) for savings-only customers to distinguish "no credit card" from "credit card with zero limit." Downstream fields that use it as a denominator (e.g. `credit_card_spend_to_limit_ratio`) handle NULL explicitly.
- `product_type` values not matching `'Credit Card'` or `'Savings'` (e.g. a new product category) are silently excluded from type-specific counts but included in `total_products`. New product types require a schema change to surface their metrics.

---

## Transaction Metrics

Calculated in [`silver_customer_transactions.sql`](../customer_360/models/silver/silver_customer_transactions.sql), propagated to gold.

| Metric | Calculation | Notes |
|--------|-------------|-------|
| `total_transactions` | COUNT(*) | COALESCE to 0 in gold |
| `debit_count` | COUNT where transaction_amount < 0 | |
| `credit_count` | COUNT where transaction_amount > 0 | |
| `total_transaction_value` | SUM(ABS(transaction_amount)) | Always >= 0 — represents total activity volume, not net position |
| `net_transaction_amount` | SUM(transaction_amount) | Signed sum — positive = net inflow, negative = net outflow |
| `avg_transaction_value` | AVG(ABS(transaction_amount)) | Average absolute transaction size; always >= 0 |
| `max_balance` / `min_balance` | MAX/MIN(closing_balance) | Range of account balance experienced |
| `current_balance` | MAX_BY(closing_balance, transaction_date) | Balance at the most recent transaction; NULL for customers with no transactions |
| `last_transaction_date` | MAX(transaction_date) | Most recent financial activity |
| `days_since_last_transaction` | DATEDIFF(DAY, last_transaction_date, CURRENT_DATE()) | Used in active customer definition |
| `credit_card_transaction_value` | SUM(ABS(transaction_amount)) where product_type = 'CREDIT CARD' | Activity volume on credit card products; resolved via JOIN to bronze_product_enrollments; COALESCE to 0 in gold |
| `savings_transaction_value` | SUM(ABS(transaction_amount)) where product_type = 'SAVINGS' | Activity volume on savings products; COALESCE to 0 in gold |
| `credit_card_net_transaction_amount` | SUM(transaction_amount) where product_type = 'CREDIT CARD' | Net signed flow on credit card products |
| `savings_net_transaction_amount` | SUM(transaction_amount) where product_type = 'SAVINGS' | Net signed flow on savings products |
| `credit_card_transaction_count` | COUNT where product_type = 'CREDIT CARD' | COALESCE to 0 in gold |
| `savings_transaction_count` | COUNT where product_type = 'SAVINGS' | COALESCE to 0 in gold |

**Absolute vs net**: `*_transaction_value` fields use `SUM(ABS(...))` — always >= 0, representing gross activity volume. A customer who deposits and withdraws 50k each has a `total_transaction_value` of 100k. The corresponding net fields (`net_transaction_amount`, `credit_card_net_transaction_amount`, `savings_net_transaction_amount`) use signed sums and can be negative. Use `debit_count` / `credit_count` alongside net values to detect high-churn accounts.

---

## Interaction Metrics

Calculated in [`silver_customer_interactions.sql`](../customer_360/models/silver/silver_customer_interactions.sql), propagated to gold.

| Metric | Calculation | Rationale | Notes |
|--------|-------------|-----------|-------|
| `total_interactions` | COUNT(*) | Overall engagement volume; used alongside transaction activity in the active customer definition | COALESCE to 0 in gold |
| `email_interactions` | COUNT where interaction_type = 'EMAIL' | Channel breakdown enables preference-based communication routing | Case-insensitive; COALESCE to 0 in gold |
| `chat_interactions` | COUNT where interaction_type = 'CHAT' | Chat-heavy customers may prefer self-service; useful for digital engagement scoring | Case-insensitive; COALESCE to 0 in gold |
| `call_interactions` | COUNT where interaction_type = 'CALL' | High call volume can indicate unresolved issues or complex needs; input for support cost analysis | Case-insensitive; COALESCE to 0 in gold |
| `last_interaction_date` | MAX(interaction_date) | Recency anchor for the 90-day active window | Most recent CRM contact |
| `last_interaction_type` | MAX_BY(interaction_type, interaction_date) | Captures the customer's last known channel preference | Uppercased; NULL for customers with no interactions |
| `days_since_last_interaction` | DATEDIFF(DAY, last_interaction_date, CURRENT_DATE()) | Half of the two-signal active customer definition | NULL for customers with no interactions; evaluated as Inactive when NULL |

**Edge cases:**
- `interaction_type` values not matching `'EMAIL'`, `'CHAT'`, or `'CALL'` (e.g. `'SMS'`, `'IN_BRANCH'`) are counted in `total_interactions` but excluded from all channel-specific counts. New channels require a schema change to be tracked individually.
- `days_since_last_interaction` is NULL for customers with no CRM records. In the active customer definition this is treated as "no recent interaction" — the customer can still be Active via `days_since_last_transaction`.
- If two interactions share the exact same `interaction_date`, `MAX_BY` returns one deterministically but the choice is arbitrary. This edge case is uncommon and does not affect any aggregated counts.

---

## Derived Metrics

Computed directly in [`customer_360.sql`](../customer_360/models/gold/customer_360.sql) from upstream silver columns.

### Credit Utilization

| | |
|---|---|
| **Definition** | How much of a customer's credit limit has been consumed by credit card transaction activity |
| **Field** | `credit_card_spend_to_limit_ratio` (decimal ratio, e.g. 0.75 = 75%) |
| **Calculation** | `credit_card_transaction_value / max_credit_limit` |
| **Rationale** | Key risk and cross-sell signal — high ratio signals heavy card usage relative to limit |
| **Edge case** | NULL when `max_credit_limit` is 0 or NULL (savings-only customers). `credit_card_transaction_value` is already an absolute sum — no ABS() needed |

### Monthly Transaction Frequency

| | |
|---|---|
| **Definition** | Transaction volume normalised to a 30-day window, allowing comparison across customers of different tenures |
| **Field** | `monthly_transaction_frequency` |
| **Calculation** | `total_transactions * 30.0 / days_since_signup` |
| **Rationale** | Raw counts favour long-tenured customers; frequency makes segments comparable |
| **Edge case** | NULL for day-0 customers (`days_since_signup = 0`) to avoid division by zero |

### Customer Lifecycle Stage

| | |
|---|---|
| **Definition** | Tenure bucket based on days since signup |
| **Field** | `customer_lifecycle_stage` |
| **Calculation** | `days_since_signup < 90` → New; `< 365` → Growing; `< 1095` → Established; else → Mature |
| **Rationale** | Complements Active/Inactive status — separates "new and quiet" (expected) from "established and inactive" (churn risk) |
| **Edge case** | Evaluated from `days_since_signup`, which is recalculated on every refresh, so stage advances automatically without a backfill |

### Product Penetration Flags

| Metric | Calculation | Rationale |
|--------|-------------|-----------|
| `has_credit_card` | `credit_card_count > 0` | Binary flag for cross-sell and segmentation filters |
| `has_savings` | `savings_count > 0` | Binary flag for cross-sell and segmentation filters |
| `is_multi_product` | `total_products >= 2` | Mirrors the Standard segment criterion; useful as a standalone boolean for dashboards |

---

## Demographic Metrics

Calculated in [`silver_customers.sql`](../customer_360/models/silver/silver_customers.sql), propagated to gold.

| Metric | Calculation | Rationale | Notes |
|--------|-------------|-----------|-------|
| `age` | DATEDIFF(YEAR, date_of_birth, CURRENT_DATE()) | Age-based segmentation and regulatory compliance (e.g. product eligibility); recalculated on every full refresh so no backfill is needed as customers age | Recalculated on each full refresh; YEAR-level precision (not exact birthday) |
| `days_since_signup` | DATEDIFF(DAY, signup_date, CURRENT_DATE()) | Denominator for `monthly_transaction_frequency` and input to `customer_lifecycle_stage`; recalculated on each refresh so lifecycle stage advances automatically | Recalculated on each full refresh |
| `mobile_clean` | REGEXP_REPLACE(mobile, '[^0-9]', '') | Normalises mobile numbers for downstream deduplication and outreach systems that require digits-only format | Strips all non-numeric characters; ~1.1% of records have non-standard formatting |

**Edge cases:**
- `age` uses year-level precision — a customer whose birthday is later in the current year is counted as one year younger than their true age until the birthday passes. This is acceptable for segmentation but should not be used for exact age-gating without a day-level check.
- `days_since_signup` will be 0 for customers who signed up today and negative if `signup_date` is in the future (data quality issue). `monthly_transaction_frequency` guards against the zero case by returning NULL; negative values indicate dirty source data and are caught by the `assert_no_negative_counts` test.
- `mobile_clean` can produce an empty string (`''`) if the raw value contains only formatting characters. Downstream consumers should treat empty string the same as NULL.
