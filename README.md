# Customer 360 Data Mart - Case Study

## Overview

This case study represents a real-world challenge in building a gold-layer data mart for business reporting. Your task is to design and implement a **customer_360** solution using **Databricks** and **dbt**.

## Repository Structure

```
tymex/
├── README.md                        # This file — case study brief
├── schema.md                        # Source table schemas and sample data
├── notes.md                         # End-to-end setup playbook
├── data/                            # Raw CSV source files
│   ├── customer_raw.csv
│   ├── product_enrollments.csv
│   ├── crm_interactions.csv
│   ├── transaction_history.csv
│   └── split_transaction_history/   # transaction_history split into 200k-row chunks
├── databricks-scripts/              # Notebooks and helper scripts
│   ├── ingest_bronze.py             # One-time CSV → Delta table seed
│   ├── data_quality.py              # Data quality profiling notebook (bronze layer)
│   ├── data_eda_gold.py             # EDA notebook for gold layer (customer_360)
│   └── maintenance/                 # OPTIMIZE and VACUUM scripts
├── terraform/                       # Infrastructure as Code
│   ├── README.md                    # Deployment order and module wiring
│   ├── databricks-foundation/       # Cluster, SQL Warehouse, schema (deploy first)
│   │   └── README.md
│   └── databricks-workflows/        # Scheduled dbt jobs (deploy second)
│       └── README.md
├── customer_360/                    # dbt project (Bronze → Silver → Gold)
│   └── README.md
└── docs/
    ├── data_model_design.md         # ERD, table schemas, grain and cardinality per layer
    ├── erd.svg                   # Entity relationship diagram — source tables, PKs, FKs, cardinality
    ├── data_lineage.md              # Source-to-target mapping, transformation flow, model dependencies
    ├── data_lineage.svg          # Visual lineage diagram (open with diagrams.net)
    ├── data_quality.md              # DQ findings, impact on metrics, remediation strategies
    ├── business_metrics.md          # Metric definitions, rationale, edge cases
    ├── design_decisions.md          # Modeling approach, trade-offs, performance optimization
    └── clustering_comparison.md     # Liquid Clustering vs Z-Ordering analysis
```

**Where to go for setup:** see [`notes.md`](notes.md) for the end-to-end playbook.

---

## Evaluation Criteria

| Category | Description |
|----------|-------------|
| **Technical Implementation** | Correct use of dbt, SQL, and Databricks |
| **Business Understanding** | Clear understanding of business goals |
| **Code Quality and Documentation** | Modular, readable, and well-documented code |
| **Data Modeling & Transformation** | Data models/schema, transformation rules, dbt tests, edge case handling |
| **Presentation & Usability** | Clarity of documentation and final output |

## Expected Deliverables

1. **dbt Project Structure** → [`customer_360/`](customer_360/)
   - Models (staging, intermediate, gold layers)
   - Tests and validation
   - Documentation

2. **SQL Transformation Logic** → [`customer_360/models/`](customer_360/models/)
   - Clear, well-commented SQL for all transformations
   - Business logic implementation

3. **Documentation** → [`docs/`](docs/)
   - Markdown or PDF explaining business logic and design decisions
   - Data model design and lineage
   - Rationale for metrics and dimensions

4. **Presentation Materials** (Optional) → [`databricks-scripts/`](databricks-scripts/)
   - Screenshots or notebook exports from Databricks
   - Walkthrough of the solution
   - Link to the presentation: https://docs.google.com/presentation/d/1cyhUtmfU4fpxw-QwgzmaTMCkPfYoqtjjKpf1U_Nw6NA/edit?usp=sharing

---

## Case Study: Customer 360 Data Mart Build

### Scenario

The bank wants a unified view of customer behavior across products (credit cards, savings accounts). Raw data is currently scattered across multiple systems and needs to be consolidated into a single, reporting-ready gold-layer table.

### Your Tasks

1. **Data Ingestion**
   - Ingest raw data from multiple source systems (transactions, CRM, product systems)
   
2. **dbt Modeling**
   - Build a gold-layer table: `customer_360`
   - Create staging and intermediate models as needed
   
3. **Business Logic Implementation**
   - Define "active customer" criteria
   - Implement customer segmentation
   - Calculate aggregated metrics
   
4. **Optimization**
   - Optimize for BI tool consumption (Power BI or Tableau)
   - Ensure query performance and usability

### Skills Tested

- **dbt Modeling**: Layered data architecture (staging → intermediate → gold)
- **Data Cleansing and Transformation**: Handling missing data, standardization, deduplication
- **Business Logic Implementation**: Translating requirements into SQL logic
- **Performance Optimization**: Query tuning, materialization strategies

---

## Technical Specifications

### Goal
Create a unified view of customer behavior across all products for business analytics and reporting.

### Input Tables
See [`schema.md`](schema.md) for detailed table structures and sample data. See [`docs/erd.svg`](docs/erd.svg) for the entity relationship diagram.

- `customer_raw`: Customer demographic and signup information
- `product_enrollments`: Product enrollment records (Savings, Credit Card)
- `crm_interactions`: Customer interaction records (Email, Chat, Phone)
- `transaction_history`: Financial transaction records across all products

### Output: customer_360 Table

**Primary Deliverable**: A gold-layer table with unified customer profiles. → [`customer_360/models/gold/customer_360.sql`](customer_360/models/gold/customer_360.sql)

**Required Business Logic** (must include): → [`docs/business_metrics.md`](docs/business_metrics.md)
- **Active Customer Definition**: Define criteria for identifying active customers (e.g., recent transaction or interaction within a specific timeframe)
- **Product Holdings Aggregation**: Count and summarize products per customer
- **Last Interaction Date**: Most recent CRM interaction for each customer
- **Total Transaction Value**: Aggregate transaction amounts per customer

**Additional Metrics** (apply your judgment):
- Define additional metrics and dimensions that provide valuable business insights
- Consider customer lifetime value, engagement scores, risk indicators, etc.
- Justify your choices in the documentation

---

## Data Quality Requirements

**Critical**: Be vigilant about potential data quality issues throughout your implementation.

### Your Responsibilities

1. **Identify Data Quality Issues** → [`databricks-scripts/data_quality.py`](databricks-scripts/data_quality.py)
   - Missing or null values
   - Duplicate records
   - Data type inconsistencies
   - Referential integrity violations
   - Outliers and anomalies

2. **Build Appropriate dbt Tests** → [`customer_360/models/bronze/schema.yml`](customer_360/models/bronze/schema.yml) · [`customer_360/models/silver/schema.yml`](customer_360/models/silver/schema.yml) · [`customer_360/models/gold/schema.yml`](customer_360/models/gold/schema.yml) · [`customer_360/tests/`](customer_360/tests/)
   - Uniqueness tests on primary keys
   - Not-null tests on critical fields
   - Relationship tests (foreign key validation)
   - Accepted values tests for categorical fields
   - Custom tests for business rule validation

3. **Document and Highlight Problems** → [`docs/data_quality.md`](docs/data_quality.md)
   - Flag any data quality issues discovered
   - Explain impact on business metrics
   - Propose remediation strategies

---

## Documentation Requirements

Your documentation must be **clear and concise**, covering:

### 1. Data Model Design
- Entity relationship diagrams. [`docs/erd.svg`](docs/erd.svg)
- Table schemas and column descriptions. [`schema.md`](schema.md)
- Grain and cardinality of each model layer. [`docs/data_model_design.md`](docs/data_model_design.md)

### 2. Data Lineage
- Source-to-target mapping. 
- Transformation flow across layers (raw → staging → intermediate → gold)
- Dependencies between models
- [`docs/data_lineage.md`](docs/data_lineage.md)

### 3. Data Quality
- Tests implemented and their purpose
- Known data quality issues
- Assumptions and limitations

Check all these related docs and code:
- [`docs/data_quality.md`](docs/data_quality.md) 
- [`databricks-scripts/data_quality.py`](databricks-scripts/data_quality.py)
- [`customer_360/models/bronze/schema.yml`](customer_360/models/bronze/schema.yml)
- [`customer_360/models/silver/schema.yml`](customer_360/models/silver/schema.yml)
- [`customer_360/models/gold/schema.yml`](customer_360/models/gold/schema.yml)
- [`customer_360/tests/`](customer_360/tests/)

### 4. Business Metrics
- Definition of each calculated metric
- Rationale and business value
- Calculation methodology
- Edge cases and handling

→ [`docs/business_metrics.md`](docs/business_metrics.md)

### 5. Design Decisions
- Why specific modeling approaches were chosen
- Trade-offs considered
- Performance optimization strategies

→ [`docs/design_decisions.md`](docs/design_decisions.md)
---

## Getting Started

1. Review [`schema.md`](schema.md) for detailed source table structures
2. Follow [`notes.md`](notes.md) to set up your Databricks environment and run the full pipeline
3. Build staging models for each source table
4. Implement transformation logic in intermediate models
5. Create the final `customer_360` gold-layer table
6. Add comprehensive tests and documentation
7. Validate and optimize for BI consumption

