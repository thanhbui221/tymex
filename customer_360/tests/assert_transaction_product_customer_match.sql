select
    t.transaction_id,
    t.customer_id as transaction_customer_id,
    t.product_id,
    p.customer_id as product_customer_id
from {{ ref('bronze_transaction_history') }} t
left join {{ ref('bronze_product_enrollments') }} p
    on t.product_id = p.product_id
where p.customer_id is null
   or t.customer_id <> p.customer_id