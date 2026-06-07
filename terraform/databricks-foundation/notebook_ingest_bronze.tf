# One-time bootstrap notebook for loading raw CSV files into bronze source tables
resource "databricks_notebook" "ingest_bronze" {
  path     = "/Workspace/Users/thanhbui22198@gmail.com/customer_360/ingest_bronze"
  language = "PYTHON"
  source   = "${path.module}/../../databricks-scripts/ingest_bronze.py"
}
