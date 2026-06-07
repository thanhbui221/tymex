# Databricks notebook source
# Maintenance script: OPTIMIZE Delta tables

import sys
from pyspark.sql import SparkSession

# Get table name parameter
table_name = sys.argv[1] if len(sys.argv) > 1 else None

if not table_name:
    raise ValueError("Table name parameter is required")

print(f"Running OPTIMIZE on {table_name}")

spark = SparkSession.builder.getOrCreate()

try:
    # Run OPTIMIZE
    spark.sql(f"OPTIMIZE {table_name}")
    print(f"Successfully optimized {table_name}")

except Exception as e:
    raise Exception(f"Failed to optimize {table_name}: {str(e)}")
