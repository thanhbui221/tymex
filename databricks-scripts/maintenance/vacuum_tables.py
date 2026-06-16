# Databricks notebook source
# Maintenance script: VACUUM Delta tables

from pyspark.sql import SparkSession

# Notebook tasks receive parameters via widgets (base_parameters in the workflow),
# not sys.argv — argv holds the kernel launch args in this context. The workflow
# passes the schema under the "schema" key.
dbutils.widgets.text("schema", "", "Schema whose tables to vacuum")
dbutils.widgets.text("retention_hours", "168", "Vacuum retention window in hours")

database_name = dbutils.widgets.get("schema") or None
retention_hours = int(dbutils.widgets.get("retention_hours") or 168)  # Default 7 days

if not database_name:
    raise ValueError("Database name parameter is required")

print(f"Running VACUUM on tables in {database_name}")
print(f"Retention hours: {retention_hours}")

spark = SparkSession.builder.getOrCreate()

# Get all tables in database
tables = spark.sql(f"SHOW TABLES IN {database_name}").collect()

for table in tables:
    table_name = f"{database_name}.{table.tableName}"
    try:
        print(f"Vacuuming {table_name}...")
        spark.sql(f"VACUUM {table_name} RETAIN {retention_hours} HOURS")
        print(f"✓ Successfully vacuumed {table_name}")
    except Exception as e:
        print(f"✗ Failed to vacuum {table_name}: {str(e)}")

print("VACUUM complete")
