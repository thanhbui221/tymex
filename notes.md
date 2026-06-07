transaction_history: UTC hay local-based time?

---

# Customer 360 Case Study - Full Setup Instructions (Databricks + dbt)

## Step 1: Get Databricks Access

### Option A: Databricks Community Edition (Free, Recommended)
1. Go to https://community.cloud.databricks.com/
2. Click "Sign up"
3. Create account with email
4. Verify email and log in
5. You'll get a free workspace with limited compute (15GB cluster)

### Option B: Databricks Trial (14 days, Full Features)
1. Go to https://databricks.com/try-databricks
2. Select cloud provider (AWS, Azure, or GCP)
3. Fill out trial form and follow setup wizard

**For this case study**: Community Edition is sufficient.

---

## Step 2: Infrastructure Setup with Terraform

### Why Terraform?
Automate infrastructure provisioning with code - similar to AWS infrastructure setup.

### Prerequisites
```bash
# Install Terraform
brew update
brew tap hashicorp/tap
brew install hashicorp/tap/terraform # macOS
# or download from terraform.io

# Install Databricks CLI
pip install databricks-cli
```

### Setup Steps

**1. Configure Databricks Authentication**

Create `~/.databrickscfg`:
```ini
[DEFAULT]
host = https://your-workspace.cloud.databricks.com
token = your-access-token
```

**2. Create Terraform Configuration**

Create a new directory for your infrastructure:
```bash
mkdir databricks-infra
cd databricks-infra
```

**3. Create provider.tf**

```hcl
terraform {
  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.0"
    }
  }
}

provider "databricks" {
  host  = var.databricks_host
  token = var.databricks_token
}
```

**4. Create variables.tf**

```hcl
variable "databricks_host" {
  description = "Databricks workspace URL"
  type        = string
}

variable "databricks_token" {
  description = "Databricks personal access token"
  type        = string
  sensitive   = true
}
```

**5. Create main.tf**

```hcl
# Create cluster
resource "databricks_cluster" "customer_360_cluster" {
  cluster_name            = "customer-360-cluster"
  spark_version           = "13.3.x-scala2.12"
  node_type_id            = "i3.xlarge"
  autotermination_minutes = 20
  num_workers             = 1
}

# Create database/schema
resource "databricks_schema" "customer_360_db" {
  name = "customer_360_db"
}

# Note: Tables will be created by dbt models, not Terraform
# dbt handles data modeling and table creation
```

**6. Create terraform.tfvars**

```hcl
databricks_host  = "https://your-workspace.cloud.databricks.com"
databricks_token = "your-access-token-here"
```

**Note**: Add `terraform.tfvars` to `.gitignore` to avoid committing secrets!

**7. Apply Terraform Configuration**

```bash
# Initialize Terraform
terraform init

# Preview changes
terraform plan

# Apply infrastructure
terraform apply
```

---

## Step 3: Initial Data Load (One-time Seed)

**Note**: This is for case study setup only. In production, raw tables are populated by automated pipelines (CDC, streaming, batch jobs).

### Load CSV Files from ./data to Raw Tables

You have CSV files in `./data` directory. Load them once to seed the raw tables.

**Using Databricks CLI + Notebook:**

```bash
# Upload CSV files to DBFS
brew tap databricks/tap
brew install databricks
databricks workspace mkdirs /Users/thanhbui22198@gmail.com/customer_360
databricks workspace import /Users/thanhbui22198@gmail.com/customer_360/customer_raw.csv \
  --file ./data/customer_raw.csv \
  --format RAW \
  --overwrite

databricks workspace import /Users/thanhbui22198@gmail.com/customer_360/product_enrollments.csv \
  --file ./data/product_enrollments.csv \
  --format RAW \
  --overwrite

databricks workspace import /Users/thanhbui22198@gmail.com/customer_360/crm_interactions.csv \
  --file ./data/crm_interactions.csv \
  --format RAW \
  --overwrite

awk 'NR==1 {header=$0; next}
     (NR-2)%200000==0 {
       if (out) close(out);
       out=sprintf("data/split_transaction_history/transaction_history_%03d.csv", ++i);
       print header > out
     }
     {print > out}' ./data/transaction_history.csv

for file in data/split_transaction_history/*.csv; do
  filename=$(basename "$file")
  databricks workspace import /Users/thanhbui22198@gmail.com/customer_360/transaction_history/$filename \
    --file "$file" \
    --format RAW \
    --overwrite
done
```

Then create a Databricks notebook to load into tables:

```python
# Read CSV and create raw tables
base_path = "file:/Workspace/Users/thanhbui22198@gmail.com/customer_360"

spark.sql("CREATE DATABASE IF NOT EXISTS customer_360_db")

spark.read.csv(f"{base_path}/customer_raw.csv", header=True, inferSchema=True) \
    .write.mode("overwrite").saveAsTable("customer_360_db.customer_raw")

spark.read.csv(f"{base_path}/product_enrollments.csv", header=True, inferSchema=True) \
    .write.mode("overwrite").saveAsTable("customer_360_db.product_enrollments")

spark.read.csv(f"{base_path}/crm_transactions.csv", header=True, inferSchema=True) \
    .write.mode("overwrite").saveAsTable("customer_360_db.crm_transactions")

spark.read.csv(f"{base_path}/transaction_history/*.csv", header=True, inferSchema=True) \
    .write.mode("overwrite").saveAsTable("customer_360_db.transaction_history")
```

**Option B: Databricks UI (Manual)**

1. In Databricks workspace, go to **Data** → **Create Table**
2. Click **Upload File** and select your CSV files from `./data`
3. Select your cluster
4. Choose database: `customer_360_db`
5. Set table names: `customer_raw`, `product_enrollments`, etc.
6. Click **Create Table**

**Result:** Raw tables created in `customer_360_db`:
- `customer_360_db.customer_raw`
- `customer_360_db.product_enrollments`
- `customer_360_db.crm_transactions`
- `customer_360_db.transaction_history`

### Loading Sample Data

After Terraform creates your infrastructure, load sample data into raw source tables. You have two options:

**Option A: Databricks Notebook** (Recommended)

Create a notebook in Databricks and run:

```python
# Sample customer data
customer_data = [
    (18231, 'Kristina', 'Pope', 'kpope90465@yahoo.com', '09408995771', 'Female', '1982-08-02', '2023-10-04'),
    (93481, 'Elizabeth', 'Black', 'eblack29035@zohomail.com', '09707540321', 'Female', '1985-06-23', '2023-05-02'),
]

df = spark.createDataFrame(customer_data, 
    ['customer_id', 'first_name', 'last_name', 'email', 'mobile', 'gender', 'date_of_birth', 'signup_date'])
df.write.mode("overwrite").saveAsTable("customer_360_db.customer_raw")
```

**Option B: Upload CSV Files**

Upload CSV files via Databricks UI → Data → Create Table → Upload File

---

## Step 4: Production Data Ingestion (Future State)

In production, raw tables are continuously populated by automated pipelines. Here's the strategy for each table:

### Ingestion Strategies by Table Type

**1. customer_raw** (Dimension Table)
- **Strategy**: Full refresh (overwrite)
- **Source**: CRM system batch export
- **Frequency**: Daily/nightly
- **Why**: Customer master data changes slowly, full refresh is acceptable
- **Tool**: Fivetran/Airbyte batch sync or Databricks workflow

**2. crm_interactions** (Event Log)
- **Strategy**: Incremental append
- **Source**: CRM API events or Kafka stream
- **Frequency**: Real-time or micro-batches
- **Why**: Events are immutable (don't change once logged)
- **Tool**: Databricks Auto Loader, Kafka connector, or streaming job

**3. product_enrollments** (Dimension Table)
- **Strategy**: Incremental merge (upsert)
- **Source**: Product database CDC (Change Data Capture)
- **Frequency**: Real-time or micro-batches
- **Why**: Credit card limits can change; need to update existing + add new
- **Unique key**: `product_id`
- **Tool**: Debezium CDC, Fivetran, or Delta merge operation

**4. transaction_history** (Fact Table)
- **Strategy**: Incremental append
- **Source**: Payment system events or transaction database
- **Frequency**: Real-time streaming
- **Why**: Transactions are immutable (never change once posted), high volume
- **Tool**: Kafka streaming, Databricks Auto Loader, or event ingestion pipeline

### Summary

```
Production Architecture:

External Systems          Databricks Raw Layer                    dbt Transformation
----------------         ---------------------                    ------------------
CRM System       →       customer_raw (overwrite)        →       staging → gold
CRM API Events   →       crm_interactions (append)       →       staging → gold  
Product DB CDC   →       product_enrollments (merge)     →       staging → gold
Payment Events   →       transaction_history (append)    →       staging → gold
```



### 2.1 Install dbt-databricks

On your local machine, run:

```bash
pip3 install dbt-databricks
```

### 4.2 Get Databricks Connection Details

You'll need these values from your Databricks workspace:

1. **Server Hostname**:
   - In Databricks, go to **Compute** → Click your cluster
   - Click **Advanced Options** → **JDBC/ODBC** tab
   - Copy **Server Hostname** (looks like: `dbc-xxxxx-xxxx.cloud.databricks.com`)

2. **HTTP Path**:
   - Same location as Server Hostname
   - Copy **HTTP Path** (looks like: `/sql/1.0/warehouses/xxxxx`)

3. **Access Token**:
   - Click your profile icon (top right) → **User Settings**
   - Go to **Developer** → **Access Tokens**
   - Click **Generate New Token**
   - Give it a name (e.g., "dbt-connection")
   - Copy the token (you won't see it again!)

### 4.3 Configure profiles.yml

Create or edit `~/.dbt/profiles.yml`:

```yaml
customer_360:
  target: dev
  outputs:
    dev:
      type: databricks
      host: <your-server-hostname>
      http_path: <your-http-path>
      token: <your-access-token>
      schema: customer_360_db
      threads: 4
```

Replace the placeholders with your actual values.

---

## Step 5: Initialize dbt Project

### 5.1 Create dbt Project

```bash
dbt init customer_360
cd customer_360
```

When prompted:
- Which database? Select **databricks**
- Profile name: `customer_360` (should match profiles.yml)

### 5.2 Test Connection

```bash
dbt debug
```

You should see "All checks passed!" if configuration is correct.

---

## Step 6: Set Up dbt Project Structure

### 6.1 Recommended Folder Structure (Medallion Architecture)

```
customer_360/
├── dbt_project.yml
├── models/
│   ├── silver/
│   │   ├── silver_customers.sql
│   │   ├── silver_customer_products.sql
│   │   ├── silver_customer_transactions.sql
│   │   └── silver_customer_interactions.sql
│   └── gold/
│       └── customer_360.sql
├── tests/
└── macros/
```

**Layer definitions:**
- **Bronze**: Raw source tables (customer_raw, product_enrollments, etc.) - loaded via CSV/pipeline
- **Silver**: Cleaned + aggregated tables ready for business logic
- **Gold**: Final business-ready tables for BI consumption

### 6.2 Update dbt_project.yml

Edit `dbt_project.yml` for medallion architecture with incremental strategy:

```yaml
name: 'customer_360'
version: '1.0.0'
config-version: 2

profile: 'customer_360'

model-paths: ["models"]
test-paths: ["tests"]
macro-paths: ["macros"]

models:
  customer_360:
    silver:
      silver_customers:
        +materialized: table
      silver_customer_products:
        +materialized: table
      silver_customer_interactions:
        +materialized: incremental
        +unique_key: customer_id
        +incremental_strategy: merge
      silver_customer_transactions:
        +materialized: incremental
        +unique_key: customer_id
        +incremental_strategy: merge
    gold:
      customer_360:
        +materialized: incremental
        +unique_key: customer_id
        +incremental_strategy: merge
```

**Materialization strategy:**
- silver_customers: table (full refresh)
- silver_customer_products: table (full refresh)
- silver_customer_interactions: incremental merge (only recalc customers with new interactions)
- silver_customer_transactions: incremental merge (only recalc customers with new transactions)
- customer_360 (gold): incremental merge (only recalc customers with changes in any silver table)

---

## Step 7: Build dbt Models

### 7.1 Create Silver Models (Clean + Aggregate)

Silver layer cleans, standardizes, and aggregates bronze data.

**Create sources.yml** in `models/silver/`:

```yaml
version: 2

sources:
  - name: customer_360_db
    database: customer_360_db
    tables:
      - name: customer_raw
      - name: product_enrollments
      - name: crm_transactions
      - name: transaction_history
```

**models/silver/silver_customers.sql** (cleaned customer base, 1-to-1)

```sql
-- Clean and standardize customer data
SELECT
    customer_id,
    TRIM(first_name) AS first_name,
    TRIM(last_name) AS last_name,
    LOWER(TRIM(email)) AS email,
    REGEXP_REPLACE(mobile, '[^0-9]', '') AS mobile_clean,
    gender,
    date_of_birth,
    DATEDIFF(YEAR, date_of_birth, CURRENT_DATE()) AS age,
    signup_date,
    DATEDIFF(DAY, signup_date, CURRENT_DATE()) AS days_since_signup
FROM {{ source('customer_360_db', 'customer_raw') }}
WHERE email IS NOT NULL
```

**models/silver/silver_customer_products.sql** (aggregated products per customer)

```sql
-- Aggregate product holdings per customer
SELECT
    customer_id,
    COUNT(*) AS total_products,
    SUM(CASE WHEN UPPER(TRIM(product_type)) = 'CREDIT CARD' THEN 1 ELSE 0 END) AS credit_card_count,
    SUM(CASE WHEN UPPER(TRIM(product_type)) = 'SAVINGS' THEN 1 ELSE 0 END) AS savings_count,
    MAX(CASE WHEN UPPER(TRIM(product_type)) = 'CREDIT CARD' THEN CAST(limit AS DECIMAL(12,2)) ELSE 0 END) AS max_credit_limit,
    MIN(enrollment_date) AS first_product_date,
    MAX(enrollment_date) AS latest_product_date
FROM {{ source('customer_360_db', 'product_enrollments') }}
WHERE product_id IS NOT NULL
GROUP BY customer_id
```

**models/silver/silver_customer_interactions.sql** (aggregated, incremental)

```sql
{{
    config(
        materialized='incremental',
        unique_key='customer_id',
        incremental_strategy='merge'
    )
}}

-- Aggregate interaction data per customer (incremental)
SELECT
    customer_id,
    MAX(interaction_date) AS last_interaction_date,
    COUNT(*) AS total_interactions,
    COUNT(CASE WHEN UPPER(TRIM(interaction_type)) = 'EMAIL' THEN 1 END) AS email_interactions,
    COUNT(CASE WHEN UPPER(TRIM(interaction_type)) = 'CHAT' THEN 1 END) AS chat_interactions,
    DATEDIFF(DAY, MAX(interaction_date), CURRENT_DATE()) AS days_since_last_interaction
FROM {{ source('customer_360_db', 'crm_transactions') }}
WHERE interaction_id IS NOT NULL
{% if is_incremental() %}
    -- Only process new interactions since last run
    AND interaction_date > (SELECT MAX(last_interaction_date) FROM {{ this }})
{% endif %}
GROUP BY customer_id
```

**models/silver/silver_customer_transactions.sql** (aggregated, incremental)

```sql
{{
    config(
        materialized='incremental',
        unique_key='customer_id',
        incremental_strategy='merge'
    )
}}

-- Aggregate transaction metrics per customer (incremental)
SELECT
    customer_id,
    COUNT(*) AS total_transactions,
    SUM(CASE WHEN CAST(transaction_amount AS DECIMAL(12,2)) < 0 THEN 1 ELSE 0 END) AS debit_count,
    SUM(CASE WHEN CAST(transaction_amount AS DECIMAL(12,2)) > 0 THEN 1 ELSE 0 END) AS credit_count,
    SUM(CAST(transaction_amount AS DECIMAL(12,2))) AS total_transaction_value,
    AVG(CAST(transaction_amount AS DECIMAL(12,2))) AS avg_transaction_amount,
    MAX(CAST(closing_balance AS DECIMAL(12,2))) AS max_balance,
    MIN(CAST(closing_balance AS DECIMAL(12,2))) AS min_balance,
    MAX(transaction_date) AS last_transaction_date,
    DATEDIFF(DAY, MAX(transaction_date), CURRENT_DATE()) AS days_since_last_transaction
FROM {{ source('customer_360_db', 'transaction_history') }}
WHERE transaction_id IS NOT NULL
{% if is_incremental() %}
    -- Only process new transactions since last run
    AND transaction_date > (SELECT MAX(last_transaction_date) FROM {{ this }})
{% endif %}
GROUP BY customer_id
```

### 7.2 Create Gold Layer Model

**models/gold/customer_360.sql** - Unified customer view (incremental)

```sql
{{
    config(
        materialized='incremental',
        unique_key='customer_id',
        incremental_strategy='merge'
    )
}}

-- Gold layer: Unified customer 360 view (incremental)
WITH customer_base AS (
    SELECT * FROM {{ ref('silver_customers') }}
),

customer_products AS (
    SELECT * FROM {{ ref('silver_customer_products') }}
),

customer_interactions AS (
    SELECT * FROM {{ ref('silver_customer_interactions') }}
),

customer_transactions AS (
    SELECT * FROM {{ ref('silver_customer_transactions') }}
),

{% if is_incremental() %}
-- Identify customers with changes
changed_customers AS (
    SELECT DISTINCT customer_id FROM {{ ref('silver_customer_interactions') }}
    WHERE last_interaction_date > (SELECT MAX(last_interaction_date) FROM {{ this }})
    UNION
    SELECT DISTINCT customer_id FROM {{ ref('silver_customer_transactions') }}
    WHERE last_transaction_date > (SELECT MAX(last_transaction_date) FROM {{ this }})
)
{% endif %}

SELECT
    -- Customer demographics
    c.customer_id,
    c.first_name,
    c.last_name,
    c.email,
    c.mobile_clean,
    c.gender,
    c.age,
    c.signup_date,
    c.days_since_signup,
    
    -- Product holdings
    COALESCE(p.total_products, 0) AS total_products,
    COALESCE(p.credit_card_count, 0) AS credit_card_count,
    COALESCE(p.savings_count, 0) AS savings_count,
    p.max_credit_limit,
    p.first_product_date,
    
    -- Interactions
    i.last_interaction_date,
    COALESCE(i.total_interactions, 0) AS total_interactions,
    i.days_since_last_interaction,
    
    -- Transactions
    COALESCE(t.total_transactions, 0) AS total_transactions,
    t.total_transaction_value,
    t.avg_transaction_amount,
    t.last_transaction_date,
    t.days_since_last_transaction,
    
    -- Business logic: Active customer definition
    CASE 
        WHEN i.days_since_last_interaction <= 90 OR t.days_since_last_transaction <= 90 THEN 'Active'
        ELSE 'Inactive'
    END AS customer_status,
    
    -- Customer segmentation
    CASE 
        WHEN COALESCE(p.total_products, 0) >= 3 AND t.total_transaction_value > 100000 THEN 'Premium'
        WHEN COALESCE(p.total_products, 0) >= 2 THEN 'Standard'
        ELSE 'Basic'
    END AS customer_segment

FROM customer_base c
LEFT JOIN customer_products p ON c.customer_id = p.customer_id
LEFT JOIN customer_interactions i ON c.customer_id = i.customer_id
LEFT JOIN customer_transactions t ON c.customer_id = t.customer_id

{% if is_incremental() %}
-- Only process customers with changes
WHERE c.customer_id IN (SELECT customer_id FROM changed_customers)
{% endif %}
```

---

## Step 8: Add dbt Tests (7 Data Quality Dimensions)

### 8.1 Data Quality Framework

**7 Data Quality Dimensions:**
1. **Uniqueness**: No duplicate records
2. **Completeness**: No missing critical values
3. **Validity**: Data conforms to formats/ranges
4. **Accuracy**: Data correctly represents reality
5. **Consistency**: Data is consistent across tables
6. **Integrity**: Relationships between tables maintained
7. **Timeliness**: Data is up-to-date

### 8.2 Create schema.yml for Gold Layer

**models/gold/schema.yml:**

```yaml
version: 2

models:
  - name: customer_360
    description: "Unified customer 360 view with demographics, products, interactions, and transactions"
    columns:
      # 1. UNIQUENESS
      - name: customer_id
        description: "Unique customer identifier"
        tests:
          - unique
          - not_null
      
      # 2. COMPLETENESS
      - name: email
        description: "Customer email address"
        tests:
          - not_null
      
      - name: first_name
        tests:
          - not_null
      
      - name: last_name
        tests:
          - not_null
      
      # 3. VALIDITY - Formats and ranges
      - name: age
        description: "Customer age calculated from date of birth"
        tests:
          - not_null
          - dbt_utils.accepted_range:
              min_value: 18
              max_value: 120
      
      - name: customer_status
        description: "Active if interaction/transaction within 90 days"
        tests:
          - not_null
          - accepted_values:
              values: ['Active', 'Inactive']
      
      - name: customer_segment
        description: "Customer segmentation: Premium/Standard/Basic"
        tests:
          - not_null
          - accepted_values:
              values: ['Premium', 'Standard', 'Basic']
      
      - name: total_products
        tests:
          - dbt_utils.accepted_range:
              min_value: 0
              max_value: 10
      
      # 4. ACCURACY - Business rule validation
      - name: days_since_signup
        tests:
          - dbt_utils.accepted_range:
              min_value: 0

# 5. CONSISTENCY - Cross-field validation
tests:
  - dbt_utils.expression_is_true:
      expression: "total_products = (credit_card_count + savings_count)"
      name: products_sum_matches_total
  
  - dbt_utils.expression_is_true:
      expression: "CASE WHEN customer_status = 'Active' THEN (days_since_last_interaction <= 90 OR days_since_last_transaction <= 90) ELSE TRUE END"
      name: active_status_consistent_with_activity

# 6. INTEGRITY - Relationships
relationships:
  - name: customer_360_to_silver_customers
    tests:
      - dbt_utils.relationships_where:
          to: ref('silver_customers')
          field: customer_id
          from_condition: "customer_id IS NOT NULL"

# 7. TIMELINESS - Freshness
freshness:
  warn_after: {count: 24, period: hour}
  error_after: {count: 48, period: hour}
```

### 8.3 Create schema.yml for Silver Layer

**models/silver/schema.yml:**

```yaml
version: 2

models:
  - name: silver_customers
    description: "Cleaned customer demographics"
    columns:
      - name: customer_id
        tests:
          - unique
          - not_null
      - name: email
        tests:
          - not_null
          - dbt_utils.unique_where:
              where: "email IS NOT NULL"
  
  - name: silver_customer_products
    description: "Aggregated product holdings per customer"
    columns:
      - name: customer_id
        tests:
          - unique
          - not_null
          - relationships:
              to: source('customer_360_db', 'customer_raw')
              field: customer_id
  
  - name: silver_customer_interactions
    description: "Aggregated interaction metrics per customer"
    columns:
      - name: customer_id
        tests:
          - unique
          - not_null
  
  - name: silver_customer_transactions
    description: "Aggregated transaction metrics per customer"
    columns:
      - name: customer_id
        tests:
          - unique
          - not_null
```

### 8.4 Custom Business Rule Tests

**tests/assert_active_customers_have_recent_activity.sql:**

```sql
-- Test: Active customers must have interaction or transaction within 90 days
SELECT
    customer_id,
    customer_status,
    days_since_last_interaction,
    days_since_last_transaction
FROM {{ ref('customer_360') }}
WHERE customer_status = 'Active'
    AND (days_since_last_interaction > 90 AND days_since_last_transaction > 90)
```

**tests/assert_premium_customers_meet_criteria.sql:**

```sql
-- Test: Premium customers must have 3+ products AND 100k+ transaction value
SELECT
    customer_id,
    customer_segment,
    total_products,
    total_transaction_value
FROM {{ ref('customer_360') }}
WHERE customer_segment = 'Premium'
    AND (total_products < 3 OR total_transaction_value <= 100000)
```

**tests/assert_no_negative_metrics.sql:**

```sql
-- Test: Ensure no negative counts or impossible values
SELECT *
FROM {{ ref('customer_360') }}
WHERE total_products < 0
    OR total_interactions < 0
    OR total_transactions < 0
    OR age < 0
```

---

## Step 9: Business Logic Documentation

Create `BUSINESS_LOGIC.md` to document all business decisions and metrics:

### Key Business Metrics Defined

**Active Customer Definition:**
- **Logic**: Customer with interaction OR transaction within 90 days
- **Rationale**: 90 days represents one quarter; customers engaging quarterly considered active
- **Impact**: Used for retention analysis and marketing targeting
- **Fields used**: `days_since_last_interaction`, `days_since_last_transaction`

**Customer Segmentation:**
- **Premium**: 3+ products AND $100k+ total transaction value
  - **Rationale**: High-value customers requiring white-glove service
- **Standard**: 2+ products (any transaction value)
  - **Rationale**: Multi-product customers with growth potential
- **Basic**: All others
  - **Rationale**: New or single-product customers

**Product Aggregations:**
- `total_products`: Count of all enrolled products
- `credit_card_count`: Number of credit card products
- `savings_count`: Number of savings accounts
- `max_credit_limit`: Highest credit limit across all cards

**Transaction Metrics:**
- `total_transaction_value`: Sum of all transactions (positive = credits, negative = debits)
- `avg_transaction_amount`: Average transaction size
- `total_transactions`: Count of all transactions
- `last_transaction_date`: Most recent transaction timestamp

**Interaction Metrics:**
- `total_interactions`: Count of all CRM interactions
- `email_interactions`: Count of email interactions
- `chat_interactions`: Count of chat interactions
- `last_interaction_date`: Most recent interaction date

### Data Model Design Decisions

**Medallion Architecture (Bronze/Silver/Gold):**
- **Bronze**: Raw source tables, 1-to-1 with data sources
- **Silver**: Cleaned + aggregated tables for efficient querying
- **Gold**: Final business-ready table joining all silver layers

**Incremental Materialization:**
- Silver interactions/transactions: Incremental to process only new records
- Gold customer_360: Incremental to recalculate only changed customers
- Reduces compute costs and improves performance

**Slowly Changing Dimensions:**
- customer_360 uses Type 1 SCD (overwrite)
- Current state only, no historical tracking
- If history needed, implement Type 2 SCD with effective dates

### Data Quality Assumptions

1. **Email uniqueness**: Assumed one email per customer
2. **Age calculation**: Based on current date, recalculated daily
3. **Missing interactions**: NULL means customer never interacted via CRM
4. **Missing transactions**: NULL means customer has no transaction activity
5. **Credit limits**: 0.0 for Savings accounts (not applicable)

### Potential Data Quality Issues

**1. Timezone Ambiguity**
- **Issue**: Raw timestamps have no timezone indicator (e.g., "2025-06-10 12:20:06")
- **Impact**: Unclear if timestamps are UTC or local time
- **Risk**: Date-based calculations (90-day active customer) may be incorrect
- **Action**: Confirm source system timezone with data team

**2. Phone Number Format Inconsistency**
- **Issue**: Mixed phone formats ("09..." vs "+63...")
- **Impact**: May indicate customers from different countries/timezones
- **Risk**: If timestamps are local time, mixing timezones causes data inconsistency
- **Action**: 
  - Standardize phone format
  - Determine customer location/timezone
  - Consider adding explicit timezone field

**3. Missing Data Patterns**
- **Issue**: Some customers may have NULL interactions or transactions
- **Impact**: Affects active customer definition and segmentation
- **Action**: Define business rules for customers with no activity

**4. Email Uniqueness**
- **Issue**: Assumed one email per customer (not validated in source)
- **Impact**: Duplicate emails could cause join issues
- **Action**: Add unique constraint test (already in schema.yml)

**5. Transaction Timestamp Precision**
- **Issue**: Different timestamp precisions across sources
- **Impact**: May affect real-time processing and ordering
- **Action**: Validate timestamp precision requirements

### Critical Issue: Timezone Handling

**Problem:**
- `transaction_date` is TIMESTAMP (includes time component)
- **Raw CSV files have naive timestamps** (no timezone indicator)
  - Example: `2025-06-10 12:20:06` (is this UTC? Local? Unknown!)
- Databricks will assume a default timezone when loading (usually UTC or cluster timezone)
- Impacts date-based calculations and business logic

**For This Case Study - Assumption:**
- **Assume all timestamps in raw CSV files are UTC**
- Document this assumption clearly
- In production, **must confirm with source system teams**

**Recommended Best Practice:**
1. **Transaction timestamps**: Store in UTC (server timezone)
2. **Customer timezone**: Add explicit timezone field to customer table (don't infer)
3. **Conversion**: Convert UTC → customer timezone only when needed for reporting

**Questions to Address:**
1. Are transaction timestamps in UTC or local timezone?
2. Should business logic use server time or customer's local time?
3. How do we handle customers across different timezones?

**Questions to Address:**
1. Are transaction timestamps in UTC or local timezone?
2. Should business logic use server time or customer's local time?
3. How do we handle customers across different timezones?

**Recommended Approach:**

**For Bronze Layer:**
- Store all timestamps in UTC (standardize at ingestion)
- Document source timezone in metadata

**For Silver/Gold Layers:**
```sql
-- Convert UTC to business timezone for calculations
CAST(CONVERT_TIMEZONE('UTC', 'America/New_York', transaction_date) AS DATE) AS transaction_date_local
```

**Impact on Business Logic:**
- **Active customer definition (90 days)**: Use DATE comparison, not TIMESTAMP
- **Days_since_* calculations**: Convert to DATE first to avoid timezone drift
- **Reporting**: Always specify timezone in documentation

**Current Implementation Issue:**
```sql
-- CURRENT (may have timezone issues):
DATEDIFF(DAY, MAX(transaction_date), CURRENT_DATE())

-- BETTER (timezone-aware):
DATEDIFF(DAY, DATE(MAX(transaction_date)), CURRENT_DATE())
```

**Action Items:**
1. Confirm source system timezone with data team
2. Standardize all timestamps to UTC in bronze layer
3. Convert to business timezone only in gold layer for reporting
4. Document timezone assumptions in all date-based metrics

---

## Step 10: Run dbt Commands

### 10.1 Build Models

```bash
# Run all models
dbt run

# Run specific layer
dbt run --select silver.*
dbt run --select gold.*

# Run specific model
dbt run --select customer_360

# Full refresh (ignore incremental)
dbt run --full-refresh
```

### 10.2 Run Tests

```bash
# Run all tests
dbt test

# Test specific model
dbt test --select customer_360

# Test specific layer
dbt test --select silver.*
```

### 10.3 Generate Documentation

```bash
# Generate documentation
dbt docs generate

# Serve documentation locally
dbt docs serve
```

Opens at http://localhost:8080 with:
- Data lineage diagrams
- Model descriptions
- Column-level documentation
- Test results

---

## Step 11: Viewing Results in Databricks

Query your customer_360 table:

```sql
USE customer_360_db;

-- View gold layer
SELECT * FROM customer_360 LIMIT 10;

-- Active customers breakdown
SELECT 
    customer_status,
    customer_segment,
    COUNT(*) as customer_count,
    AVG(total_products) as avg_products,
    AVG(total_transaction_value) as avg_transaction_value
FROM customer_360
GROUP BY customer_status, customer_segment;

-- Premium customers
SELECT * FROM customer_360 
WHERE customer_segment = 'Premium'
ORDER BY total_transaction_value DESC;
```

---

**Setup complete!** You now have a production-ready Customer 360 data mart with:
✓ Infrastructure as Code (Terraform)
✓ Medallion architecture (Bronze/Silver/Gold)
✓ Incremental processing for efficiency
✓ Comprehensive data quality tests (7 dimensions)
✓ Complete business logic documentation

### 9.1 Build Models

```bash
# Run all models
dbt run

# Run specific model
dbt run --select customer_360

# Run models in a folder
dbt run --select staging.*
```

### 9.2 Run Tests

```bash
# Run all tests
dbt test

# Test specific model
dbt test --select customer_360
```

### 9.3 Generate Documentation

```bash
dbt docs generate
dbt docs serve
```

This opens documentation in your browser at http://localhost:8080

---

## Step 10: View Results in Databricks

### 10.1 Query Your customer_360 Table

Go back to Databricks SQL Editor and run:

```sql
USE customer_360_db;

-- View the gold layer table
SELECT * FROM gold.customer_360 LIMIT 10;

-- Check data quality
SELECT 
    customer_status,
    COUNT(*) as customer_count
FROM gold.customer_360
GROUP BY customer_status;
```

### 10.2 Connect to BI Tools

Once your customer_360 table is built:
- Go to Databricks → **SQL** → **SQL Warehouses**
- Create a SQL Warehouse (or use existing)
- Get connection details for Power BI/Tableau
- Connect your BI tool to the gold.customer_360 table

---

## Quick Tips & Best Practices

### dbt Development
- **Incremental models**: For large tables, use `{{ config(materialized='incremental') }}`
- **Use refs**: Always use `{{ ref('model_name') }}` instead of table names
- **Layer separation**: staging → intermediate → gold (don't skip layers)
- **Model naming**: `stg_` for staging, `int_` for intermediate, no prefix for gold

### Testing Strategy
- Add tests for all primary keys (unique, not_null)
- Test relationships between tables
- Add custom tests for business rules
- Run `dbt test` before committing

### Performance
- Materialize staging as views (fast, no storage)
- Materialize gold as tables (optimized for BI queries)
- Use intermediate models to break complex logic into steps
- Partition large tables by date if needed

### Documentation
- Add descriptions to all models and columns in schema.yml
- Use `dbt docs generate` to create lineage diagrams
- Document business logic decisions in model .sql files

---

## Troubleshooting

**"Connection refused"**: Check cluster is running in Databricks

**"Database not found"**: Verify schema name in profiles.yml matches Databricks

**"Token expired"**: Generate new access token in Databricks settings

**"Model not found"**: Run `dbt run` before `dbt test`

---

**Setup complete!** You now have a working Databricks + dbt environment for the Customer 360 case study.
