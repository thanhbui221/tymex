{{
    config(
        materialized='table'
    )
}}

SELECT
    customer_id,
    COUNT(*) AS total_products,
    SUM(CASE WHEN UPPER(TRIM(product_type)) = 'CREDIT CARD' THEN 1 ELSE 0 END) AS credit_card_count,
    SUM(CASE WHEN UPPER(TRIM(product_type)) = 'SAVINGS' THEN 1 ELSE 0 END) AS savings_count,
    MAX(CASE WHEN UPPER(TRIM(product_type)) = 'CREDIT CARD' THEN CAST(limit AS DECIMAL(12,2)) ELSE 0 END) AS max_credit_limit,
    MIN(enrollment_date) AS first_product_date,
    MAX(enrollment_date) AS latest_product_date
FROM {{ ref('bronze_product_enrollments') }}
WHERE product_id IS NOT NULL
GROUP BY customer_id