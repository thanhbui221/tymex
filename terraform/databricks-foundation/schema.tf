# Customer 360 database schema
resource "databricks_schema" "customer_360_db" {
  catalog_name = "workspace"
  name         = "customer_360_db"
  comment      = "Schema for Customer 360 project"

  properties = {
    managed_by = "terraform"
    project    = "customer-360"
  }
}
