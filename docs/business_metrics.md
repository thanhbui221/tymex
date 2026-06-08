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
| `last_transaction_date` | MAX(transaction_date) | Most recent financial activity |
| `days_since_last_transaction` | DATEDIFF(DAY, last_transaction_date, CURRENT_DATE()) | Used in active customer definition |

---

## Interaction Metrics

Calculated in [`silver_customer_interactions.sql`](../customer_360/models/silver/silver_customer_interactions.sql), propagated to gold.

| Metric | Calculation | Notes |
|--------|-------------|-------|
| `total_interactions` | COUNT(*) | COALESCE to 0 in gold |
| `email_interactions` | COUNT where interaction_type = 'Email' | |
| `chat_interactions` | COUNT where interaction_type = 'Chat' | |
| `last_interaction_date` | MAX(interaction_date) | Most recent CRM contact |
| `days_since_last_interaction` | DATEDIFF(DAY, last_interaction_date, CURRENT_DATE()) | Used in active customer definition |

**Known gap**: `Call` interactions (10% of volume) are counted in `total_interactions` but have no dedicated breakdown column. See [`data_quality.md`](data_quality.md) Issue 3.

---

## Demographic Metrics

Calculated in [`silver_customers.sql`](../customer_360/models/silver/silver_customers.sql), propagated to gold.

| Metric | Calculation | Notes |
|--------|-------------|-------|
| `age` | DATEDIFF(YEAR, date_of_birth, CURRENT_DATE()) | Recalculated on each full refresh |
| `days_since_signup` | DATEDIFF(DAY, signup_date, CURRENT_DATE()) | Recalculated on each full refresh |
| `mobile_clean` | REGEXP_REPLACE(mobile, '[^0-9]', '') | Strips formatting characters; ~1.1% have non-standard format |
