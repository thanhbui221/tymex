SELECT * FROM {{ source('customer_360_db', 'crm_interactions') }}
