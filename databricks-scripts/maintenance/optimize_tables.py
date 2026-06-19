# Databricks notebook source
# Maintenance script: OPTIMIZE Delta tables

from pyspark.sql import SparkSession

# Notebook tasks receive parameters via widgets (base_parameters in the workflow),
# not sys.argv — argv holds the kernel launch args in this context.
dbutils.widgets.text("table_name", "", "Fully-qualified table to optimize")
dbutils.widgets.text("zorder_by", "", "Optional comma-separated columns for ZORDER BY")
table_name = dbutils.widgets.get("table_name") or None
zorder_by = dbutils.widgets.get("zorder_by") or None

if not table_name:
    raise ValueError("Table name parameter is required")

print(f"Running OPTIMIZE on {table_name}" + (f" ZORDER BY ({zorder_by})" if zorder_by else ""))

spark = SparkSession.builder.getOrCreate()

try:
    sql = f"OPTIMIZE {table_name}"
    if zorder_by:
        sql += f" ZORDER BY ({zorder_by})"
    spark.sql(sql)
    print(f"Successfully optimized {table_name}")

except Exception as e:
    raise Exception(f"Failed to optimize {table_name}: {str(e)}")
