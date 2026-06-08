# Databricks Clustering Strategies: Liquid Clustering vs Z-Ordering

## TL;DR

**Liquid Clustering (Option A)** is the modern approach - use it for new tables.
**Z-Ordering (Legacy)** is the older method - only use if you're on Databricks Runtime < 13.3.

---

## Liquid Clustering (Recommended)

**Available:** Databricks Runtime 13.3+ (released late 2023)

### How it works:
- **Automatic maintenance**: Databricks automatically reorganizes data during writes
- **No manual OPTIMIZE needed**: Clustering happens incrementally on writes
- **Multi-column clustering**: Can cluster by multiple columns efficiently
- **Adaptive**: Automatically adjusts clustering as data distribution changes

### Syntax:
```sql
CREATE TABLE customer_360
CLUSTER BY (customer_id)
AS SELECT ...
```

### dbt implementation:
```sql
{{ config(
    materialized='incremental',
    unique_key='customer_id',
    cluster_by=['customer_id']
) }}
```

### Pros:
✓ Fully automated - no post-hooks needed
✓ Better performance for multi-column clustering
✓ Lower maintenance overhead (no manual OPTIMIZE jobs)
✓ More cost-efficient (incremental clustering vs full table scans)

### Cons:
✗ Requires Databricks Runtime 13.3+
✗ Cannot mix with Z-Ordering on same table

---

## Z-Ordering (Legacy)

**Available:** All Databricks Runtime versions

### How it works:
- **Manual process**: You must run `OPTIMIZE ... ZORDER BY` explicitly
- **Full table operation**: Each OPTIMIZE scans entire table (expensive)
- **Z-order curve**: Uses space-filling curve to co-locate related data
- **Best for 1-4 columns**: Performance degrades with more columns

### Syntax:
```sql
-- Create table (no clustering yet)
CREATE TABLE customer_360 AS SELECT ...

-- Manually run OPTIMIZE periodically
OPTIMIZE customer_360 ZORDER BY (customer_id);
```

### dbt implementation:
```sql
{{ config(
    materialized='incremental',
    unique_key='customer_id',
    post_hook=[
        "OPTIMIZE {{ this }} ZORDER BY (customer_id)"
    ]
) }}
```

### Pros:
✓ Works on all Databricks versions
✓ Mature and well-tested
✓ Good for low-frequency updates

### Cons:
✗ Requires manual OPTIMIZE commands
✗ Expensive (full table scans)
✗ Adds significant time to dbt runs if in post-hook
✗ Need to schedule separate OPTIMIZE jobs
✗ Performance degrades with 4+ columns

---

## Performance Comparison

| Aspect | Liquid Clustering | Z-Ordering |
|--------|------------------|------------|
| **Setup complexity** | Simple (one config line) | Complex (post-hooks or separate jobs) |
| **Maintenance** | Automatic | Manual OPTIMIZE needed |
| **Cost per optimization** | Low (incremental) | High (full table scan) |
| **Query performance** | Excellent | Excellent |
| **Multi-column clustering** | Efficient (4+ columns) | Degrades (4+ columns) |
| **Write overhead** | Low | None (until OPTIMIZE) |
| **Best for** | All new tables | Legacy systems |

---

## Migration Path

If you're currently using Z-Ordering and want to migrate:

```sql
-- 1. Remove Z-ordering
ALTER TABLE customer_360 ALTER COLUMN customer_id DROP STATISTICS;

-- 2. Add liquid clustering
ALTER TABLE customer_360 CLUSTER BY (customer_id);

-- 3. Let next writes apply clustering (automatic)
```

---

## Recommendation for Customer 360 Project

**Use Liquid Clustering (Option A)** because:

1. **Databricks Community Edition supports Runtime 13.3+** ✓
2. **Lower operational overhead** - no separate OPTIMIZE jobs needed
3. **Better cost efficiency** - incremental clustering vs full table scans
4. **Future-proof** - Databricks is deprecating Z-Ordering focus

**Only use Z-Ordering if:**
- You're stuck on older Databricks Runtime (< 13.3)
- You have existing infrastructure with Z-Ordering and no migration window

---

## Implementation for customer_360

```sql
-- models/gold/customer_360.sql
{{
    config(
        materialized='incremental',
        unique_key='customer_id',
        incremental_strategy='merge',
        cluster_by=['customer_id'],  -- Liquid Clustering
        file_format='delta'
    )
}}

SELECT
    c.customer_id,
    c.first_name,
    c.last_name,
    ...
FROM {{ ref('silver_customers') }} c
LEFT JOIN {{ ref('silver_customer_products') }} p ON c.customer_id = p.customer_id
LEFT JOIN {{ ref('silver_customer_interactions') }} i ON c.customer_id = i.customer_id
LEFT JOIN {{ ref('silver_customer_transactions') }} t ON c.customer_id = t.customer_id

{% if is_incremental() %}
WHERE c.customer_id IN (
    SELECT DISTINCT customer_id FROM {{ ref('silver_customer_interactions') }}
    WHERE last_interaction_date > (SELECT MAX(last_interaction_date) FROM {{ this }})
    UNION
    SELECT DISTINCT customer_id FROM {{ ref('silver_customer_transactions') }}
    WHERE last_transaction_date > (SELECT MAX(last_transaction_date) FROM {{ this }})
)
{% endif %}
```

No post-hooks needed! Clustering happens automatically on writes.
