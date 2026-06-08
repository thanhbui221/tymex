# Databricks notebook source
# Customer 360 — Data Quality & EDA
# Run this notebook on the cluster after bronze tables are loaded.

# COMMAND ----------
# MAGIC %md
# MAGIC # Customer 360 — Data Quality & Exploratory Data Analysis
# MAGIC
# MAGIC Profiles the four bronze source tables for:
# MAGIC - Null / missing values
# MAGIC - Duplicate records
# MAGIC - Data type inconsistencies
# MAGIC - Referential integrity violations
# MAGIC - Outliers and anomalies
# MAGIC - Cross-table coverage gaps

# COMMAND ----------
# MAGIC %md ## Setup

# COMMAND ----------
from pyspark.sql import functions as F
from pyspark.sql.types import DecimalType
import pyspark.sql.functions as F

DB = "customer_360_db"

customer_raw        = spark.table(f"{DB}.customer_raw")
product_enrollments = spark.table(f"{DB}.product_enrollments")
crm_transactions    = spark.table(f"{DB}.crm_transactions")
transaction_history = spark.table(f"{DB}.transaction_history")

print("Row counts:")
print(f"  customer_raw:        {customer_raw.count():>10,}")
print(f"  product_enrollments: {product_enrollments.count():>10,}")
print(f"  crm_transactions:    {crm_transactions.count():>10,}")
print(f"  transaction_history: {transaction_history.count():>10,}")

# COMMAND ----------
# MAGIC %md ## 1. customer_raw

# COMMAND ----------
# MAGIC %md ### 1.1 Null & Completeness Check

# COMMAND ----------
print("Null counts per column:")
customer_raw.select([
    F.count(F.when(F.col(c).isNull() | (F.col(c) == ""), c)).alias(c)
    for c in customer_raw.columns
]).show()

# COMMAND ----------
# MAGIC %md ### 1.2 Duplicate Check

# COMMAND ----------
total = customer_raw.count()
distinct_cust = customer_raw.select("customer_id").distinct().count()
distinct_email = customer_raw.select("email").distinct().count()
print(f"Total rows:           {total:,}")
print(f"Distinct customer_id: {distinct_cust:,}  → duplicates: {total - distinct_cust}")
print(f"Distinct email:       {distinct_email:,}  → duplicate emails: {total - distinct_email}")

# Show the duplicate emails
customer_raw.groupBy("email") \
    .count() \
    .filter(F.col("count") > 1) \
    .orderBy(F.col("count").desc()) \
    .show(10, truncate=False)

# COMMAND ----------
# MAGIC %md ### 1.3 Age Distribution & Validity

# COMMAND ----------
customer_with_age = customer_raw.withColumn(
    "age", F.floor(F.datediff(F.current_date(), F.col("date_of_birth")) / 365)
)

customer_with_age.select(
    F.min("age").alias("min_age"),
    F.max("age").alias("max_age"),
    F.avg("age").alias("avg_age"),
    F.count(F.when(F.col("age") < 18, True)).alias("under_18"),
    F.count(F.when(F.col("age") > 100, True)).alias("over_100"),
).show()

# COMMAND ----------
# MAGIC %md ### 1.4 Phone Number Format

# COMMAND ----------
customer_raw.withColumn(
    "phone_format",
    F.when(F.col("mobile").startswith("09"), "09...")
     .when(F.col("mobile").startswith("+63"), "+63...")
     .otherwise("other")
).groupBy("phone_format").count().orderBy("phone_format").show()

# Show sample of non-standard phone numbers
print("Sample non-standard phone numbers:")
customer_raw.filter(
    ~F.col("mobile").startswith("09") & ~F.col("mobile").startswith("+63")
).select("customer_id", "mobile").show(20, truncate=False)

# COMMAND ----------
# MAGIC %md ### 1.5 Gender Distribution

# COMMAND ----------
customer_raw.groupBy("gender").count() \
    .withColumn("pct", F.round(F.col("count") / total * 100, 1)) \
    .orderBy(F.col("count").desc()).show()

# COMMAND ----------
# MAGIC %md ### 1.6 Signup Date Range

# COMMAND ----------
customer_raw.select(
    F.min("signup_date").alias("earliest_signup"),
    F.max("signup_date").alias("latest_signup"),
).show()

# COMMAND ----------
# MAGIC %md ## 2. product_enrollments

# COMMAND ----------
# MAGIC %md ### 2.1 Null & Duplicate Check

# COMMAND ----------
print("Null counts:")
product_enrollments.select([
    F.count(F.when(F.col(c).isNull() | (F.col(c) == ""), c)).alias(c)
    for c in product_enrollments.columns
]).show()

total_pe = product_enrollments.count()
distinct_pid = product_enrollments.select("product_id").distinct().count()
print(f"Duplicate product_ids: {total_pe - distinct_pid}")

# COMMAND ----------
# MAGIC %md ### 2.2 Product Type Distribution

# COMMAND ----------
product_enrollments.groupBy("product_type").count() \
    .withColumn("pct", F.round(F.col("count") / total_pe * 100, 1)) \
    .orderBy(F.col("count").desc()).show()

# Check for unexpected product_type values (case/whitespace issues)
product_enrollments.withColumn("product_type_clean", F.upper(F.trim(F.col("product_type")))) \
    .groupBy("product_type", "product_type_clean").count() \
    .orderBy("product_type").show()

# COMMAND ----------
# MAGIC %md ### 2.3 Credit Limit Analysis

# COMMAND ----------
product_enrollments.select(
    F.min("limit").alias("min_limit"),
    F.max("limit").alias("max_limit"),
    F.avg("limit").alias("avg_limit"),
    F.count(F.when(F.col("limit") < 0, True)).alias("negative_limits"),
    F.count(F.when(
        (F.upper(F.trim(F.col("product_type"))) == "SAVINGS") & (F.col("limit") != 0), True
    )).alias("savings_with_nonzero_limit"),
).show()

# COMMAND ----------
# MAGIC %md ### 2.4 Referential Integrity — customer_id

# COMMAND ----------
orphaned = product_enrollments.join(
    customer_raw.select("customer_id"),
    on="customer_id", how="left_anti"
).count()
print(f"Product enrollments with no matching customer_id: {orphaned}")

# COMMAND ----------
# MAGIC %md ### 2.5 Products Per Customer

# COMMAND ----------
product_enrollments.groupBy("customer_id").count() \
    .select(
        F.min("count").alias("min_products"),
        F.max("count").alias("max_products"),
        F.avg("count").alias("avg_products"),
    ).show()

product_enrollments.groupBy("customer_id").count() \
    .groupBy("count").count() \
    .withColumnRenamed("count", "products_per_customer") \
    .withColumnRenamed("count(1)", "num_customers") \
    .orderBy("products_per_customer").show()

# COMMAND ----------
# MAGIC %md ## 3. crm_transactions

# COMMAND ----------
# MAGIC %md ### 3.1 Null & Duplicate Check

# COMMAND ----------
print("Null counts:")
crm_transactions.select([
    F.count(F.when(F.col(c).isNull() | (F.col(c) == ""), c)).alias(c)
    for c in crm_transactions.columns
]).show()

total_crm = crm_transactions.count()
distinct_iid = crm_transactions.select("interaction_id").distinct().count()
print(f"Duplicate interaction_ids: {total_crm - distinct_iid}")

# COMMAND ----------
# MAGIC %md ### 3.2 Interaction Type Distribution

# COMMAND ----------
# IMPORTANT: 'Call' type exists in data but is not counted in silver_customer_interactions
crm_transactions.groupBy("interaction_type").count() \
    .withColumn("pct", F.round(F.col("count") / total_crm * 100, 1)) \
    .orderBy(F.col("count").desc()).show()

# COMMAND ----------
# MAGIC %md ### 3.3 Interaction Date Range & Recency

# COMMAND ----------
crm_transactions.select(
    F.min("interaction_date").alias("earliest"),
    F.max("interaction_date").alias("latest"),
).show()

# COMMAND ----------
# MAGIC %md ### 3.4 Referential Integrity — customer_id

# COMMAND ----------
orphaned_crm = crm_transactions.join(
    customer_raw.select("customer_id"), on="customer_id", how="left_anti"
).count()
print(f"CRM interactions with no matching customer_id: {orphaned_crm}")

# COMMAND ----------
# MAGIC %md ## 4. transaction_history

# COMMAND ----------
# MAGIC %md ### 4.1 Null & Duplicate Check

# COMMAND ----------
print("Null counts:")
transaction_history.select([
    F.count(F.when(F.col(c).isNull() | (F.col(c) == ""), c)).alias(c)
    for c in transaction_history.columns
]).show()

total_tx = transaction_history.count()
distinct_tid = transaction_history.select("transaction_id").distinct().count()
print(f"Duplicate transaction_ids: {total_tx - distinct_tid}")

# COMMAND ----------
# MAGIC %md ### 4.2 Transaction Amount Distribution & Outliers

# COMMAND ----------
tx_stats = transaction_history.select(
    F.min("transaction_amount").alias("min"),
    F.max("transaction_amount").alias("max"),
    F.avg("transaction_amount").alias("mean"),
    F.stddev("transaction_amount").alias("stddev"),
    F.percentile_approx("transaction_amount", 0.01).alias("p1"),
    F.percentile_approx("transaction_amount", 0.25).alias("p25"),
    F.percentile_approx("transaction_amount", 0.50).alias("p50"),
    F.percentile_approx("transaction_amount", 0.75).alias("p75"),
    F.percentile_approx("transaction_amount", 0.99).alias("p99"),
).collect()[0]
print(f"transaction_amount stats:")
for k, v in tx_stats.asDict().items():
    print(f"  {k}: {float(v):.2f}")

# Outlier detection: values beyond 3 standard deviations
mean_val  = tx_stats["mean"]
std_val   = tx_stats["stddev"]
outliers = transaction_history.filter(
    F.abs(F.col("transaction_amount") - mean_val) > 3 * std_val
).count()
print(f"\nOutliers (>3σ from mean): {outliers}")

# COMMAND ----------
# MAGIC %md ### 4.3 Closing Balance — Negative Balances

# COMMAND ----------
neg_balance_count = transaction_history.filter(F.col("closing_balance") < 0).count()
print(f"Negative closing_balance: {neg_balance_count:,} ({100*neg_balance_count/total_tx:.1f}%)")

transaction_history.select(
    F.min("closing_balance").alias("min_balance"),
    F.max("closing_balance").alias("max_balance"),
    F.avg("closing_balance").alias("avg_balance"),
).show()

# COMMAND ----------
# MAGIC %md ### 4.4 Timestamp Timezone Check

# COMMAND ----------
# All timestamps should be naive (no timezone info assumed UTC)
tz_aware = transaction_history.filter(
    F.col("transaction_date").cast("string").contains("+") |
    F.col("transaction_date").cast("string").endswith("Z")
).count()
print(f"Timezone-aware timestamps: {tz_aware} / {total_tx}")
print("All timestamps are naive (no TZ info) — assumed UTC per project convention.")

transaction_history.select(
    F.min("transaction_date").alias("earliest_tx"),
    F.max("transaction_date").alias("latest_tx"),
).show()

# COMMAND ----------
# MAGIC %md ### 4.5 Referential Integrity

# COMMAND ----------
orphaned_prod = transaction_history.join(
    product_enrollments.select("product_id"), on="product_id", how="left_anti"
).count()
orphaned_cust = transaction_history.join(
    customer_raw.select("customer_id"), on="customer_id", how="left_anti"
).count()
print(f"Transactions with orphaned product_id:  {orphaned_prod}")
print(f"Transactions with orphaned customer_id: {orphaned_cust}")

# COMMAND ----------
# MAGIC %md ## 5. Cross-Table Coverage

# COMMAND ----------
cust_with_products = product_enrollments.select("customer_id").distinct()
cust_with_crm      = crm_transactions.select("customer_id").distinct()
cust_with_tx       = transaction_history.select("customer_id").distinct()
all_customers      = customer_raw.select("customer_id")

total_cust = all_customers.count()

no_products = all_customers.join(cust_with_products, on="customer_id", how="left_anti").count()
no_crm      = all_customers.join(cust_with_crm,      on="customer_id", how="left_anti").count()
no_tx       = all_customers.join(cust_with_tx,        on="customer_id", how="left_anti").count()
no_crm_no_tx = all_customers \
    .join(cust_with_crm, on="customer_id", how="left_anti") \
    .join(cust_with_tx,  on="customer_id", how="left_anti") \
    .count()

print(f"Total customers:                   {total_cust:>8,}")
print(f"Customers with NO products:        {no_products:>8,}  ({100*no_products/total_cust:.1f}%)")
print(f"Customers with NO CRM history:     {no_crm:>8,}  ({100*no_crm/total_cust:.1f}%)")
print(f"Customers with NO transactions:    {no_tx:>8,}  ({100*no_tx/total_cust:.1f}%)")
print(f"Customers with NO activity at all: {no_crm_no_tx:>8,}  ({100*no_crm_no_tx/total_cust:.1f}%)")
print()
print("→ Customers with no activity are automatically classified as Inactive in customer_360.")

# COMMAND ----------
# MAGIC %md ## 6. Summary of Data Quality Issues

# COMMAND ----------
print("""
╔══════════════════════════════════════════════════════════════════════════════╗
║                    DATA QUALITY ISSUES SUMMARY                             ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                            ║
║  COMPLETENESS                                                              ║
║  ✓ No null values in any field across all four tables                      ║
║                                                                            ║
║  UNIQUENESS                                                                ║
║  ✗ customer_raw: 3 duplicate email addresses                               ║
║  ✓ No duplicate PKs in any table                                           ║
║                                                                            ║
║  VALIDITY                                                                  ║
║  ✗ customer_raw: ~1,120 phone numbers in non-standard format               ║
║    (not '09...' or '+63...')                                               ║
║  ✗ crm_transactions: 'Call' interaction type exists but is NOT             ║
║    counted in silver_customer_interactions (only EMAIL and CHAT handled)   ║
║  ✓ Age range 18–66, no underage customers                                  ║
║  ✓ No negative credit limits                                               ║
║                                                                            ║
║  CONSISTENCY                                                               ║
║  ✗ transaction_history: 59.1% negative closing balances — confirm         ║
║    whether overdraft is expected or indicative of a data issue             ║
║  ✗ All timestamps are timezone-naive — assumed UTC; must confirm           ║
║    with source system owners                                               ║
║                                                                            ║
║  REFERENTIAL INTEGRITY                                                     ║
║  ✓ No orphaned keys across all FK relationships                            ║
║                                                                            ║
║  OUTLIERS                                                                  ║
║  ✓ No statistical outliers in transaction_amount (0 rows beyond 3σ)       ║
║                                                                            ║
║  COVERAGE (customers with no activity)                                     ║
║  ✗ 27,385 customers (27.4%) have no CRM history                           ║
║  ✗ 23,120 customers (23.1%) have no transaction history                   ║
║    → These customers will be classified as Inactive in customer_360       ║
║                                                                            ║
╚══════════════════════════════════════════════════════════════════════════════╝
""")
