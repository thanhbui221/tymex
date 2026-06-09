-- Fails if any Premium customer does not meet the defined Premium criteria.
select
    customer_id,
    customer_segment,
    has_credit_card,
    total_transaction_value
from {{ ref('customer_360') }}
where customer_segment = 'Premium'
  and (
        has_credit_card <> true
        or total_transaction_value < 100000
      )