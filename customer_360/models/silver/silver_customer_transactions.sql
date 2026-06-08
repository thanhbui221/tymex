{{
    config(
        materialized='incremental',
        unique_key='customer_id',
        incremental_strategy='merge'
    )
}}

SELECT
    t.customer_id,
    COUNT(*) AS total_transactions,
    SUM(CASE WHEN CAST(t.transaction_amount AS DECIMAL(12,2)) < 0 THEN 1 ELSE 0 END) AS debit_count,
    SUM(CASE WHEN CAST(t.transaction_amount AS DECIMAL(12,2)) > 0 THEN 1 ELSE 0 END) AS credit_count,
    SUM(CAST(t.transaction_amount AS DECIMAL(12,2)))        AS total_transaction_value,
    AVG(CAST(t.transaction_amount AS DECIMAL(12,2)))        AS avg_transaction_amount,
    MAX(CAST(t.closing_balance AS DECIMAL(12,2)))           AS max_balance,
    MIN(CAST(t.closing_balance AS DECIMAL(12,2)))           AS min_balance,
    MAX(t.transaction_date)                                 AS last_transaction_date,
    DATEDIFF(DAY, MAX(t.transaction_date), CURRENT_DATE())  AS days_since_last_transaction,

    -- product-type breakdowns via product_id FK → product_enrollments
    SUM(CASE WHEN UPPER(TRIM(pe.product_type)) = 'CREDIT CARD'
        THEN CAST(t.transaction_amount AS DECIMAL(12,2)) ELSE 0 END) AS credit_card_transaction_value,
    SUM(CASE WHEN UPPER(TRIM(pe.product_type)) = 'SAVINGS'
        THEN CAST(t.transaction_amount AS DECIMAL(12,2)) ELSE 0 END) AS savings_transaction_value,
    COUNT(CASE WHEN UPPER(TRIM(pe.product_type)) = 'CREDIT CARD' THEN 1 END) AS credit_card_transaction_count,
    COUNT(CASE WHEN UPPER(TRIM(pe.product_type)) = 'SAVINGS'     THEN 1 END) AS savings_transaction_count,

    MAX(t._ingested_at) AS _ingested_at
FROM {{ ref('bronze_transaction_history') }} t
LEFT JOIN {{ ref('bronze_product_enrollments') }} pe ON t.product_id = pe.product_id
WHERE t.transaction_id IS NOT NULL
{% if is_incremental() %}
    AND t._ingested_at > (SELECT MAX(_ingested_at) FROM {{ this }})
{% endif %}
GROUP BY t.customer_id