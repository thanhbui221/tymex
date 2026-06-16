# Business Metrics

Full SQL implementation: [`customer_360/models/`](../customer_360/models/)
Design decisions behind the modeling approach: [`design_decisions.md`](design_decisions.md)

---

## Active Customer

| | |
|---|---|
| **Definition** | Customer status based on recency of last CRM interaction or financial transaction |
| **Field** | `customer_status` = `'Never Active'` / `'Active'` / `'At Risk'` / `'Dormant'` |
| **Boolean** | `is_active_customer` = TRUE when `customer_status = 'Active'` |
| **Logic** | No activity ever → `'Never Active'`; last activity ≤ 90 days → `'Active'`; ≤ 180 days → `'At Risk'`; else → `'Dormant'` |
| **Rationale** | 90 days = one quarter (retained); 180 days = two quarters (at-risk before churn action); beyond = dormant |
| **Edge case** | No interactions AND no transactions → `last_activity_date` is NULL → `'Never Active'` |

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

## Customer Value Segment

| Segment | Criteria | Rationale |
|---------|----------|-----------|
| `High Value` | `total_transaction_value >= 150,000` | Top-tier activity volume |
| `Medium Value` | `total_transaction_value >= 50,000` | Mid-tier activity volume |
| `Low Value` | `total_transaction_value > 0` | Some activity but below medium threshold |
| `No Transaction` | `total_transaction_value = 0` | No recorded financial activity |

Field: `customer_value_segment`. Evaluated from `total_transaction_value` (absolute sum). Thresholds are configurable via dbt vars (`high_value_transaction_threshold: 150,000`, `medium_value_transaction_threshold: 50,000`). Complements `customer_segment` — a Basic customer can still be High Value if they have single-product high throughput.

---

## Engagement Segment

| Segment | Criteria | Rationale |
|---------|----------|-----------|
| `Highly Engaged` | `total_interactions >= 10` | Frequent CRM contact — active service relationship |
| `Moderately Engaged` | `total_interactions >= 3` | Regular but not frequent contact |
| `Low Engagement` | `total_interactions > 0` | Some CRM history |
| `No CRM Engagement` | `total_interactions = 0` | No recorded CRM interactions |

Field: `engagement_segment`. Thresholds configurable via `highly_engaged_interaction_threshold: 10`, `moderately_engaged_interaction_threshold: 3`. High call volume within `Highly Engaged` may indicate unresolved issues — cross-reference `call_interactions` for support cost analysis.

---

## Product Metrics

Calculated in [`silver_customer_products.sql`](../customer_360/models/silver/silver_customer_products.sql), propagated to gold.

| Metric | Calculation | Rationale | Notes |
|--------|-------------|-----------|-------|
| `total_products` | COUNT(*) of enrollments per customer | Measures depth of banking relationship; drives `is_multi_product` flag and Standard segment | COALESCE to 0 in gold |
| `credit_card_count` | COUNT of enrollments where `product_type = 'Credit Card'` | Enables `has_credit_card` flag used in Premium segmentation | Case-insensitive match |
| `savings_count` | COUNT of enrollments where `product_type = 'Savings'` | Enables `has_savings` flag; savings customers have different transaction behaviour from card-only customers | Case-insensitive match |
| `max_credit_limit` | MAX(limit) across credit card enrollments | Denominator for `credit_card_activity_to_limit_ratio`; MAX chosen over SUM because limits are per-product caps, not additive | NULL for customers with no credit card; 0.0 for savings-only |
| `total_credit_limit` | SUM(limit) across credit card enrollments | Sum of all credit limits; 0 for customers with no credit card | Distinct from `max_credit_limit` — useful for customers with multiple cards |
| `first_product_date` | MIN(enrollment_date) | Marks the start of the product relationship; used alongside `signup_date` to measure time-to-first-product | Earliest enrollment across all product types |
| `latest_product_date` | MAX(enrollment_date) | Recency-of-product signal; a recent acquisition suggests an active cross-sell motion | Most recent enrollment across all product types |
| `product_segment` | Derived from `has_credit_card` and `has_savings` | Categorises the product portfolio type; useful for product-mix analysis | `'Savings + Credit Card'`, `'Credit Card Only'`, `'Savings Only'`, `'No Product'` |

**Edge cases:**
- A customer enrolled in the same `product_id` more than once (e.g. re-opened account) will be counted multiple times in `total_products` and type-specific counts. Deduplication is not applied at the silver layer — raw enrollment count is the intended measure of activity.
- `max_credit_limit` is NULL (not 0) for savings-only customers to distinguish "no credit card" from "credit card with zero limit." Downstream fields that use it as a denominator (e.g. `credit_card_spend_to_limit_ratio`) handle NULL explicitly.
- `product_type` values not matching `'Credit Card'` or `'Savings'` (e.g. a new product category) are silently excluded from type-specific counts but included in `total_products`. New product types require a schema change to surface their metrics.

---

## Transaction Metrics

Calculated in [`silver_customer_transactions.sql`](../customer_360/models/silver/silver_customer_transactions.sql), propagated to gold.

| Metric | Calculation | Rationale | Notes |
|--------|-------------|-----------|-------|
| `total_transactions` | COUNT(*) | Overall transaction activity volume; baseline financial engagement signal | COALESCE to 0 in gold |
| `debit_count` | COUNT where transaction_amount < 0 | Spending frequency indicator; used alongside `credit_count` to detect high-churn or net-outflow accounts | |
| `credit_count` | COUNT where transaction_amount > 0 | Inflow frequency indicator; complements `debit_count` for activity pattern analysis | |
| `total_transaction_value` | SUM(ABS(transaction_amount)) | Gross activity throughput — used for Premium segmentation and value segmentation; ABS() ensures both deposits and withdrawals contribute equally to volume | Always >= 0 — represents total activity volume, not net position |
| `net_transaction_amount` | SUM(transaction_amount) | Liquidity and risk signal — positive = net depositor, negative = net spender; NOT used in segmentation (see [Customer Segmentation](#customer-segmentation)) | Signed sum — positive = net inflow, negative = net outflow |
| `avg_transaction_value` | AVG(ABS(transaction_amount)) | Average ticket size; distinguishes high-frequency small-value customers from low-frequency high-value ones | Always >= 0 |
| `max_balance` / `min_balance` | MAX/MIN(closing_balance) | Balance range experienced; flags volatility and minimum liquidity across the customer's history | |
| `current_balance` | MAX_BY(closing_balance, STRUCT(transaction_ts, transaction_id)) | Most recent balance snapshot; ordered on the full timestamp (not DATE) so same-day transactions resolve correctly; actionable for product eligibility checks and risk assessment | NULL for customers with no transactions |
| `first_transaction_date` | MIN(transaction_date) | Marks start of the financial relationship; used to measure time-to-first-transaction from signup | |
| `last_transaction_date` | MAX(transaction_date) | Recency anchor for the 90-day active window | Most recent financial activity |
| `days_since_last_transaction` | DATEDIFF(DAY, last_transaction_date, CURRENT_DATE()) | One of two signals in the active customer definition (alongside `days_since_last_interaction`) | Used in active customer definition |
| `credit_card_transaction_value` | SUM(ABS(transaction_amount)) where product_type = 'CREDIT CARD' | Card-specific activity volume; primary input for `credit_card_activity_to_limit_ratio` | Resolved via JOIN to bronze_product_enrollments; COALESCE to 0 in gold |
| `savings_transaction_value` | SUM(ABS(transaction_amount)) where product_type = 'SAVINGS' | Savings-specific activity volume; enables product-mix and channel analysis | COALESCE to 0 in gold |
| `credit_card_net_transaction_amount` | SUM(transaction_amount) where product_type = 'CREDIT CARD' | Net card flow; expected to be negative for active card spenders — a positive value may indicate returns or credits dominate | Net signed flow on credit card products |
| `savings_net_transaction_amount` | SUM(transaction_amount) where product_type = 'SAVINGS' | Net savings flow; positive = net saver — useful for liquidity and retention analysis | Net signed flow on savings products |
| `credit_card_transaction_count` | COUNT where product_type = 'CREDIT CARD' | Card usage frequency; combined with `credit_card_transaction_value` to derive average card ticket size | COALESCE to 0 in gold |
| `savings_transaction_count` | COUNT where product_type = 'SAVINGS' | Savings usage frequency; high count with low `savings_net_transaction_amount` may indicate frequent small withdrawals | COALESCE to 0 in gold |

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
| `first_interaction_date` | MIN(interaction_date) | Earliest CRM contact; used to measure time-to-first-contact from signup | NULL for customers with no CRM records |
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
| **Field** | `credit_card_activity_to_limit_ratio` (decimal ratio, e.g. 0.75 = 75%) |
| **Calculation** | `credit_card_transaction_value / max_credit_limit` |
| **Rationale** | Key risk and cross-sell signal — high ratio signals heavy card usage relative to limit |
| **Edge case** | NULL when `max_credit_limit` is 0 or NULL (savings-only customers). `credit_card_transaction_value` is already an absolute sum — no ABS() needed |

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
| `age` | FLOOR(MONTHS_BETWEEN(CURRENT_DATE(), date_of_birth) / 12) | Age-based segmentation and regulatory compliance (e.g. product eligibility); recalculated on every full refresh so no backfill is needed as customers age | Recalculated on each full refresh; birthday-accurate (counts only completed years via MONTHS_BETWEEN) |
| `days_since_signup` | DATEDIFF(DAY, signup_date, CURRENT_DATE()) | Input to `customer_lifecycle_stage`; recalculated on each refresh so lifecycle stage advances automatically | Recalculated on each full refresh |
| `mobile_clean` | NULLIF(REGEXP_REPLACE(mobile, '[^0-9]', ''), '') | Normalises mobile numbers for downstream deduplication and outreach systems that require digits-only format | Strips all non-numeric characters; an all-formatting value resolves to NULL (not empty string); ~1.1% of records have non-standard formatting |

**Edge cases:**
- `age` is birthday-accurate: `FLOOR(MONTHS_BETWEEN(CURRENT_DATE(), date_of_birth) / 12)` counts only completed years, so a customer whose birthday has not yet occurred this year is correctly counted as one year younger. It is refreshed only on each batch run, so for strict regulatory age-gating a day-level recomputation at query time is still recommended.
- `days_since_signup` will be 0 for customers who signed up today and negative if `signup_date` is in the future (data quality issue). Negative values indicate dirty source data and are caught by the `assert_no_negative_counts` test.
- `mobile_clean` returns NULL (not an empty string) when the raw value contains only formatting characters — the `NULLIF(..., '')` wrapper converts the empty result to NULL, so downstream `IS NOT NULL` guards behave correctly.
