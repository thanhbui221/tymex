# Databricks notebook source
# Maintenance script: Truncate and vacuum dbt test audit tables.
#
# dbt store_failures: true writes failing rows into the audit schema but never
# removes them. This script truncates all tables in the schema weekly to prevent
# unbounded growth, then vacuums to remove stale file versions from prior writes.
#
# Parameters:
#   audit_schema    — schema to clean, e.g. "customer_360_db_dbt_test__audit"
#   retention_hours — vacuum retention window (default 168 = 7 days)

import sys
from pyspark.sql import SparkSession

audit_schema    = sys.argv[1] if len(sys.argv) > 1 else None
retention_hours = int(sys.argv[2]) if len(sys.argv) > 2 else 168

if not audit_schema:
    raise ValueError("audit_schema parameter is required")

spark = SparkSession.builder.getOrCreate()

# Skip gracefully if the schema hasn't been created yet (first run, no failures)
existing_schemas = [row.databaseName for row in spark.sql("SHOW DATABASES").collect()]
if audit_schema not in existing_schemas:
    print(f"Schema {audit_schema} does not exist — nothing to clean")
    sys.exit(0)

tables = spark.sql(f"SHOW TABLES IN {audit_schema}").collect()

if not tables:
    print(f"No tables in {audit_schema} — nothing to clean")
    sys.exit(0)

print(f"Cleaning {len(tables)} audit table(s) in {audit_schema}")

errors = []
for table in tables:
    table_name = f"{audit_schema}.{table.tableName}"
    try:
        # DROP rather than TRUNCATE — removes the table object itself so it doesn't
        # count against the Unity Catalog table quota. dbt recreates audit tables on
        # the next test run only when failures occur.
        spark.sql(f"DROP TABLE IF EXISTS {table_name}")
        print(f"✓ {table_name}")
    except Exception as e:
        print(f"✗ {table_name}: {e}")
        errors.append(table_name)

if errors:
    raise Exception(f"Cleanup failed for: {', '.join(errors)}")

print("Audit table cleanup complete")
