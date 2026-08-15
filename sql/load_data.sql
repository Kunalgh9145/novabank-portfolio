-- =====================================================================
-- NovaBank Portfolio Project - Load the CSVs (MySQL)
-- ---------------------------------------------------------------------
-- Run schema.sql FIRST, then run this file to fill the tables.
--
-- Requirement: MySQL must be started with local-infile support.
--   Option A (command line):
--       mysql --local-infile=1 -u root -p < schema.sql
--       mysql --local-infile=1 -u root -p < load_data.sql
--   Option B (Workbench): Settings -> Local INFILE -> ON.
--
-- IMPORTANT: change the paths below to the real location of your CSV files,
-- e.g. C:/Users/You/novabank-portfolio/data/cleaned_transactions.csv on Windows.
-- =====================================================================

USE novabank;

-- ---------------------------------------------------------------------
-- 1) branches.csv
-- ---------------------------------------------------------------------
LOAD DATA LOCAL INFILE '/workspace/novabank-portfolio/data/branches.csv'
INTO TABLE branches
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES                      -- skip the header row
(branch_code, branch_name, city, region);

-- ---------------------------------------------------------------------
-- 2) customers.csv
-- ---------------------------------------------------------------------
LOAD DATA LOCAL INFILE '/workspace/novabank-portfolio/data/customers.csv'
INTO TABLE customers
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(customer_id, customer_name, age, gender, city, branch_code, account_type, opening_balance);

-- ---------------------------------------------------------------------
-- 3) cleaned_transactions.csv
--    The CSV has 14 columns; the last one (Is_Outlier) maps to the
--    is_outlier column of the table. LOAD DATA maps them positionally.
-- ---------------------------------------------------------------------
LOAD DATA LOCAL INFILE '/workspace/novabank-portfolio/data/cleaned_transactions.csv'
INTO TABLE transactions
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(transaction_id, customer_id, customer_name, account_type, transaction_date,
 transaction_time, transaction_type, category, amount, balance_after_transaction,
 city, payment_mode, status, is_outlier);

-- ---------------------------------------------------------------------
-- 4) OPTIONAL - raw_transactions_staging
--    Only needed if you want to practice cleaning inside SQL (see queries.sql,
--    Section 1 and Section 2).
-- ---------------------------------------------------------------------
LOAD DATA LOCAL INFILE '/workspace/novabank-portfolio/data/raw_transactions.csv'
INTO TABLE raw_transactions_staging
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(transaction_id, customer_id, customer_name, account_type, transaction_date,
 transaction_time, transaction_type, category, amount, balance_after_transaction,
 city, payment_mode, status);

-- ---------------------------------------------------------------------
-- Sanity checks - run these to confirm the load worked.
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS branches_loaded        FROM branches;
SELECT COUNT(*) AS customers_loaded       FROM customers;
SELECT COUNT(*) AS transactions_loaded    FROM transactions;
SELECT COUNT(*) AS raw_staging_loaded     FROM raw_transactions_staging;

-- ---------------------------------------------------------------------
-- PostgreSQL note
-- ---------------------------------------------------------------------
-- If you prefer PostgreSQL you can use the COPY command instead, for example:
--
--   COPY branches      FROM '/path/to/data/branches.csv'      DELIMITER ',' CSV HEADER;
--   COPY customers     FROM '/path/to/data/customers.csv'     DELIMITER ',' CSV HEADER;
--   COPY transactions  FROM '/path/to/data/cleaned_transactions.csv' DELIMITER ',' CSV HEADER;
--
-- (Adjust the CREATE TABLE statements in schema.sql for PostgreSQL types,
--  e.g. TINYINT -> SMALLINT, TEXT/TIME work as-is.)
-- =====================================================================
