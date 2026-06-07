# Customer 360 Data Mart - Case Study

## Overview

This case study represents a real-world challenge in building a gold-layer data mart for business reporting. Your task is to design and implement a **customer_360** solution using **Databricks** and **dbt**.

## Evaluation Criteria

| Category | Description |
|----------|-------------|
| **Technical Implementation** | Correct use of dbt, SQL, and Databricks |
| **Business Understanding** | Clear understanding of business goals |
| **Code Quality and Documentation** | Modular, readable, and well-documented code |
| **Data Modeling & Transformation** | Data models/schema, transformation rules, dbt tests, edge case handling |
| **Presentation & Usability** | Clarity of documentation and final output |

## Expected Deliverables

1. **dbt Project Structure**
   - Models (staging, intermediate, gold layers)
   - Tests and validation
   - Documentation

2. **SQL Transformation Logic**
   - Clear, well-commented SQL for all transformations
   - Business logic implementation

3. **Documentation**
   - Markdown or PDF explaining business logic and design decisions
   - Data model design and lineage
   - Rationale for metrics and dimensions

4. **Presentation Materials** (Optional)
   - Screenshots or notebook exports from Databricks
   - Walkthrough of the solution

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
See `schema.md` for detailed table structures and sample data.

- `customer_raw`: Customer demographic and signup information
- `product_enrollments`: Product enrollment records (Savings, Credit Card)
- `crm_transactions`: Customer interaction records (Email, Chat, Phone)
- `transaction_history`: Financial transaction records across all products

### Output: customer_360 Table

**Primary Deliverable**: A gold-layer table with unified customer profiles.

**Required Business Logic** (must include):
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

1. **Identify Data Quality Issues**
   - Missing or null values
   - Duplicate records
   - Data type inconsistencies
   - Referential integrity violations
   - Outliers and anomalies

2. **Build Appropriate dbt Tests**
   - Uniqueness tests on primary keys
   - Not-null tests on critical fields
   - Relationship tests (foreign key validation)
   - Accepted values tests for categorical fields
   - Custom tests for business rule validation

3. **Document and Highlight Problems**
   - Flag any data quality issues discovered
   - Explain impact on business metrics
   - Propose remediation strategies

---

## Documentation Requirements

Your documentation must be **clear and concise**, covering:

### 1. Data Model Design
- Entity relationship diagrams
- Table schemas and column descriptions
- Grain and cardinality of each model layer

### 2. Data Lineage
- Source-to-target mapping
- Transformation flow across layers (raw → staging → intermediate → gold)
- Dependencies between models

### 3. Data Quality
- Tests implemented and their purpose
- Known data quality issues
- Assumptions and limitations

### 4. Business Metrics
- Definition of each calculated metric
- Rationale and business value
- Calculation methodology
- Edge cases and handling

### 5. Design Decisions
- Why specific modeling approaches were chosen
- Trade-offs considered
- Performance optimization strategies

---

## Getting Started

1. Review `schema.md` for detailed source table structures
2. Set up your Databricks environment
3. Initialize your dbt project
4. Build staging models for each source table
5. Implement transformation logic in intermediate models
6. Create the final `customer_360` gold-layer table
7. Add comprehensive tests and documentation
8. Validate and optimize for BI consumption

Good luck!