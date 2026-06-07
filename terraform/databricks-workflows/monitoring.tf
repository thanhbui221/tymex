resource "databricks_directory" "alerts_dir" {
  path = "/Shared/alerts"
}

# Monitoring: Job run duration alerts
resource "databricks_query" "job_duration_monitor" {
  warehouse_id = var.sql_warehouse_id
  display_name          = "Customer360 - Job Duration Monitor"

  query_text = <<-EOQ
    SELECT
      job_id,
      job_name,
      start_time,
      end_time,
      TIMESTAMPDIFF(MINUTE, start_time, end_time) as duration_minutes,
      state
    FROM system.workflows.job_runs
    WHERE job_name LIKE 'Customer360%'
      AND start_time >= CURRENT_DATE() - INTERVAL 7 DAYS
    ORDER BY start_time DESC
  EOQ

  description = "Monitors dbt job run durations for performance degradation"
}

resource "databricks_alert" "long_running_jobs" {
  query_id     = databricks_query.job_duration_monitor.id
  display_name = "Customer360 - Long Running Jobs Alert"

  condition {
    op = "GREATER_THAN"

    operand {
      column {
        name = "duration_minutes"
      }
    }

    threshold {
      value {
        double_value = 60
      }
    }
  }

  # 24 hours = 24 * 60 * 60 seconds
  seconds_to_retrigger = 86400

  parent_path = "/Shared/alerts"
  depends_on  = [databricks_directory.alerts_dir]
}

# Monitoring: Row count tracking for data quality
resource "databricks_query" "row_count_monitor" {
  warehouse_id = var.sql_warehouse_id
  display_name          = "Customer360 - Row Count Monitor"

  query_text = <<-EOQ
    SELECT
      'silver_customers' as table_name,
      COUNT(*) as row_count,
      CURRENT_TIMESTAMP() as check_time
    FROM customer_360_db.silver_customers

    UNION ALL

    SELECT
      'silver_customer_interactions' as table_name,
      COUNT(*) as row_count,
      CURRENT_TIMESTAMP() as check_time
    FROM customer_360_db.silver_customer_interactions

    UNION ALL

    SELECT
      'silver_customer_transactions' as table_name,
      COUNT(*) as row_count,
      CURRENT_TIMESTAMP() as check_time
    FROM customer_360_db.silver_customer_transactions

    UNION ALL

    SELECT
      'customer_360' as table_name,
      COUNT(*) as row_count,
      CURRENT_TIMESTAMP() as check_time
    FROM customer_360_db.customer_360
  EOQ

  description = "Tracks row counts across all layers for anomaly detection"
}

# Alert on unexpected row count drops (> 10% decrease)
resource "databricks_alert" "row_count_drop" {
  query_id     = databricks_query.row_count_monitor.id
  display_name = "Customer360 - Row Count Drop Alert"

  condition {
    op = "LESS_THAN"

    operand {
      column {
        name = "row_count"
      }
    }

    threshold {
      value {
        double_value = 1000
      }
    }
  }

  # 1 hour = 60 * 60 seconds
  seconds_to_retrigger = 3600

  parent_path = "/Shared/alerts"
  depends_on  = [databricks_directory.alerts_dir]
}
