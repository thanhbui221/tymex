-- Fails if any customer marked Active has no activity in the last 90 days.
-- Both conditions must be false (or NULL) for an Active customer to be invalid.
SELECT
    customer_id,
    customer_status,
    days_since_last_interaction,
    days_since_last_transaction
FROM {{ ref('customer_360') }}
WHERE customer_status = 'Active'
  AND (days_since_last_interaction > 90 OR days_since_last_interaction IS NULL)
  AND (days_since_last_transaction  > 90 OR days_since_last_transaction  IS NULL)
