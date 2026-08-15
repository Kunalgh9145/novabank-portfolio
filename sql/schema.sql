-- =====================================================================
-- NovaBank Portfolio Project - Database Schema (MySQL 8.x)
-- ---------------------------------------------------------------------
-- Purpose: create the tables used for the NovaBank analysis.
-- Tables:
--   1. branches      - branch lookup (15 branches)
--   2. customers     - customer master data (100 customers)
--   3. transactions  - cleaned transaction fact table (21,915 rows)
--
-- How to run:
--   Option A (command line):  mysql -u root -p < schema.sql
--   Option B (MySQL Workbench): open the file and click the lightning bolt
--
-- NOTE: the cleaned CSV keeps customer_name and account_type inside
-- transactions as well. This is deliberately "denormalized" so the CSV can
-- be imported with one simple LOAD DATA and so beginners can see both styles.
-- The customers/branches tables exist so you can also practice proper JOINs.
-- =====================================================================

CREATE DATABASE IF NOT EXISTS novabank;
USE novabank;

-- ---------------------------------------------------------------------
-- 1) branches  (15 rows, loaded from data/branches.csv)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS branches (
    branch_code  CHAR(5)      NOT NULL,           -- e.g. BR001
    branch_name  VARCHAR(60)  NOT NULL,           -- e.g. NovaBank Mumbai Branch
    city         VARCHAR(40)  NOT NULL,
    region       VARCHAR(20)  NOT NULL,           -- North / South / West / East / Central
    PRIMARY KEY (branch_code)
);

-- ---------------------------------------------------------------------
-- 2) customers  (100 rows, loaded from data/customers.csv)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS customers (
    customer_id    CHAR(8)        NOT NULL,       -- e.g. CUST1001
    customer_name  VARCHAR(80)    NOT NULL,
    age            TINYINT UNSIGNED,              -- 21-70
    gender         CHAR(1),                       -- M / F
    city           VARCHAR(40)    NOT NULL,
    branch_code    CHAR(5),                       -- link to branches
    account_type   VARCHAR(20)    NOT NULL,       -- Savings / Current / Credit Card
    opening_balance DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    PRIMARY KEY (customer_id),
    CONSTRAINT fk_cust_branch FOREIGN KEY (branch_code)
        REFERENCES branches (branch_code)
);

-- ---------------------------------------------------------------------
-- 3) transactions  (21,915 rows, loaded from data/cleaned_transactions.csv)
--    This is the "fact" table of the star schema. amount > 1,000,000 is
--    flagged with is_outlier = 1.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS transactions (
    transaction_id            CHAR(10)     NOT NULL,   -- e.g. TXN0000001
    customer_id               CHAR(8)      NOT NULL,   -- link to customers
    customer_name             VARCHAR(80)  NOT NULL,   -- denormalized copy (see note above)
    account_type              VARCHAR(20)  NOT NULL,   -- denormalized copy
    transaction_date          DATE         NOT NULL,   -- standard YYYY-MM-DD
    transaction_time          TIME,
    transaction_type          VARCHAR(20),             -- Debit / Credit / Transfer / Withdrawal / Deposit
    category                  VARCHAR(30),             -- Groceries, Rent, Salary, ...
    amount                    DECIMAL(12,2),           -- always a number here
    balance_after_transaction DECIMAL(12,2),
    city                      VARCHAR(40),
    payment_mode              VARCHAR(20),             -- UPI / Card / Net Banking / Cash / Cheque
    status                    VARCHAR(20),             -- Success / Failed / Pending
    is_outlier                TINYINT      NOT NULL DEFAULT 0,  -- 1 if amount > 1,000,000
    PRIMARY KEY (transaction_id),
    CONSTRAINT fk_txn_customer FOREIGN KEY (customer_id)
        REFERENCES customers (customer_id)
);

-- Indexes speed up the queries that filter by date / category / customer.
CREATE INDEX idx_txn_date     ON transactions (transaction_date);
CREATE INDEX idx_txn_customer ON transactions (customer_id);
CREATE INDEX idx_txn_category ON transactions (category);

-- ---------------------------------------------------------------------
-- 4) raw_transactions_staging  (22,462 rows, loaded from raw_transactions.csv)
--    Everything is stored as TEXT because the raw file is intentionally
--    dirty: mixed date formats, missing values, text amounts, etc.
--    We only create it when you want to practice cleaning inside SQL.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_transactions_staging (
    transaction_id            VARCHAR(20),
    customer_id               VARCHAR(20),
    customer_name             TEXT,
    account_type              VARCHAR(20),
    transaction_date          TEXT,               -- mixed formats live here
    transaction_time          VARCHAR(20),
    transaction_type          VARCHAR(20),
    category                  TEXT,               -- may be empty
    amount                    TEXT,               -- may be empty or "₹1,234.56"
    balance_after_transaction TEXT,
    city                      TEXT,
    payment_mode              TEXT,               -- may be empty
    status                    TEXT
);
