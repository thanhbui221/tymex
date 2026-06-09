{{
    config(
        materialized='table'
    )
}}

with joined as (

    select
        c.customer_id,

        -- customer profile
        c.first_name,
        c.last_name,
        c.full_name,
        c.email,
        c.mobile_clean,
        c.gender,
        c.date_of_birth,
        c.age,
        c.age_band,
        c.signup_date,
        c.days_since_signup,

        -- product holdings
        coalesce(p.total_products, 0) as total_products,
        coalesce(p.credit_card_count, 0) as credit_card_count,
        coalesce(p.savings_count, 0) as savings_count,
        p.max_credit_limit,
        p.total_credit_limit,
        p.first_product_date,
        p.latest_product_date,
        coalesce(p.has_credit_card, false) as has_credit_card,
        coalesce(p.has_savings, false) as has_savings,
        coalesce(p.is_multi_product, false) as is_multi_product,
        coalesce(p.product_segment, 'No Product') as product_segment,

        -- CRM interactions
        coalesce(i.total_interactions, 0) as total_interactions,
        coalesce(i.email_interactions, 0) as email_interactions,
        coalesce(i.chat_interactions, 0) as chat_interactions,
        coalesce(i.call_interactions, 0) as call_interactions,
        i.first_interaction_date,
        i.last_interaction_date,
        i.last_interaction_type,

        -- transactions
        coalesce(t.total_transactions, 0) as total_transactions,
        coalesce(t.debit_count, 0) as debit_count,
        coalesce(t.credit_count, 0) as credit_count,

        coalesce(t.total_transaction_value, 0) as total_transaction_value,
        coalesce(t.net_transaction_amount, 0) as net_transaction_amount,
        coalesce(t.avg_transaction_value, 0) as avg_transaction_value,

        coalesce(t.total_debit_value, 0) as total_debit_value,
        coalesce(t.total_credit_value, 0) as total_credit_value,

        t.max_balance,
        t.min_balance,
        t.current_balance,

        t.first_transaction_date,
        t.last_transaction_date,

        coalesce(t.credit_card_transaction_value, 0) as credit_card_transaction_value,
        coalesce(t.savings_transaction_value, 0) as savings_transaction_value,
        coalesce(t.credit_card_net_transaction_amount, 0) as credit_card_net_transaction_amount,
        coalesce(t.savings_net_transaction_amount, 0) as savings_net_transaction_amount,
        coalesce(t.credit_card_transaction_count, 0) as credit_card_transaction_count,
        coalesce(t.savings_transaction_count, 0) as savings_transaction_count,

        -- source watermarks
        coalesce(c._ingested_at, cast('1970-01-01' as timestamp)) as _customer_ingested_at,
        coalesce(p._ingested_at, cast('1970-01-01' as timestamp)) as _products_ingested_at,
        coalesce(i._ingested_at, cast('1970-01-01' as timestamp)) as _interactions_ingested_at,
        coalesce(t._ingested_at, cast('1970-01-01' as timestamp)) as _transactions_ingested_at

    from {{ ref('silver_customers') }} c

    left join {{ ref('silver_customer_products') }} p
        on c.customer_id = p.customer_id

    left join {{ ref('silver_customer_interactions') }} i
        on c.customer_id = i.customer_id

    left join {{ ref('silver_customer_transactions') }} t
        on c.customer_id = t.customer_id

),

activity as (

    select
        *,

        case
            when last_transaction_date is null and last_interaction_date is null then null
            when last_transaction_date is null then last_interaction_date
            when last_interaction_date is null then last_transaction_date
            else greatest(last_transaction_date, last_interaction_date)
        end as last_activity_date

    from joined

),

final as (

    select
        *,

        datediff(current_date(), last_transaction_date) as days_since_last_transaction,
        datediff(current_date(), last_interaction_date) as days_since_last_interaction,
        datediff(current_date(), last_activity_date) as days_since_last_activity,

        case
            when last_activity_date is not null
             and datediff(current_date(), last_activity_date) <= {{ var('active_days_threshold') }}
                then true
            else false
        end as is_active_customer,

        case
            when last_activity_date is null then 'Never Active'
            when datediff(current_date(), last_activity_date) <= {{ var('active_days_threshold') }} then 'Active'
            when datediff(current_date(), last_activity_date) <= {{ var('at_risk_days_threshold') }} then 'At Risk'
            else 'Dormant'
        end as customer_status,

        case
            when total_transaction_value >= {{ var('high_value_transaction_threshold') }} then 'High Value'
            when total_transaction_value >= {{ var('medium_value_transaction_threshold') }} then 'Medium Value'
            when total_transaction_value > 0 then 'Low Value'
            else 'No Transaction'
        end as customer_value_segment,

        case
            when has_credit_card = true
             and total_transaction_value >= {{ var('premium_transaction_threshold') }} then 'Premium'
            when is_multi_product = true then 'Standard'
            else 'Basic'
        end as customer_segment,

        case
            when total_interactions >= {{ var('highly_engaged_interaction_threshold') }} then 'Highly Engaged'
            when total_interactions >= {{ var('moderately_engaged_interaction_threshold') }} then 'Moderately Engaged'
            when total_interactions > 0 then 'Low Engagement'
            else 'No CRM Engagement'
        end as engagement_segment,

        case
            when coalesce(max_credit_limit, 0) > 0
                then credit_card_transaction_value / max_credit_limit
            else null
        end as credit_card_activity_to_limit_ratio,

        case
            when days_since_signup > 0
                then total_transactions * 30.0 / days_since_signup
            else null
        end as monthly_transaction_frequency,

        case
            when days_since_signup < {{ var('lifecycle_new_days') }} then 'New'
            when days_since_signup < {{ var('lifecycle_growing_days') }} then 'Growing'
            when days_since_signup < {{ var('lifecycle_established_days') }} then 'Established'
            else 'Mature'
        end as customer_lifecycle_stage,

        greatest(
            _customer_ingested_at,
            _products_ingested_at,
            _interactions_ingested_at,
            _transactions_ingested_at
        ) as _latest_source_ingested_at,

        current_timestamp() as _gold_updated_at

    from activity

)

select *
from final
