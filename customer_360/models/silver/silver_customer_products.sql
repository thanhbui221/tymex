{{
    config(
        materialized='table'
    )
}}

with cleaned as (

    select
        product_id,
        customer_id,
        upper(trim(product_type)) as product_type,
        cast(enrollment_date as date) as enrollment_date,

        case
            when upper(trim(product_type)) = 'CREDIT CARD'
                then cast(`limit` as decimal(18, 2))
            else null
        end as credit_limit,

        _ingested_at

    from {{ ref('bronze_product_enrollments') }}

    where product_id is not null
      and customer_id is not null

),

aggregated as (

    select
        customer_id,

        count(*) as total_products,

        sum(case when product_type = 'CREDIT CARD' then 1 else 0 end) as credit_card_count,
        sum(case when product_type = 'SAVINGS' then 1 else 0 end) as savings_count,

        max(credit_limit) as max_credit_limit,
        sum(coalesce(credit_limit, 0)) as total_credit_limit,

        min(enrollment_date) as first_product_date,
        max(enrollment_date) as latest_product_date,

        max(_ingested_at) as _ingested_at

    from cleaned

    group by customer_id

)

select
    customer_id,
    total_products,
    credit_card_count,
    savings_count,
    max_credit_limit,
    total_credit_limit,
    first_product_date,
    latest_product_date,

    case when credit_card_count > 0 then true else false end as has_credit_card,
    case when savings_count > 0 then true else false end as has_savings,
    case when total_products >= 2 then true else false end as is_multi_product,

    case
        when credit_card_count > 0 and savings_count > 0 then 'Savings + Credit Card'
        when credit_card_count > 0 then 'Credit Card Only'
        when savings_count > 0 then 'Savings Only'
        else 'No Product'
    end as product_segment,

    _ingested_at

from aggregated