from pyspark.sql import functions as F

base_path = "file:/Workspace/Users/thanhbui22198@gmail.com/customer_360"

spark.sql("CREATE DATABASE IF NOT EXISTS customer_360_db")

def load_raw(csv_path, table_name, **read_opts):
    df = spark.read.csv(csv_path, header=True, inferSchema=True, sep="|", **read_opts)
    df = df.withColumn("_ingested_at", F.current_timestamp())
    df.write.mode("overwrite").option("overwriteSchema", "true").saveAsTable(f"customer_360_db.{table_name}")

# dbt bronze views wrap these raw tables under the bronze_* names
load_raw(f"{base_path}/customer_raw.csv",          "customer_raw")
load_raw(f"{base_path}/product_enrollments.csv",   "product_enrollments")
load_raw(f"{base_path}/crm_interactions.csv",      "crm_transactions")
load_raw(f"{base_path}/transaction_history/*.csv", "transaction_history")
