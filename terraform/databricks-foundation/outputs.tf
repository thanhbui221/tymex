output "schema_name" {
  description = "Customer 360 database schema name"
  value       = databricks_schema.customer_360_db.name
}

output "databricks_host" {
  description = "Databricks workspace URL (passthrough)"
  value       = var.databricks_host
}

output "ingest_bronze_notebook_path" {
  description = "Workspace path of the one-time bronze ingestion notebook"
  value       = databricks_notebook.ingest_bronze.path
}
