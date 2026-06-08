{{
    config(
        materialized='incremental',
        unique_key='customer_id',
        incremental_strategy='merge'
    )
}}

SELECT
    -- demographics
    c.customer_id,
    c.first_name,
    c.last_name,
    c.email,
    c.mobile_clean,
    c.gender,
    c.age,
    c.signup_date,
    c.days_since_signup,

    -- product holdings
    COALESCE(p.total_products, 0)            AS total_products,
    COALESCE(p.credit_card_count, 0)         AS credit_card_count,
    COALESCE(p.savings_count, 0)             AS savings_count,
    p.max_credit_limit,
    p.first_product_date,

    -- interactions
    i.last_interaction_date,
    COALESCE(i.total_interactions, 0)        AS total_interactions,
    i.days_since_last_interaction,

    -- transactions
    COALESCE(t.total_transactions, 0)             AS total_transactions,
    COALESCE(t.debit_count, 0)                    AS debit_count,
    COALESCE(t.credit_count, 0)                   AS credit_count,
    t.total_transaction_value,
    t.avg_transaction_amount,
    t.max_balance,
    t.min_balance,
    t.last_transaction_date,
    t.days_since_last_transaction,

    -- business logic
    CASE
        WHEN i.days_since_last_interaction <= 90
          OR t.days_since_last_transaction  <= 90 THEN 'Active'
        ELSE 'Inactive'
    END AS customer_status,

    CASE
        WHEN COALESCE(p.total_products, 0) >= 3
         AND t.total_transaction_value > 100000 THEN 'Premium'
        WHEN COALESCE(p.total_products, 0) >= 2  THEN 'Standard'
        ELSE 'Basic'
    END AS customer_segment,

    -- separate watermarks per silver source to avoid cross-contamination
    COALESCE(i._ingested_at, CAST('1970-01-01' AS TIMESTAMP)) AS _interactions_ingested_at,
    COALESCE(t._ingested_at, CAST('1970-01-01' AS TIMESTAMP)) AS _transactions_ingested_at

FROM {{ ref('silver_customers') }} c
LEFT JOIN {{ ref('silver_customer_products') }}     p ON c.customer_id = p.customer_id
LEFT JOIN {{ ref('silver_customer_interactions') }} i ON c.customer_id = i.customer_id
LEFT JOIN {{ ref('silver_customer_transactions') }} t ON c.customer_id = t.customer_id

{% if is_incremental() %}
WHERE
    i._ingested_at > (SELECT COALESCE(MAX(_interactions_ingested_at), CAST('1970-01-01' AS TIMESTAMP)) FROM {{ this }})
    OR
    t._ingested_at > (SELECT COALESCE(MAX(_transactions_ingested_at), CAST('1970-01-01' AS TIMESTAMP)) FROM {{ this }})
{% endif %}
