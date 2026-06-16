# Databricks notebook source
# Maintenance script: OPTIMIZE Delta tables

from pyspark.sql import SparkSession

# Notebook tasks receive parameters via widgets (base_parameters in the workflow),
# not sys.argv — argv holds the kernel launch args in this context.
dbutils.widgets.text("table_name", "", "Fully-qualified table to optimize")
table_name = dbutils.widgets.get("table_name") or None

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
