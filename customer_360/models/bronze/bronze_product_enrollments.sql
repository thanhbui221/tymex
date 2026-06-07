SELECT * FROM {{ source('customer_360_db', 'product_enrollments') }}
