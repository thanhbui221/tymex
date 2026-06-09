{{
    config(
        materialized='incremental',
        unique_key='customer_id',
        incremental_strategy='merge'
    )
}}

with changed_customers as (

    {% if is_incremental() %}

        select distinct customer_id
        from {{ ref('bronze_transaction_history') }}
        where _ingested_at > (
            select coalesce(max(_ingested_at), cast('1970-01-01' as timestamp))
            from {{ this }}
        )

    {% else %}

        select distinct customer_id
        from {{ ref('bronze_transaction_history') }}

    {% endif %}

),

base_transactions as (

    select
        t.transaction_id,
        t.customer_id,
        t.product_id,

        cast(t.transaction_amount as decimal(18, 2)) as transaction_amount,
        abs(cast(t.transaction_amount as decimal(18, 2))) as abs_transaction_amount,

        cast(t.closing_balance as decimal(18, 2)) as closing_balance,
        cast(t.transaction_date as date) as transaction_date,

        upper(trim(pe.product_type)) as product_type,

        t._ingested_at

    from {{ ref('bronze_transaction_history') }} t

    inner join changed_customers c
        on t.customer_id = c.customer_id

    left join {{ ref('bronze_product_enrollments') }} pe
        on t.product_id = pe.product_id

    where t.transaction_id is not null
      and t.customer_id is not null
      and t.product_id is not null

),

aggregated as (

    select
        customer_id,

        count(*) as total_transactions,

        sum(case when transaction_amount < 0 then 1 else 0 end) as debit_count,
        sum(case when transaction_amount > 0 then 1 else 0 end) as credit_count,

        -- total activity value
        sum(abs_transaction_amount) as total_transaction_value,

        -- net inflow / outflow
        sum(transaction_amount) as net_transaction_amount,

        avg(abs_transaction_amount) as avg_transaction_value,

        sum(case when transaction_amount < 0 then abs_transaction_amount else 0 end) as total_debit_value,
        sum(case when transaction_amount > 0 then abs_transaction_amount else 0 end) as total_credit_value,

        max(closing_balance) as max_balance,
        min(closing_balance) as min_balance,

        min(transaction_date) as first_transaction_date,
        max(transaction_date) as last_transaction_date,

        max_by(closing_balance, transaction_date) as current_balance,

        sum(
            case
                when product_type = 'CREDIT CARD'
                    then abs_transaction_amount
                else 0
            end
        ) as credit_card_transaction_value,

        sum(
            case
                when product_type = 'SAVINGS'
                    then abs_transaction_amount
                else 0
            end
        ) as savings_transaction_value,

        sum(
            case
                when product_type = 'CREDIT CARD'
                    then transaction_amount
                else 0
            end
        ) as credit_card_net_transaction_amount,

        sum(
            case
                when product_type = 'SAVINGS'
                    then transaction_amount
                else 0
            end
        ) as savings_net_transaction_amount,

        count(case when product_type = 'CREDIT CARD' then 1 end) as credit_card_transaction_count,
        count(case when product_type = 'SAVINGS' then 1 end) as savings_transaction_count,

        max(_ingested_at) as _ingested_at

    from base_transactions

    group by customer_id

)

select *
from aggregated