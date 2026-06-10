{{
    config(
        materialized='incremental',
        unique_key='customer_id',
        incremental_strategy='merge',
        liquid_clustered_by=['customer_id']
    )
}}

with changed_customers as (

    {% if is_incremental() %}

        select distinct customer_id
        from {{ ref('bronze_crm_interactions') }}
        where _ingested_at > (
            select coalesce(max(_ingested_at), cast('1970-01-01' as timestamp))
            from {{ this }}
        )

    {% else %}

        select distinct customer_id
        from {{ ref('bronze_crm_interactions') }}

    {% endif %}

),

base_interactions as (

    select
        i.interaction_id,
        i.customer_id,
        upper(trim(i.interaction_type)) as interaction_type,
        cast(i.interaction_date as date) as interaction_date,
        i._ingested_at

    from {{ ref('bronze_crm_interactions') }} i

    inner join changed_customers c
        on i.customer_id = c.customer_id

    where i.interaction_id is not null
      and i.customer_id is not null

),

aggregated as (

    select
        customer_id,

        count(*) as total_interactions,

        sum(case when interaction_type = 'EMAIL' then 1 else 0 end) as email_interactions,
        sum(case when interaction_type = 'CHAT' then 1 else 0 end) as chat_interactions,
        sum(case when interaction_type = 'CALL' then 1 else 0 end) as call_interactions,

        min(interaction_date) as first_interaction_date,
        max(interaction_date) as last_interaction_date,

        max_by(interaction_type, interaction_date) as last_interaction_type,

        max(_ingested_at) as _ingested_at

    from base_interactions

    group by customer_id

)

select *
from aggregated