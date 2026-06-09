-- Fails if any customer has a negative value for a metric that must be >= 0.
select
    customer_id,
    age,
    days_since_signup,
    total_products,
    total_interactions,
    total_transactions,
    credit_card_count,
    savings_count,
    email_interactions,
    chat_interactions,
    call_interactions,
    debit_count,
    credit_count,
    total_transaction_value,
    total_debit_value,
    total_credit_value,
    credit_card_transaction_value,
    savings_transaction_value,
    credit_card_transaction_count,
    savings_transaction_count,
    days_since_last_activity
from {{ ref('customer_360') }}
where age < 0
   or days_since_signup < 0
   or total_products < 0
   or total_interactions < 0
   or total_transactions < 0
   or credit_card_count < 0
   or savings_count < 0
   or email_interactions < 0
   or chat_interactions < 0
   or call_interactions < 0
   or debit_count < 0
   or credit_count < 0
   or total_transaction_value < 0
   or total_debit_value < 0
   or total_credit_value < 0
   or credit_card_transaction_value < 0
   or savings_transaction_value < 0
   or credit_card_transaction_count < 0
   or savings_transaction_count < 0
   or days_since_last_activity < 0