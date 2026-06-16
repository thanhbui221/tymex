# Data Schema Reference

## Table: customer_raw

**Description:** Raw customer demographic and signup information from the customer master system.

**Columns:**
- `customer_id` (INTEGER, PRIMARY KEY): Unique customer identifier
- `first_name` (STRING): Customer first name
- `last_name` (STRING): Customer last name
- `email` (STRING): Customer email address
- `mobile` (STRING): Customer mobile phone number
- `gender` (STRING): Customer gender (Male/Female)
- `date_of_birth` (DATE): Customer date of birth
- `signup_date` (DATE): Date when customer signed up

**Sample Data:**
```
customer_id | first_name | last_name | email                      | mobile      | gender | date_of_birth | signup_date
18231       | Kristina   | Pope      | kpope90465@yahoo.com       | 09408995771 | Female | 1982-08-02    | 2023-10-04
93481       | Elizabeth  | Black     | eblack29035@zohomail.com   | 09707540321 | Female | 1985-06-23    | 2023-05-02
67158       | Amanda     | Mccall    | amccall62737@yahoo.com     | 09481829568 | Female | 2005-11-01    | 2023-07-25
```

---

## Table: product_enrollments

**Description:** Product enrollment records showing which products customers have enrolled in.

**Columns:**
- `product_id` (INTEGER, PRIMARY KEY): Unique product enrollment identifier
- `customer_id` (INTEGER, FOREIGN KEY): References customer_raw.customer_id
- `product_type` (STRING): Type of product (Savings, Credit Card)
- `enrollment_date` (DATE): Date when customer enrolled in the product
- `limit` (DECIMAL): Credit limit for Credit Card products, 0.0 for Savings

**Sample Data:**
```
product_id | customer_id | product_type | enrollment_date | limit
20834      | 14876       | Savings      | 2023-10-24      | 0.0
62036      | 44308       | Credit Card  | 2024-12-30      | 83000.0
8611       | 6143        | Savings      | 2023-01-18      | 0.0
```

---

## Table: crm_interactions

**Description:** Customer interaction records from the CRM system.

**Columns:**
- `interaction_id` (INTEGER, PRIMARY KEY): Unique interaction identifier
- `customer_id` (INTEGER, FOREIGN KEY): References customer_raw.customer_id
- `interaction_type` (STRING): Type of interaction (Email, Chat, Call)
- `interaction_date` (DATE): Date of the interaction

**Sample Data:**
```
interaction_id | customer_id | interaction_type | interaction_date
189930         | 13306       | Email            | 2025-06-29
81484          | 79985       | Email            | 2025-06-11
25376          | 54209       | Chat             | 2025-01-19
```

---

## Table: transaction_history

**Description:** Financial transaction records across all products.

**Columns:**
- `transaction_id` (INTEGER, PRIMARY KEY): Unique transaction identifier
- `product_id` (INTEGER, FOREIGN KEY): References product_enrollments.product_id
- `customer_id` (INTEGER, FOREIGN KEY): References customer_raw.customer_id
- `transaction_amount` (DECIMAL): Transaction amount (negative for debits, positive for credits)
- `closing_balance` (DECIMAL): Account balance after transaction
- `transaction_date` (TIMESTAMP): Date and time of transaction

**Sample Data:**
```
product_id | customer_id | transaction_amount | closing_balance | transaction_date    | transaction_id
6874       | 4917        | -2671.76           | 9124.39         | 2025-06-10 12:20:06 | 296463
27644      | 19720       | 42558.77           | -465068.11      | 2025-06-30 23:58:14 | 881470
110562     | 78934       | -83197.21          | -420303.12      | 2025-06-30 11:56:59 | 660237
```

---

## Data Relationships

```
customer_raw (customer_id) 
    ├─→ product_enrollments (customer_id)
    │       └─→ transaction_history (product_id)
    └─→ crm_interactions (customer_id)
    └─→ transaction_history (customer_id)
```