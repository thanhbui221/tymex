# Daily workflow: Refresh slow-changing dimension tables
resource "databricks_job" "daily_dimensions_refresh" {
  name = "Customer360 - Daily Dimensions Refresh"

  schedule {
    quartz_cron_expression = "0 0 2 * * ?"  # 2 AM daily
    timezone_id            = "UTC"
    pause_status           = "UNPAUSED"
  }

  task {
    task_key = "build_silver_customers"

    notebook_task {
      notebook_path = "${var.dbt_project_path}/run_dbt.py"
      base_parameters = {
        dbt_command = "build --select silver_customers --full-refresh"
      }
    }

    timeout_seconds = 3600
    max_retries     = 2
  }

  task {
    task_key = "build_silver_products"
    depends_on {
      task_key = "build_silver_customers"
    }

    notebook_task {
      notebook_path = "${var.dbt_project_path}/run_dbt.py"
      base_parameters = {
        dbt_command = "build --select silver_customer_products --full-refresh"
      }
    }

    timeout_seconds = 3600
    max_retries     = 2
  }

  # After the dimensions are refreshed, trigger the hourly pipeline so the 2 AM
  # gold build runs on fresh dimension data. The hourly job's own schedule skips
  # 2 AM (see workflow_hourly_incremental.tf), so this is the only 2 AM gold
  # build — making the daily→hourly ordering explicit and removing the race
  # between the two independently-scheduled jobs. run_job_task waits for the
  # triggered hourly run (incrementals → gold → tests) to complete.
  task {
    task_key = "trigger_hourly_pipeline"
    depends_on {
      task_key = "build_silver_products"
    }

    run_job_task {
      job_id = databricks_job.hourly_incremental_refresh.id
    }

    timeout_seconds = 7200
  }

  # Compact small files from the accumulated hourly incremental merges.
  # Depends on trigger_hourly_pipeline so OPTIMIZE runs AFTER the 2 AM hourly
  # MERGE completes — running OPTIMIZE concurrently with a MERGE on the same
  # Delta table risks a concurrent-modification conflict.
  task {
    task_key = "optimize_silver_interactions"
    depends_on {
      task_key = "trigger_hourly_pipeline"
    }

    notebook_task {
      notebook_path = "${var.dbt_project_path}/maintenance/optimize_tables.py"
      base_parameters = {
        table_name = "customer_360_db.silver_customer_interactions"
      }
    }

    timeout_seconds = 1800
    max_retries     = 1
  }

  task {
    task_key = "optimize_silver_transactions"
    depends_on {
      task_key = "trigger_hourly_pipeline"
    }

    notebook_task {
      notebook_path = "${var.dbt_project_path}/maintenance/optimize_tables.py"
      base_parameters = {
        table_name = "customer_360_db.silver_customer_transactions"
      }
    }

    timeout_seconds = 1800
    max_retries     = 1
  }

  # Drop stale dbt audit tables daily to prevent Unity Catalog table quota exhaustion.
  # store_failures: true creates one table per failing test; without cleanup these
  # accumulate. DROP removes the table object itself (not just rows) so it frees quota.
  # dbt recreates audit tables on the next test run only when failures occur.
  task {
    task_key = "cleanup_audit_tables"

    notebook_task {
      notebook_path = "${var.dbt_project_path}/maintenance/cleanup_audit_tables.py"
      base_parameters = {
        # DROP SCHEMA CASCADE removes everything; no vacuum retention needed.
        audit_schema = "customer_360_db_dbt_test__audit"
      }
    }

    timeout_seconds = 1800
    max_retries     = 1
  }

  email_notifications {
    on_failure                = var.notification_emails
    no_alert_for_skipped_runs = true
  }

  tags = {
    environment = "production"
    layer       = "silver"
    frequency   = "daily"
  }
}
