{{
    config(
        materialized='table'
    )
}}

SELECT
    customer_id,
    TRIM(first_name)                          AS first_name,
    TRIM(last_name)                           AS last_name,
    LOWER(TRIM(email))                        AS email,
    REGEXP_REPLACE(mobile, '[^0-9]', '')      AS mobile_clean,
    gender,
    date_of_birth,
    DATEDIFF(YEAR, date_of_birth, CURRENT_DATE()) AS age,
    signup_date,
    DATEDIFF(DAY, signup_date, CURRENT_DATE()) AS days_since_signup
FROM {{ ref('bronze_customer_raw') }}