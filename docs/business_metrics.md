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
| `Premium` | `total_products >= 3` AND `total_transaction_value > 100,000` | High-product, high-value customers requiring differentiated service |
| `Standard` | `total_products >= 2` | Multi-product customers with growth potential, regardless of transaction volume |
| `Basic` | All others | New or single-product customers |

Rules are evaluated top-down; a customer meeting Premium criteria is not re-evaluated for Standard.

**Edge case**: A customer with 3+ products but negative `total_transaction_value` (net debit position) falls into Standard, not Premium — the 100k threshold applies to the sum, which can be negative.

---

## Product Metrics

Calculated in [`silver_customer_products.sql`](../customer_360/models/silver/silver_customer_products.sql), propagated to gold.

| Metric | Calculation | Notes |
|--------|-------------|-------|
| `total_products` | COUNT(*) of enrollments per customer | COALESCE to 0 in gold |
| `credit_card_count` | COUNT of enrollments where `product_type = 'Credit Card'` | Case-insensitive match |
| `savings_count` | COUNT of enrollments where `product_type = 'Savings'` | Case-insensitive match |
| `max_credit_limit` | MAX(limit) across credit card enrollments | NULL for customers with no credit card |
| `first_product_date` | MIN(enrollment_date) | Earliest product relationship with the bank |
| `latest_product_date` | MAX(enrollment_date) | Most recent product acquisition; useful for recency-of-product analysis |

---

## Transaction Metrics

Calculated in [`silver_customer_transactions.sql`](../customer_360/models/silver/silver_customer_transactions.sql), propagated to gold.

| Metric | Calculation | Notes |
|--------|-------------|-------|
| `total_transactions` | COUNT(*) | COALESCE to 0 in gold |
| `debit_count` | COUNT where transaction_amount < 0 | |
| `credit_count` | COUNT where transaction_amount > 0 | |
| `total_transaction_value` | SUM(transaction_amount) | Positive = net credit; negative = net debit position |
| `avg_transaction_amount` | AVG(transaction_amount) | Can be negative |
| `max_balance` / `min_balance` | MAX/MIN(closing_balance) | Range of account balance experienced |
| `current_balance` | MAX_BY(closing_balance, transaction_date) | Balance at the most recent transaction; NULL for customers with no transactions |
| `last_transaction_date` | MAX(transaction_date) | Most recent financial activity |
| `days_since_last_transaction` | DATEDIFF(DAY, last_transaction_date, CURRENT_DATE()) | Used in active customer definition |
| `credit_card_transaction_value` | SUM(transaction_amount) where product_type = 'CREDIT CARD' | Net flow; resolved via JOIN to bronze_product_enrollments; COALESCE to 0 in gold |
| `savings_transaction_value` | SUM(transaction_amount) where product_type = 'SAVINGS' | Net flow; COALESCE to 0 in gold |
| `credit_card_transaction_count` | COUNT where product_type = 'CREDIT CARD' | COALESCE to 0 in gold |
| `savings_transaction_count` | COUNT where product_type = 'SAVINGS' | COALESCE to 0 in gold |

**Net vs gross**: all `*_transaction_value` fields represent **net flow** (sum of signed amounts). A customer who deposits and withdraws equally has a value of 0, not a large gross number. Use `debit_count` / `credit_count` alongside the net value to detect high-churn accounts.

---

## Interaction Metrics

Calculated in [`silver_customer_interactions.sql`](../customer_360/models/silver/silver_customer_interactions.sql), propagated to gold.

| Metric | Calculation | Notes |
|--------|-------------|-------|
| `total_interactions` | COUNT(*) | COALESCE to 0 in gold |
| `email_interactions` | COUNT where interaction_type = 'EMAIL' | Case-insensitive; COALESCE to 0 in gold |
| `chat_interactions` | COUNT where interaction_type = 'CHAT' | Case-insensitive; COALESCE to 0 in gold |
| `last_interaction_date` | MAX(interaction_date) | Most recent CRM contact |
| `days_since_last_interaction` | DATEDIFF(DAY, last_interaction_date, CURRENT_DATE()) | Used in active customer definition |

**Known gap**: `Call` interactions (10% of volume) are counted in `total_interactions` but have no dedicated breakdown column. See [`data_quality.md`](data_quality.md) Issue 3.

---

## Derived Metrics

Computed directly in [`customer_360.sql`](../customer_360/models/gold/customer_360.sql) from upstream silver columns.

### Credit Utilization

| | |
|---|---|
| **Definition** | How much of a customer's credit limit has been consumed by credit card transactions |
| **Field** | `credit_utilization` (decimal ratio, e.g. 0.75 = 75%) |
| **Calculation** | `ABS(credit_card_transaction_value) / max_credit_limit` |
| **Rationale** | Key risk and cross-sell signal — high utilization signals potential stress or upsell readiness |
| **Edge case** | NULL when `max_credit_limit` is 0 or NULL (savings-only customers). Uses `ABS()` on the net value; since net flow can be negative (debit position), the absolute value gives an unsigned utilization ratio |

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

| Metric | Calculation | Notes |
|--------|-------------|-------|
| `age` | DATEDIFF(YEAR, date_of_birth, CURRENT_DATE()) | Recalculated on each full refresh |
| `days_since_signup` | DATEDIFF(DAY, signup_date, CURRENT_DATE()) | Recalculated on each full refresh |
| `mobile_clean` | REGEXP_REPLACE(mobile, '[^0-9]', '') | Strips formatting characters; ~1.1% have non-standard format |
