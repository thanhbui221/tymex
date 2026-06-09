# Backfill workflow: Reprocess incremental silver and gold models.
#
# PAUSED by default — triggered manually when needed:
#   - Bug fix in transformation logic affecting historical records
#   - Business rule change (e.g. segmentation thresholds)
#   - Source data correction upstream
#   - New column added to an incremental model
#   - Initial historical load on first deployment
#
# Parameters (pass at trigger time via Databricks UI or API):
#   backfill_start  — inclusive lower bound, e.g. "2025-01-01"
#   backfill_end    — exclusive upper bound, e.g. "2025-06-01"
#
# Behaviour:
#   Dates provided  → windowed backfill: identifies affected customer_ids from the
#                     window, recomputes full history for those customers only.
#   No dates        → full refresh: drops and rebuilds from scratch (nuclear option).
#
# run_dbt.py is responsible for constructing the final dbt command:
#   if backfill_start != "": dbt build --select <model> --vars '{"backfill_start": ..., "backfill_end": ...}'
#   else:                    dbt build --select <model> --full-refresh
resource "databricks_job" "backfill" {
  name = "Customer360 - Backfill"

  # No schedule — manual trigger only
  schedule {
    quartz_cron_expression = "0 0 0 1 1 ? 2099"  # Unreachable date — effectively disabled
    timezone_id            = "UTC"
    pause_status           = "PAUSED"
  }

  # Pass at trigger time. Leave blank to trigger a full refresh.
  parameter {
    name    = "backfill_start"
    default = ""
  }

  parameter {
    name    = "backfill_end"
    default = ""
  }

  task {
    task_key = "backfill_silver_interactions"

    notebook_task {
      notebook_path = "${var.dbt_project_path}/run_dbt.py"
      base_parameters = {
        dbt_select     = "silver_customer_interactions"
        backfill_start = "{{job.parameters.backfill_start}}"
        backfill_end   = "{{job.parameters.backfill_end}}"
      }
    }

    timeout_seconds = 7200
    max_retries     = 1
  }

  task {
    task_key = "backfill_silver_transactions"

    notebook_task {
      notebook_path = "${var.dbt_project_path}/run_dbt.py"
      base_parameters = {
        dbt_select     = "silver_customer_transactions"
        backfill_start = "{{job.parameters.backfill_start}}"
        backfill_end   = "{{job.parameters.backfill_end}}"
      }
    }

    timeout_seconds = 7200
    max_retries     = 1
  }

  # Gate: validate silver invariants before building gold from them.
  task {
    task_key = "test_silver"
    depends_on {
      task_key = "backfill_silver_interactions"
    }
    depends_on {
      task_key = "backfill_silver_transactions"
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
    task_key = "backfill_gold_customer_360"
    depends_on {
      task_key = "test_silver"
    }

    notebook_task {
      notebook_path = "${var.dbt_project_path}/run_dbt.py"
      base_parameters = {
        dbt_select     = "customer_360"
        backfill_start = "{{job.parameters.backfill_start}}"
        backfill_end   = "{{job.parameters.backfill_end}}"
      }
    }

    timeout_seconds = 7200
    max_retries     = 1
  }

  task {
    task_key = "test_gold"
    depends_on {
      task_key = "backfill_gold_customer_360"
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
    on_success                = var.notification_emails
    no_alert_for_skipped_runs = true
  }

  tags = {
    environment = "production"
    type        = "backfill"
    frequency   = "on-demand"
  }
}
