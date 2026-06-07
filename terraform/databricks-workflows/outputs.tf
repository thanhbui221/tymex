output "daily_workflow_id" {
  description = "Job ID for daily dimensions refresh workflow"
  value       = databricks_job.daily_dimensions_refresh.id
}

output "hourly_workflow_id" {
  description = "Job ID for hourly incremental refresh workflow"
  value       = databricks_job.hourly_incremental_refresh.id
}

output "maintenance_workflow_id" {
  description = "Job ID for weekly maintenance workflow"
  value       = databricks_job.weekly_maintenance.id
}

output "workflow_urls" {
  description = "Direct URLs to workflows in Databricks"
  value = {
    daily_dimensions = "${var.databricks_host}/#job/${databricks_job.daily_dimensions_refresh.id}"
    hourly_incremental = "${var.databricks_host}/#job/${databricks_job.hourly_incremental_refresh.id}"
    weekly_maintenance = "${var.databricks_host}/#job/${databricks_job.weekly_maintenance.id}"
  }
}
