select
    customer_id,
    total_transaction_value,
    total_debit_value,
    total_credit_value
from {{ ref('silver_customer_transactions') }}
where round(total_transaction_value, 2) <> round(total_debit_value + total_credit_value, 2)