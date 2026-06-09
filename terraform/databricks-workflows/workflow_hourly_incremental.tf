# Hourly workflow: Refresh incremental models (interactions, transactions, customer_360)
resource "databricks_job" "hourly_incremental_refresh" {
  name = "Customer360 - Hourly Incremental Refresh"

  schedule {
    quartz_cron_expression = "0 0 * * * ?"  # Every hour at :00
    timezone_id            = "UTC"
    pause_status           = "UNPAUSED"
  }

  # Gate: verify bronze referential integrity before building silver from it.
  task {
    task_key = "test_bronze"

    notebook_task {
      notebook_path = "${var.dbt_project_path}/run_dbt.py"
      base_parameters = {
        dbt_command = "test --select assert_transaction_product_customer_match"
      }
    }

    timeout_seconds = 600
    max_retries     = 1
  }

  task {
    task_key = "build_silver_interactions"
    depends_on {
      task_key = "test_bronze"
    }

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
    depends_on {
      task_key = "test_bronze"
    }

    notebook_task {
      notebook_path = "${var.dbt_project_path}/run_dbt.py"
      base_parameters = {
        dbt_command = "build --select silver_customer_transactions"
      }
    }

    timeout_seconds = 1800
    max_retries     = 2
  }

  # Gate: validate silver invariants before building gold from them.
  task {
    task_key = "test_silver"
    depends_on {
      task_key = "build_silver_interactions"
    }
    depends_on {
      task_key = "build_silver_transactions"
    }

    notebook_task {
      notebook_path = "${var.dbt_project_path}/run_dbt.py"
      base_parameters = {
        dbt_command = "test --select assert_customer_360_transaction_values_consistent"
      }
    }

    timeout_seconds = 600
    max_retries     = 1
  }

  task {
    task_key = "build_gold_customer_360"
    depends_on {
      task_key = "test_silver"
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
    task_key = "test_gold"
    depends_on {
      task_key = "build_gold_customer_360"
    }

    notebook_task {
      notebook_path = "${var.dbt_project_path}/run_dbt.py"
      base_parameters = {
        dbt_command = "test --select assert_no_negative_counts assert_active_customers_have_recent_activity assert_premium_customers_meet_criteria"
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
