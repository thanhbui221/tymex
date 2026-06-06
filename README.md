Overview and Instructions

The case study represents a challenge our data engineering team faces in building the gold layer for business reporting. Your task is to design and implment a solution using Databricks and dbt.

Category | Description
Technical implementation | Correct use of dbt, SQL, and Databricks
Business understading | Clear understadning of business goals
Code quality and documentation | Modular, readable, and well-documented
Data modelling, transformation logic, test and validation | data models / schema, transform rules, dbt tests, edge case
Presentation / usability readiness | Clarity of documentation and final output

Expected Deliverables
dbt project folder (models, tests, documentation)
SQL Logic for transformations
Markdown or PDF explaining business logic and decisions
Presentation / Walk throught (Optional: screenshots or notebook exports from Databricks)

Case study: Customer 360 Data Mart Build
Scenario: The bank wants an unified view of customer behavior across products (credit carts, savings). Raw data is scattered across multiple systems. 

Tasks:
- Ingest raw data from multiple sources (e.g. transactions, CRM, product systems)
- Use dbt to model a gold-layer table: customer_360
- Apply business logic (e.g. active customer definition, segmentation)
- OPtimize for reporting (e.q. Power Bi or Tableau consumption)

Skills Tested:
- dbt modeling
- Data cleansing and transformation
- Business logic implementation
- Performance optimization

Goal: Create an unified view of customer behavior across products
Input:
- customer_raw
- product_enrollments
- crm_interations
- transaction_history

Deliverables:
- customer_360: gold-layer table
- dbt models and tests

Documentation of business logic

Expected Outputs:
- customer_360 table with unified customer profile (Key business logic must be included but apply your mind and define additional metrics and dimensions that will provide valuable insights to the business)

Key Business Logic:
- Define “active customer” (e.g., recent transaction or interaction)
- Aggregate product holdings per customer
- Include last interaction date and total transaction value

Data quality:
- Be on the lookout for potential data quality issues, build appropriate tests to validate data quality and highlight potential problems.

Documentation:
- Documentation must be clear and concise, should cover data model design, lineage, data quality, rational and motivation for business metrics included in your customer 360 output.