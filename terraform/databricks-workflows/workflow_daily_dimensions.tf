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
