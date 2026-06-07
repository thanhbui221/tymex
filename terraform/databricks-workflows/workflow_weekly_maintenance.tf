# Weekly maintenance: OPTIMIZE and VACUUM Delta tables
resource "databricks_job" "weekly_maintenance" {
  name = "Customer360 - Weekly Maintenance"

  schedule {
    quartz_cron_expression = "0 0 3 ? * SUN"  # 3 AM every Sunday
    timezone_id            = "UTC"
    pause_status           = "UNPAUSED"
  }

  task {
    task_key = "optimize_silver_interactions"

    notebook_task {
      notebook_path = "${var.dbt_project_path}/maintenance/optimize_tables.py"
      base_parameters = {
        table_name = "customer_360_db.silver_customer_interactions"
      }
    }

    timeout_seconds = 7200
    max_retries     = 1
  }

  task {
    task_key = "optimize_silver_transactions"

    notebook_task {
      notebook_path = "${var.dbt_project_path}/maintenance/optimize_tables.py"
      base_parameters = {
        table_name = "customer_360_db.silver_customer_transactions"
      }
    }

    timeout_seconds = 7200
    max_retries     = 1
  }

  task {
    task_key = "optimize_customer_360"

    notebook_task {
      notebook_path = "${var.dbt_project_path}/maintenance/optimize_tables.py"
      base_parameters = {
        table_name = "customer_360_db.customer_360"
      }
    }

    timeout_seconds = 7200
    max_retries     = 1
  }

  task {
    task_key = "vacuum_old_files"
    depends_on {
      task_key = "optimize_silver_interactions"
    }
    depends_on {
      task_key = "optimize_silver_transactions"
    }
    depends_on {
      task_key = "optimize_customer_360"
    }

    notebook_task {
      notebook_path = "${var.dbt_project_path}/maintenance/vacuum_tables.py"
      base_parameters = {
        schema          = "customer_360_db"
        retention_hours = "168"
      }
    }

    timeout_seconds = 3600
    max_retries     = 1
  }

  email_notifications {
    on_failure                = var.notification_emails
    no_alert_for_skipped_runs = true
  }

  tags = {
    environment = "production"
    type        = "maintenance"
    frequency   = "weekly"
  }
}
