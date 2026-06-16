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
CREATE TABLE silver_customer_transactions
CLUSTER BY (customer_id)
AS SELECT ...
```

### dbt implementation:
```sql
{{ config(
    materialized='incremental',
    unique_key='customer_id',
    liquid_clustered_by=['customer_id']
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
CREATE TABLE silver_customer_transactions AS SELECT ...

-- Manually run OPTIMIZE periodically
OPTIMIZE silver_customer_transactions ZORDER BY (customer_id);
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
ALTER TABLE silver_customer_transactions ALTER COLUMN customer_id DROP STATISTICS;

-- 2. Add liquid clustering
ALTER TABLE silver_customer_transactions CLUSTER BY (customer_id);

-- 3. Let next writes apply clustering (automatic)
```

---

## Recommendation for Customer 360 Project

**Liquid Clustering is applied to the two incremental silver tables** — `silver_customer_interactions` and `silver_customer_transactions` — clustered on `customer_id`:

1. **Databricks Runtime 13.3+ is available** ✓
2. **Lower operational overhead** — no separate `OPTIMIZE ZORDER` jobs
3. **Better cost efficiency** — incremental clustering vs full-table scans
4. **MERGE benefits directly** — each hourly merge locates target `customer_id` rows; clustering on the same key lets Delta skip non-matching files as files accumulate across runs

**It is NOT applied to the gold `customer_360` table.** Gold is a full-refresh `table` — every run drops and rewrites all files from scratch, so there is no accumulated disorder to cluster, and at 100k customers the table fits in a handful of files that every query reads in full regardless of layout. Liquid Clustering is also lazy (applied at OPTIMIZE time, which only runs weekly), so gold would sit unclustered between maintenance runs anyway. See [`design_decisions.md`](design_decisions.md) §4 for the full rationale. Revisit if customer count reaches the millions.

---

## Implementation

### Incremental silver tables (clustered)

```sql
-- models/silver/silver_customer_transactions.sql (same config on silver_customer_interactions)
{{
    config(
        materialized='incremental',
        unique_key='customer_id',
        incremental_strategy='merge',
        liquid_clustered_by=['customer_id']
    )
}}
```

`liquid_clustered_by` is the dbt-databricks config for Liquid Clustering — applied automatically on write, no post-hooks needed.

### Gold table (NOT clustered, full refresh)

```sql
-- models/gold/customer_360.sql
{{
    config(
        materialized='table'
    )
}}
```

No clustering and no incremental block — gold is rebuilt in full each run as a join of four pre-aggregated, one-row-per-customer silver tables, so it is consistent and self-healing by construction.
