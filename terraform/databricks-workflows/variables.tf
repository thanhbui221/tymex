variable "databricks_host" {
  description = "Databricks workspace URL"
  type        = string
}

variable "databricks_token" {
  description = "Databricks personal access token"
  type        = string
  sensitive   = true
}

variable "dbt_project_path" {
  description = "Path to dbt project scripts in Databricks Workspace"
  type        = string
  default     = "/Workspace/Shared/dbt/customer_360"
}

variable "sql_warehouse_id" {
  description = "SQL Warehouse ID for monitoring queries"
  type        = string
}

variable "notification_emails" {
  description = "List of emails for failure alerts"
  type        = list(string)
  default     = []
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for alerts (optional)"
  type        = string
  default     = ""
  sensitive   = true
}
