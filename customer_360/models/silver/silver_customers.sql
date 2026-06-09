{{
    config(
        materialized='table'
    )
}}

with cleaned as (

    select
        customer_id,

        trim(first_name) as first_name,
        trim(last_name) as last_name,
        concat(trim(first_name), ' ', trim(last_name)) as full_name,

        lower(trim(email)) as email,
        nullif(regexp_replace(cast(mobile as string), '[^0-9]', ''), '') as mobile_clean,

        trim(gender) as gender,

        cast(date_of_birth as date) as date_of_birth,
        cast(signup_date as date) as signup_date,

        _ingested_at

    from {{ ref('bronze_customer_raw') }}

    where customer_id is not null

),

deduped as (

    select
        *,
        row_number() over (
            partition by customer_id
            order by _ingested_at desc
        ) as rn

    from cleaned

),

with_age as (

    select
        *,
        floor(months_between(current_date(), date_of_birth) / 12) as age

    from deduped

    where rn = 1

),

final as (

    select
        customer_id,
        first_name,
        last_name,
        full_name,
        email,
        mobile_clean,
        gender,
        date_of_birth,
        age,

        case
            when age < 18 then 'Under 18'
            when age < 25 then '18-24'
            when age < 35 then '25-34'
            when age < 45 then '35-44'
            when age < 55 then '45-54'
            when age < 65 then '55-64'
            else '65+'
        end as age_band,

        signup_date,
        datediff(current_date(), signup_date) as days_since_signup,

        _ingested_at

    from with_age

)

select *
from final