-- Fails if any Premium customer does not meet both criteria:
-- 3+ products AND total_transaction_value > 100,000.
SELECT
    customer_id,
    customer_segment,
    total_products,
    total_transaction_value
FROM {{ ref('customer_360') }}
WHERE customer_segment = 'Premium'
  AND (total_products < 3 OR total_transaction_value <= 100000)
