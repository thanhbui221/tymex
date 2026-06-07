# Databricks notebook source
# Maintenance script: VACUUM Delta tables

import sys
from pyspark.sql import SparkSession

# Get parameters
database_name = sys.argv[1] if len(sys.argv) > 1 else None
retention_hours = int(sys.argv[2]) if len(sys.argv) > 2 else 168  # Default 7 days

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
