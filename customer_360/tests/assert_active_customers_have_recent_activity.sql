-- Fails if active customer flags/status do not match days_since_last_activity.
select
    customer_id,
    last_activity_date,
    days_since_last_activity,
    is_active_customer,
    customer_status
from {{ ref('customer_360') }}
where (
        customer_status = 'Active'
        and (
            last_activity_date is null
            or days_since_last_activity > 90
            or is_active_customer <> true
        )
      )
   or (
        is_active_customer = true
        and (
            last_activity_date is null
            or days_since_last_activity > 90
            or customer_status <> 'Active'
        )
      )
   or (
        customer_status = 'Never Active'
        and last_activity_date is not null
      )