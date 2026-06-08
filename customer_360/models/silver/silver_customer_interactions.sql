{{
    config(
        materialized='incremental',
        unique_key='customer_id',
        incremental_strategy='merge'
    )
}}

SELECT
    customer_id,
    MAX(interaction_date) AS last_interaction_date,
    COUNT(*) AS total_interactions,
    COUNT(CASE WHEN UPPER(TRIM(interaction_type)) = 'EMAIL' THEN 1 END) AS email_interactions,
    COUNT(CASE WHEN UPPER(TRIM(interaction_type)) = 'CHAT' THEN 1 END) AS chat_interactions,
    DATEDIFF(DAY, MAX(interaction_date), CURRENT_DATE()) AS days_since_last_interaction,
    MAX(_ingested_at) AS _ingested_at
FROM {{ ref('bronze_crm_transactions') }}
WHERE interaction_id IS NOT NULL
{% if var('backfill_start', '') | trim != '' %}
    AND customer_id IN (
        SELECT DISTINCT customer_id
        FROM {{ ref('bronze_crm_transactions') }}
        WHERE _ingested_at >= '{{ var("backfill_start") }}'
        {% if var('backfill_end', '') | trim != '' %}
            AND _ingested_at < '{{ var("backfill_end") }}'
        {% endif %}
    )
{% elif is_incremental() %}
    AND _ingested_at > (SELECT MAX(_ingested_at) FROM {{ this }})
{% endif %}
GROUP BY customer_id
