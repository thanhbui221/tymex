# Databricks notebook source
# Maintenance script: Drop the dbt test audit schema to reclaim space.
#
# dbt store_failures: true writes failing rows into the audit schema and
# overwrites every audit table on each test run, accumulating stale Delta files
# that are never cleaned. Run daily so file counts never pile up between cleanups.
#
# DROP SCHEMA ... CASCADE removes all audit tables in a single catalog operation
# (no per-table loop / round-trips). dbt recreates the schema on the next test
# run that produces failures.
#
# Parameters:
#   audit_schema — schema to clean, e.g. "customer_360_db_dbt_test__audit"

from pyspark.sql import SparkSession

# Notebook tasks receive parameters via widgets (base_parameters in the workflow),
# not sys.argv — argv holds the kernel launch args in this context.
dbutils.widgets.text("audit_schema", "", "Audit schema to drop")
audit_schema = dbutils.widgets.get("audit_schema") or None

if not audit_schema:
    raise ValueError("audit_schema parameter is required")

spark = SparkSession.builder.getOrCreate()

# Skip gracefully if the schema hasn't been created yet (first run, no failures)
existing_schemas = [row.databaseName for row in spark.sql("SHOW DATABASES").collect()]
if audit_schema not in existing_schemas:
    print(f"Schema {audit_schema} does not exist — nothing to clean")
else:
    spark.sql(f"DROP SCHEMA IF EXISTS {audit_schema} CASCADE")
    print(f"Dropped schema {audit_schema}")
