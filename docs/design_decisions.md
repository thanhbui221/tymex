# Design Decisions

Architecture diagram:

![Architecture](architecture.svg)

The diagram covers the full pipeline: source systems → ingestion → Bronze/Silver/Gold (Delta Lake) → consumers, plus the orchestration layer (four Databricks Workflow jobs provisioned by Terraform) and where dbt tests fire.

---

## 1. Medallion Architecture (Bronze → Silver → Gold)

**Decision**: Three-layer medallion — Bronze (raw views) → Silver (clean, aggregated, one row per customer) → Gold (joined, business-logic enriched).

**Rationale**:
- Bronze views create a stable contract between raw source tables and downstream models. If a source table is renamed, only the bronze model changes.
- Silver isolates cleaning and aggregation logic; each silver model has a single responsibility (demographics, products, interactions, transactions).
- Gold is purely a join + business logic layer — no aggregation happens there.

**Trade-off**: An extra layer adds query hops. Accepted because concern isolation outweighs the marginal performance cost, especially with Delta caching on Databricks.

---

## 2. Materialization Strategy — `customer_360`: Full Refresh vs Incremental Upsert

Full configuration: [`customer_360/dbt_project.yml`](../customer_360/dbt_project.yml)

| Model | Materialization | Rationale |
|-------|----------------|-----------|
| Bronze (all) | `view` | No storage cost; always reflects latest raw data |
| `silver_customers` | `table` (full refresh) | Source is small (100k rows); demographics change slowly; simpler than incremental |
| `silver_customer_products` | `table` (full refresh) | Same reasoning; enrollment data is relatively stable |
| `silver_customer_interactions` | `incremental` (merge) | High-volume source (243k+); append-heavy; watermark-based processing avoids full scans |
| `silver_customer_transactions` | `incremental` (merge) | Highest-volume source (887k+); same reasoning |
| `customer_360` | `table` (full refresh) | Joins 4 silver sources; an incremental merge would require tracking which customers changed across all 4 upstreams simultaneously — complex and fragile. Full refresh is simpler, always consistent. |

**Incremental watermark**: `_ingested_at` (load timestamp) is used rather than the business event timestamp (`transaction_date`, `interaction_date`). This avoids reprocessing failures caused by late-arriving records or timezone-ambiguous event times.

### Why `customer_360` is full refresh — detailed comparison

The gold table joins all four silver models and derives a large number of business metrics. The choice between full refresh and incremental upsert has significant implications for correctness, not just performance.

#### Full Refresh (current)

| | |
|---|---|
| **How it works** | Every hourly run drops and rewrites the entire table by joining all four silver models |
| **Scales with** | Customer count (not event volume — silver handles that) |

**Pros:**

1. **Always consistent across all four silver sources** — every row reflects the same point-in-time join. An incremental merge for customer A could mix a newly updated `silver_customer_interactions` row with a stale `silver_customer_transactions` row from a previous merge cycle, depending on which sources had delta that run.

2. **Time-relative metrics are always correct for every customer** — `customer_360` derives many fields from `CURRENT_DATE()`:
   - `days_since_last_activity`, `days_since_last_transaction`, `days_since_last_interaction`
   - `age`, `days_since_signup`
   - `customer_status` (`Active` → `At Risk` → `Dormant` transitions happen with the passage of time, not just on new events)
   - `customer_lifecycle_stage` (`Growing` → `Established` → `Mature` advances automatically)

   With incremental upsert, only customers with new silver data get reprocessed. A customer who goes quiet — no new transactions, no new interactions — never triggers a delta and their gold row is never updated. Their `customer_status` stays frozen as `'Active'` indefinitely even as they cross the 90-day and 180-day boundaries. Their `age` never increments past their birthday. **This is a silent correctness failure with real business impact.**

3. **Self-healing** — a bug fix in silver (or a threshold change in dbt vars) propagates to all 100k customer rows on the next run. With incremental, only affected customers get the fix; silent rows remain incorrect until explicitly reprocessed.

4. **Schema changes are trivial** — adding or removing a column is a `dbt build` away. Incremental models require `--full-refresh` for any schema change anyway, negating a run of incremental builds.

5. **Scales better than it looks** — the gold table grain is 1 row per customer. Silver has already done all aggregation. The hourly full refresh is a 4-way join of four pre-aggregated tables (each 100k rows), not a raw event scan. At millions of customers this is still a bounded, predictable join.

**Cons:**

1. **Compute scales with customer count, not delta** — if 500 customers had new data this hour, all 100k are still reprocessed. At very large scale (tens of millions of customers) this becomes expensive.
   *Counter-measure*: the incremental silver models absorb all event-volume work — gold only joins four pre-aggregated tables, each already collapsed to 1 row per customer. The full-refresh cost is bounded by customer count, not transaction or interaction volume. Photon is enabled on the hourly cluster, further reducing the join cost. At current scale this completes in well under the hourly window.

2. **VACUUM overhead** — each rebuild marks the previous files as deleted. Without cleanup, stale file versions accumulate (168 hourly rebuilds × ~3–5 files each between Sunday runs).
   *Counter-measure*: the weekly maintenance job (`workflow_weekly_maintenance.tf`) explicitly runs VACUUM on `customer_360` with 168-hour retention, clearing all stale file versions from the week's hourly rebuilds before they compound further.

---

#### Incremental Upsert (alternative)

| | |
|---|---|
| **How it works** | Detect which `customer_id`s changed in any silver source since the last gold run; re-join and merge only those rows |
| **Scales with** | Number of customers who had new data each run |

**Pros:**

1. **Compute scales with delta** — at large customer counts where only a fraction change each hour, incremental upsert is significantly cheaper per run.

2. **Better ceiling for very large datasets** — at 50M+ customers, a full-refresh hourly join may exceed the refresh window; incremental is the only viable path.

**Cons:**

1. **Change detection across four sources is complex** — to correctly identify affected `customer_id`s, you need watermarks or Delta Change Data Feed from `silver_customers`, `silver_customer_products`, `silver_customer_interactions`, and `silver_customer_transactions` simultaneously. Missed watermarks or CDC gaps mean stale rows in gold with no alert.

2. **Time-relative metrics go stale for quiet customers** — this is the fundamental problem described above. Every customer needs their derived time-relative fields recalculated on every run, regardless of whether they had new silver data. The only workaround is to force all customers into every incremental run — which is just a full refresh with extra complexity — or to move time-relative fields out of the stored table into a real-time view.

3. **Cross-source consistency is harder to guarantee** — if `silver_customer_interactions` has new data for customer A but `silver_customer_transactions` does not, the merged row for A would reflect today's interaction state but potentially yesterday's transaction state.

4. **Self-healing requires explicit backfill** — a bug fix or threshold change in dbt vars does not propagate automatically; a manual backfill is required to correct all affected rows.

---

#### Verdict

Full refresh is the right choice for `customer_360` at current and foreseeable scale. The decisive factor is not performance but **correctness**: the time-relative derived metrics (`customer_status`, `age`, lifecycle stage, etc.) must be recalculated for every customer on every run regardless of activity. An incremental upsert that only reprocesses active customers would silently misclassify dormant customers — which are precisely the customers most in need of accurate status data for churn and re-engagement decisions.

Incremental upsert becomes worth revisiting only if customer count grows to a scale where hourly full-refresh duration approaches or exceeds the refresh window, **and** time-relative metrics are refactored out of the stored table into a computed view.

---

## 3. Refresh Frequency — Hourly vs Daily

**Decision**: Silver and gold models are split across two schedules — daily full-refresh at 2 AM for dimension tables, hourly incremental for event-driven tables and gold.

| Model | Frequency | Reason |
|---|---|---|
| `silver_customers` | Daily 2 AM | Demographics (name, DOB, email) change rarely and never intraday — a correction takes effect the next morning, which is acceptable. Full refresh on 100k rows is fast and simpler than tracking incremental deletes (e.g. email corrections). `age` and `days_since_signup` are recalculated in gold on every hourly run, so stale silver demographics don't affect time-relative metrics. |
| `silver_customer_products` | Daily 2 AM | Product enrollments are low-frequency events — customers don't open or close accounts multiple times a day. A full refresh is appropriate because enrollment changes can include corrections or cancellations that are difficult to express as incremental upserts without CDC. New enrollments will flow into gold within the hour once the 2 AM rebuild completes. |
| `silver_customer_interactions` | Hourly | CRM agents log interactions in real time — a customer who contacts support at 9 AM should appear Active in gold by 10 AM. `days_since_last_interaction` feeds directly into `customer_status`; a stale silver row could hold a customer at `'Dormant'` for hours after they've re-engaged. Incremental merge on `customer_id` keeps hourly compute low — only customers with new interactions since the last watermark are reprocessed. |
| `silver_customer_transactions` | Hourly | Transactions drive `customer_status`, `customer_segment` (Premium ≥100k threshold), and `customer_value_segment` — all three affect real-time business decisions and BI dashboards. A large transaction processed at 2 PM should update a customer's segment before end-of-day reporting, not the following morning. Incremental merge is justified by source volume (887k+ rows) — only changed customers are reprocessed each hour, capping compute cost regardless of total table size. |
| `customer_360` | Hourly | Inherits from the hourly incrementals. Refreshing gold less frequently than its silver inputs would mean BI consumers see stale status/segment values even after silver has updated. |

**Scheduling dependency (enforced)**: The daily dimensions job runs at 2 AM; the hourly job's schedule deliberately **skips 2 AM** (`0 0 0-1,3-23 * * ?`). After the daily job rebuilds `silver_customers` and `silver_customer_products`, its final task triggers the hourly pipeline via a Databricks `run_job_task`, which waits for the full hourly run (incrementals → gold → tests) to complete. This makes the daily→hourly ordering explicit — the 2 AM gold build always sees fresh dimension data, and there is exactly one gold build at 2 AM. The other 23 hourly runs are unaffected. (Previously both jobs fired independently at 2 AM, leaving an implicit timing-based dependency where a long-running daily job could cause the 2 AM gold build to use the previous day's dimensions; that race is now removed.)

**Trade-off**: Running `silver_customers` and `silver_customer_products` hourly would also remove the dependency but adds unnecessary compute — demographics and product enrollments don't change at hourly granularity. Triggering the hourly pipeline from the daily job keeps dimensions on a daily cadence while still guaranteeing ordering.

See [`databricks-workflows/`](../terraform/databricks-workflows/) for the Terraform schedule configuration.

---

## 4. Clustering Strategy

Full analysis: [`docs/clustering_comparison.md`](clustering_comparison.md)

**Decision**: Liquid Clustering on `customer_id` for the **incremental silver tables** (`silver_customer_interactions`, `silver_customer_transactions`). Not applied to the gold table.

**Rationale for silver**: Each hourly MERGE needs to locate matching `customer_id` rows in the target table. With Liquid Clustering on `customer_id` (which is also the `unique_key`), Delta skips files that don't contain the affected IDs instead of scanning the whole table. Files accumulate across hourly runs, so clustering genuinely improves both MERGE performance and the downstream gold full-refresh join.

**Why not gold**: The gold table is a full refresh — every hourly rebuild wipes and rewrites all files from scratch. There is no accumulated disorder to cluster. At current scale (100k customers), the entire table fits in 2–5 Parquet files and every query reads them all regardless of layout. Liquid Clustering would also be lazy (clustering applied at OPTIMIZE time), but OPTIMIZE only runs weekly — meaning the gold table would be unclustered for up to 167 hours between maintenance runs. Revisit if customer count scales to millions and the table spans enough files for meaningful file skipping.

**Trade-off vs Z-Ordering**: Z-Ordering requires explicit `OPTIMIZE ZORDER BY` runs and degrades over time as new data arrives. Liquid Clustering is self-maintaining. See `clustering_comparison.md` for the full comparison.

---

## 5. `store_failures: true` Globally

**Decision**: All dbt tests run with `store_failures: true` (set in `dbt_project.yml`).

**Rationale**: Failed test rows are written to a dedicated audit table in Databricks (e.g. `dbt_test__audit.not_null_silver_customers_email`). This makes DQ failures inspectable and queryable without re-running the pipeline. Particularly important for the `unique` test on `silver_customers.email` — duplicate email pairs need investigation, not silent failure.

Test definitions: [`models/bronze/schema.yml`](../customer_360/models/bronze/schema.yml), [`models/silver/schema.yml`](../customer_360/models/silver/schema.yml), [`models/gold/schema.yml`](../customer_360/models/gold/schema.yml)

### 5.1 Audit Schema Cleanup — `DROP SCHEMA CASCADE` Daily

**Problem**: With ~169 tests all storing failures, every `dbt build` **overwrites** ~169 audit tables, and each overwrite leaves a fresh set of stale Delta files behind (the audit table only ever holds the *latest* run's failing rows). At hourly cadence these files compound fast, and they are never vacuumed. The cleanup job that drops them was running for a very long time because dropping a *managed* hive-metastore table is a **synchronous, per-file recursive delete** from object storage — multiplied across hundreds of tables, each carrying thousands of un-vacuumed files, in a serial loop.

**Decision**: Keep `store_failures: true` global, but have the daily maintenance job ([`cleanup_audit_tables.py`](../databricks-scripts/maintenance/cleanup_audit_tables.py), wired into `workflow_daily_dimensions.tf`) reclaim space with a single `DROP SCHEMA IF EXISTS <audit_schema> CASCADE`. dbt recreates the schema on the next test run that produces failures.

**Why this over the alternatives**: Scoping `store_failures` to a handful of tests would go further (it stops the files being created at all), but it requires per-test judgement about which failures are worth persisting and changes test artifact behaviour. Daily `DROP SCHEMA CASCADE` is cheaper to ship and keeps every audit table available for inspection.

**Pros**
- Simplest possible cleanup — one catalog statement, no `SHOW TABLES`, no per-table loop or round-trips.
- Self-healing: dbt re-creates the schema and tables as needed, so it also resolves the Unity Catalog table-quota concern.
- Daily cadence caps accumulation at ~24 rewrites/table before cleanup, so file counts never pile up to the multi-hour-drop levels seen before.
- Keeps full failure-row inspectability for *all* tests (no behaviour change vs. the previous design).

**Cons**
- Does **not** go "under the floor": files are still created on every run and still physically deleted on every cleanup. The synchronous per-file deletion cost remains — it's just bounded to one day's churn instead of weeks/months, and paid once per day off-peak.
- The audit schema is fully dropped, so failure rows are only retained until the next daily cleanup — fine for triage within a day, not for long-term history.
- Relies on dbt recreating the schema; if a downstream process expects the audit schema to always exist between runs, it must tolerate its absence.
- `CASCADE` is blunt: anything that ends up in that schema is removed, so the schema must remain dedicated to dbt test audits.

---

## 6. Bronze Ingestion: Case Study vs Production


The current implementation treats bronze ingestion as a **one-time manual seed** (`databricks-scripts/ingest_bronze.py`) — CSV files are loaded once into Delta tables and that is the starting point for the dbt pipeline.

In production this is not the case. Each source table would need a continuous ingestion pattern appropriate to its source system:

| Source Table | Likely production pattern | Open questions |
|---|---|---|
| `customer_raw` | Batch (daily CRM export or CDC) | Is CDC enabled on the CRM database? |
| `product_enrollments` | Batch or event-driven | Does enrollment trigger an event or is it polled? |
| `crm_interactions` | Near real-time or streaming | Does the CRM expose a Kafka topic or REST API? |
| `transaction_history` | Streaming or micro-batch | Is the transaction system CDC-enabled? What is the SLA? |

The bronze models and `ingest_bronze.py` would need to be redesigned once source system details are confirmed. Until those details are known, **the ingestion layer should be treated as a placeholder**.

The dbt incremental models (`silver_customer_interactions`, `silver_customer_transactions`, `customer_360`) are already designed for continuous ingestion — they use `_ingested_at` watermarks and merge on `customer_id`. Only the bronze ingestion mechanism needs to change; the dbt layer is production-ready.

---

## 7. No Deduplication by Email

**Decision**: `silver_customers` does NOT deduplicate by email. `customer_id` is the true PK.

**Rationale**: 3 email addresses are shared across 6 distinct customers (different names, genders, dates of birth). These are real, separate people. Deduplicating by email would incorrectly merge valid customers and collapse their product holdings, transactions, and interaction histories. The `unique` test with `store_failures: true` flags duplicates for investigation without polluting the model with a flag column.

See [`data_quality.md`](data_quality.md) Issue 2.

---

## 8. `dbt build` over `dbt run` in Production Workflows

**Decision**: All Databricks workflow tasks use `dbt build` instead of `dbt run` + a separate `dbt test` task.

**Rationale**: `dbt build` runs the model and its tests in sequence, blocking downstream tasks on failure. With `dbt run` + `dbt test` as separate tasks, a test failure sends an alert but all models have already been built — bad data in `silver_customers` (the FK anchor for all other silver models) would propagate into `silver_customer_products` and `customer_360` before the failure is caught. In an hourly pipeline, that means up to an hour of a corrupted gold table serving BI consumers.

**Exception**: The custom business rule tests (`assert_*`) are singular tests — standalone DAG nodes with no model to build. They run as dedicated `dbt test` tasks, split by layer rather than lumped at the end:

| Task | Runs after | Selects |
|---|---|---|
| `test_bronze` | (start of hourly run) | `assert_transaction_product_customer_match` — bronze referential integrity gates both silver builds |
| `test_silver` | `build_silver_interactions` + `build_silver_transactions` | `assert_customer_360_transaction_values_consistent` — silver invariants gate gold build |
| `test_gold` | `build_gold_customer_360` | `assert_no_negative_counts`, `assert_active_customers_have_recent_activity`, `assert_premium_customers_meet_criteria` |

This fail-fast ordering means bad silver data never reaches gold, and a bronze integrity failure blocks the entire run before any compute is wasted.

**Trade-off**: `dbt build` is a harder failure mode — a flaky test will block the entire downstream refresh. Teams that prefer soft failures (build everything, alert but don't block) should use `dbt run` + `dbt test` explicitly. For this pipeline, data correctness takes priority over refresh availability.

See [`databricks-workflows/`](../terraform/databricks-workflows/) for the Terraform implementation.

---

## 9. Separate Backfill Pipeline

**Decision**: A dedicated backfill Databricks job exists alongside the hourly and daily production jobs. It is `PAUSED` by default and triggered manually (or via CI) — never on a schedule.

**When to trigger:**
- Bug fix in transformation logic that affects historical records
- Business rule change (e.g. segmentation thresholds updated)
- Source data correction upstream
- New column added to an incremental silver model
- Initial historical load on first deployment

**Why not Lambda architecture**: Lambda would maintain a separate batch layer running the same transformations on a slower cadence. That means two codepaths to maintain, two sets of results to reconcile, and two places for logic to diverge. The backfill job uses the exact same dbt models as production — there is no separate batch layer.

**Why not pure Kappa architecture**: Pure Kappa replays raw events through the same streaming pipeline for both real-time and historical reprocessing. This works cleanly for event-level models but breaks down here because silver models aggregate to customer grain (`GROUP BY customer_id`). Replaying only new events cannot correctly recompute aggregates for customers whose historical records are affected — a full recompute per customer is always required. Storing pre-aggregation raw events in silver to enable true event replay would add complexity without benefit given the current grain.

**Mechanism**: The backfill job accepts two parameters at trigger time — `backfill_start` (inclusive) and `backfill_end` (exclusive).

| Parameters provided | Behaviour |
|---|---|
| `backfill_start` + `backfill_end` | Windowed backfill — identifies affected `customer_id`s from the window, recomputes full history for those customers, merges. Unaffected customers untouched. |
| Neither | Full refresh — drops and rebuilds the entire table from scratch. Nuclear option for schema changes or initial loads. |

```sql
-- Pattern in silver incremental models
{% if var('backfill_start', '') | trim != '' %}
    AND customer_id IN (
        SELECT DISTINCT customer_id FROM {{ ref('bronze_...') }}
        WHERE _ingested_at >= '{{ var("backfill_start") }}'
          AND _ingested_at <  '{{ var("backfill_end") }}'
    )
{% elif is_incremental() %}
    AND _ingested_at > (SELECT MAX(_ingested_at) FROM {{ this }})
{% endif %}
-- No branch = full refresh (dbt handles via --full-refresh flag)
```

`silver_customers` and `silver_customer_products` are excluded — they are full-refresh tables rebuilt by the daily job and do not need backfill.

**Why trace to exact date rather than always full-refresh**: Full refresh reprocesses 887k+ transactions regardless of how many records were actually affected. In production, a bug is typically traced to a specific ingestion batch — backfilling only that window is faster, leaves unaffected customers untouched, and reduces the blast radius if the backfill itself has an issue.

See [`workflow_backfill.tf`](../terraform/databricks-workflows/workflow_backfill.tf) for the Terraform implementation.

---

## 10. Performance Optimization Strategies

### 10.1 Liquid Clustering (Incremental Silver Tables)

Covered in detail in §4 and [`clustering_comparison.md`](clustering_comparison.md). The short version: Liquid Clustering on `customer_id` is applied to the incremental silver tables — no manual `OPTIMIZE ZORDER BY` job needed. MERGE operations and the downstream gold join both benefit from file co-location on the cluster key.

### 10.2 Small File Compaction (Incremental Silver Tables)

`silver_customer_interactions` and `silver_customer_transactions` use incremental merge. Each hourly run writes a small set of new/updated Parquet files. Over time this accumulates small files, degrading read performance for the gold full-refresh join.

**Mitigation**: Run `OPTIMIZE` on both tables once per day as part of the daily 2 AM job (`workflow_daily_dimensions.tf`), in parallel with the dimension table builds.

```sql
OPTIMIZE silver_customer_interactions;
OPTIMIZE silver_customer_transactions;
```

**Why daily and not hourly**: Each hourly incremental delta is small — only changed customers are written, producing a handful of files per run. Reading 100k pre-aggregated silver rows across a day's worth of small files is still fast; the gold full-refresh is not meaningfully degraded within a single day. Running `OPTIMIZE` after every hourly merge would cost 24× the compute for diminishing returns. Daily compaction caps fragmentation at 24 hourly file sets and resets it each morning before the next day's runs begin.

The weekly maintenance job (`workflow_weekly_maintenance.tf`) runs an additional `OPTIMIZE` pass on Sundays — on an already-compacted table this is effectively a no-op, but it serves as a safety net and also triggers `VACUUM` to remove old file versions.

**Target file size**: Delta defaults to 128 MB per file. No override is applied here — the default is appropriate for the current data volume. Revisit if table size exceeds ~100 GB.

### 10.3 Bronze as Views — Re-read Risk

All bronze models are `view`. This means every dbt model that references a bronze view re-executes a full scan of the underlying raw Delta table at query time. In this pipeline each bronze table is referenced by exactly one silver model, so there is no fan-out problem today.

**Risk**: If a future model references the same bronze view twice in the same run (e.g. a new silver model that self-joins bronze_transaction_history), the raw table will be scanned twice. The mitigation is to materialise that bronze model as a `table` or use `{{ this }}` caching — but this is not a current issue.

### 10.4 Photon Accelerator

The Databricks workflows are provisioned on clusters with Photon enabled (see [`workflow_hourly_incremental.tf`](../terraform/databricks-workflows/workflow_hourly_incremental.tf)). Photon provides the largest gains for:

- The gold full-refresh join (4-way join across silver tables)
- `OPTIMIZE` compaction on the incremental silver tables
- `silver_customer_transactions` aggregations (`SUM`, `MAX`, `MIN`, `AVG`, `MAX_BY` over 887k+ rows)

The backfill job also runs on a Photon cluster — full-refresh backfills on the transactions table are the most compute-intensive operation in the pipeline.

### 10.5 Cluster Sizing

| Job | Cluster type | Rationale |
|-----|-------------|-----------|
| Hourly incremental | Single-node or small multi-node | Incremental silver merges touch a small subset of customers per run; gold full-refresh is a join of pre-aggregated silver tables (one row per customer) — low shuffle |
| Daily full-refresh | Same as hourly | `silver_customers` and `silver_customer_products` are ≤100k rows — no need for large cluster |
| Backfill | Larger multi-node | Full-refresh of 887k+ transaction rows with aggregation; higher parallelism justified |

Cluster sizes are defined in Terraform and should be reviewed if source volumes grow significantly beyond current levels.

### 10.6 Delta Result Caching

Databricks caches Delta table scan results in memory on the cluster. The gold table (`customer_360`) benefits from this when BI tools issue repeated queries within the same cluster session — the first query pays the scan cost, subsequent queries are served from cache.

**Implication for scheduling**: The hourly gold rebuild invalidates the cache. BI queries issued immediately after a rebuild will pay a full scan. If query latency at the top of the hour is a concern, consider pre-warming the cache by running a lightweight `SELECT COUNT(*) FROM customer_360` as a post-build step.

---

## 11. Production Readiness Gaps

The following items are known gaps between the current implementation and a fully hardened production deployment.

### 11.1 PII Exposure — No Column Masking or Row-Level Security

**Gap**: The gold table exposes sensitive personal data — `first_name`, `last_name`, `email`, `date_of_birth`, `mobile_clean` — without column-level masking or row-level security (RLS). Any principal with `SELECT` on `customer_360` reads raw PII.

**Risk**: In a banking context this is a compliance exposure (GDPR, BSP, or equivalent data protection obligations). An analytics team member should not have the same access to raw names and dates of birth as a regulated marketing system.

**Remediation options**:
1. **Dynamic data masking** (Unity Catalog): Attach a masking policy to PII columns so non-privileged roles see a tokenised or redacted value.
2. **Row-level security** (Unity Catalog row filters): Restrict visible rows per role if customer-level access scoping is required (e.g. relationship managers seeing only their portfolio).
3. **Separate analytics view**: Create a non-PII view over `customer_360` that excludes or hashes identifying columns for self-serve analytics consumers.

Until one of these is in place, access to `customer_360` should be restricted to explicitly approved service accounts and data engineers.

### 11.2 Data Freshness — Defined but Not Enforced

**Current state**: `sources.yml` defines source freshness thresholds (`warn_after: 24h`, `error_after: 48h` on `_ingested_at`), and `_gold_updated_at` is tracked per row. However, no workflow runs `dbt source freshness`, so the thresholds are never evaluated and no alert fires if a scheduled run is delayed or missed.

**Risk**: BI consumers have no reliable signal that the data is current. A failed hourly run goes undetected until a downstream user notices a stale `customer_status` or `customer_segment` value.

**Remediation**:
1. Tighten the per-source SLA to match the refresh cadence — the current 24h/48h are placeholders; the hourly feeds (`crm_interactions`, `transaction_history`) should be no more than ~90 minutes stale.
2. Wire a `dbt source freshness` task into the hourly job so the thresholds already in `sources.yml` are actually evaluated.
3. Add a Databricks workflow alert (email or PagerDuty) on job failure and a post-build check that errors if `MAX(_gold_updated_at)` is older than the SLA window.
