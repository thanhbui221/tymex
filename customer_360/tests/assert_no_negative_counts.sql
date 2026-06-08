-- Fails if any customer has a negative value for a metric that must be >= 0.
SELECT
    customer_id,
    age,
    days_since_signup,
    total_products,
    total_interactions,
    total_transactions,
    credit_card_count,
    savings_count
FROM {{ ref('customer_360') }}
WHERE age                < 0
   OR days_since_signup  < 0
   OR total_products     < 0
   OR total_interactions < 0
   OR total_transactions < 0
   OR credit_card_count  < 0
   OR savings_count      < 0
