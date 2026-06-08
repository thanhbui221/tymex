# Hourly workflow: Refresh incremental models (interactions, transactions, customer_360)
resource "databricks_job" "hourly_incremental_refresh" {
  name = "Customer360 - Hourly Incremental Refresh"

  schedule {
    quartz_cron_expression = "0 0 * * * ?"  # Every hour at :00
    timezone_id            = "UTC"
    pause_status           = "UNPAUSED"
  }

  task {
    task_key = "build_silver_interactions"

    notebook_task {
      notebook_path = "${var.dbt_project_path}/run_dbt.py"
      base_parameters = {
        dbt_command = "build --select silver_customer_interactions"
      }
    }

    timeout_seconds = 1800
    max_retries     = 2
  }

  task {
    task_key = "build_silver_transactions"

    notebook_task {
      notebook_path = "${var.dbt_project_path}/run_dbt.py"
      base_parameters = {
        dbt_command = "build --select silver_customer_transactions"
      }
    }

    timeout_seconds = 1800
    max_retries     = 2
  }

  task {
    task_key = "build_gold_customer_360"
    depends_on {
      task_key = "build_silver_interactions"
    }
    depends_on {
      task_key = "build_silver_transactions"
    }

    notebook_task {
      notebook_path = "${var.dbt_project_path}/run_dbt.py"
      base_parameters = {
        dbt_command = "build --select customer_360"
      }
    }

    timeout_seconds = 3600
    max_retries     = 2
  }

  task {
    task_key = "test_business_rules"
    depends_on {
      task_key = "build_gold_customer_360"
    }

    notebook_task {
      notebook_path = "${var.dbt_project_path}/run_dbt.py"
      base_parameters = {
        # Singular tests are standalone DAG nodes — not picked up by model name selectors.
        # Must be selected explicitly by test_type.
        dbt_command = "test --select test_type:singular"
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
    layer       = "silver_gold"
    frequency   = "hourly"
  }
}
