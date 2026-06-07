SELECT * FROM {{ source('customer_360_db', 'transaction_history') }}
