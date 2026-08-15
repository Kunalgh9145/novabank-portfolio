-- =====================================================================
-- NovaBank Portfolio Project - Practice Queries (MySQL 8.x)
-- ---------------------------------------------------------------------
-- 15+ commented queries in 6 sections:
--   Section 1  Data quality checks        (run against raw_transactions_staging)
--   Section 2  Cleaning the data in SQL   (staging -> transactions)
--   Section 3  Aggregations               (monthly spend, balances, branch volume)
--   Section 4  Window functions           (running balance, ranking, MoM growth)
--   Section 5  Joins                      (transactions + customers + branches)
--   Section 6  Views for reporting
--
-- Every query is written for MySQL 8 (window functions, CTEs). The
-- expressions that differ a lot in other databases are noted in comments.
-- =====================================================================

USE novabank;

-- #####################################################################
-- SECTION 1 - DATA QUALITY CHECKS (run against the RAW staging table)
-- These queries show you how to *detect* the problems that were
-- deliberately planted in raw_transactions.csv.
-- #####################################################################

-- ---------------------------------------------------------------
-- Q1. Missing values: how many rows have empty Category / Payment Mode / Amount?
-- ---------------------------------------------------------------
SELECT
    SUM(CASE WHEN category      IS NULL OR TRIM(category)      = '' THEN 1 ELSE 0 END) AS missing_category,
    SUM(CASE WHEN payment_mode  IS NULL OR TRIM(payment_mode)  = '' THEN 1 ELSE 0 END) AS missing_payment_mode,
    SUM(CASE WHEN amount        IS NULL OR TRIM(amount)        = '' THEN 1 ELSE 0 END) AS missing_amount,
    COUNT(*) AS total_rows
FROM raw_transactions_staging;

-- ---------------------------------------------------------------
-- Q2. Duplicate rows: identical rows appearing more than once.
-- ---------------------------------------------------------------
SELECT transaction_id, customer_id, transaction_date, transaction_time,
       amount, payment_mode, status, COUNT(*) AS copies
FROM raw_transactions_staging
GROUP BY transaction_id, customer_id, transaction_date, transaction_time,
         amount, payment_mode, status
HAVING COUNT(*) > 1
ORDER BY copies DESC
LIMIT 10;

-- ---------------------------------------------------------------
-- Q3. Inconsistent date formats: which formats exist?
--     We simply count the rows that match each possible pattern.
-- ---------------------------------------------------------------
SELECT
    SUM(CASE WHEN transaction_date REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN 1 ELSE 0 END) AS yyyy_mm_dd,
    SUM(CASE WHEN transaction_date REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}$' THEN 1 ELSE 0 END) AS dd_mm_yyyy,
    SUM(CASE WHEN transaction_date REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$' THEN 1 ELSE 0 END) AS mm_dd_yyyy,
    SUM(CASE WHEN transaction_date REGEXP '^[0-9]{2}-[A-Za-z]{3}-[0-9]{4}$' THEN 1 ELSE 0 END) AS dd_mon_yyyy,
    COUNT(*) AS total_rows
FROM raw_transactions_staging;

-- ---------------------------------------------------------------
-- Q4. Amount stored as text: any value containing symbols or commas.
-- ---------------------------------------------------------------
SELECT transaction_id, amount
FROM raw_transactions_staging
WHERE amount LIKE '%₹%' OR amount LIKE '%,%'
LIMIT 10;

-- ---------------------------------------------------------------
-- Q5. Outliers: amounts that look unrealistic (> 1,000,000).
-- ---------------------------------------------------------------
SELECT transaction_id, customer_id, category, amount
FROM raw_transactions_staging
WHERE amount NOT IN ('', ',')
  AND CAST(REPLACE(REPLACE(amount, '₹', ''), ',', '') AS DECIMAL(12,2)) > 1000000
ORDER BY CAST(REPLACE(REPLACE(amount, '₹', ''), ',', '') AS DECIMAL(12,2)) DESC;

-- #####################################################################
-- SECTION 2 - CLEANING THE DATA IN SQL
-- This INSERT moves raw_transactions_staging into the clean
-- transactions table, applying the cleaning rules as it goes:
--   * TRIM + title-case text
--   * map account type / category / city / payment-mode variants
--   * convert every date format to YYYY-MM-DD
--   * parse text amounts ("₹1,234.56" -> 1234.56)
--   * impute missing amounts with the category median
--   * fix negative balances on Credit Card accounts
--   * flag outliers with is_outlier
-- #####################################################################

-- Q6. One big "cleaning" query. Run it ONLY if the transactions table is
--     currently empty (e.g. re-create it first: DROP TABLE transactions;).
--     INSERT IGNORE skips the exact duplicate rows, because a duplicate has
--     the same transaction_id, which would violate the primary key.
WITH parsed AS (                                 -- 1) parse every amount into a number
    SELECT s.*,
           CAST(REPLACE(REPLACE(NULLIF(TRIM(s.amount), ''), '₹', ''), ',', '')
                AS DECIMAL(12,2)) AS parsed_amount
    FROM raw_transactions_staging s
),
median_amount AS (                               -- 2) median amount per category (MySQL 8)
    SELECT LOWER(TRIM(category)) AS category, amount AS median_amount
    FROM (
        SELECT LOWER(TRIM(category)) AS category, parsed_amount AS amount,
               ROW_NUMBER() OVER (PARTITION BY LOWER(TRIM(category)) ORDER BY parsed_amount) AS rn,
               COUNT(*)     OVER (PARTITION BY LOWER(TRIM(category)))                         AS cnt
        FROM parsed
        WHERE parsed_amount IS NOT NULL
    ) x
    WHERE rn = FLOOR((cnt + 1) / 2)
)
INSERT IGNORE INTO transactions
    (transaction_id, customer_id, customer_name, account_type, transaction_date,
     transaction_time, transaction_type, category, amount, balance_after_transaction,
     city, payment_mode, status, is_outlier)
SELECT
    p.transaction_id,
    p.customer_id,
    TRIM(REPLACE(p.customer_name, '  ', ' '))                               AS customer_name,
    CASE LOWER(TRIM(p.account_type))                                        -- account variants
        WHEN 'savings' THEN 'Savings' WHEN 'sav' THEN 'Savings' WHEN 'saving' THEN 'Savings'
        WHEN 'current' THEN 'Current' WHEN 'cur' THEN 'Current' WHEN 'curr' THEN 'Current'
        WHEN 'credit card' THEN 'Credit Card' WHEN 'cc' THEN 'Credit Card'
        WHEN 'credit' THEN 'Credit Card' WHEN 'creditcard' THEN 'Credit Card'
        ELSE TRIM(p.account_type)
    END                                                                     AS account_type,
    COALESCE(                                -- 3) any date format -> YYYY-MM-DD
        STR_TO_DATE(p.transaction_date, '%Y-%m-%d'),
        STR_TO_DATE(p.transaction_date, '%d/%m/%Y'),
        STR_TO_DATE(p.transaction_date, '%m-%d-%Y'),
        STR_TO_DATE(p.transaction_date, '%d-%b-%Y')
    )                                                                       AS transaction_date,
    p.transaction_time,
    CONCAT(UPPER(LEFT(TRIM(p.transaction_type), 1)),
           LOWER(SUBSTRING(TRIM(p.transaction_type), 2)))                   AS transaction_type,
    COALESCE(                                -- 4) category: map variants, else title-case
        CASE LOWER(TRIM(p.category))
            WHEN ''              THEN NULL
            WHEN 'grocery'       THEN 'Groceries'
            WHEN 'grocries'      THEN 'Groceries'
            WHEN 'groceires'     THEN 'Groceries'
            WHEN 'shooping'      THEN 'Shopping'
            WHEN 'utilitiies'    THEN 'Utilities'
            WHEN 'entertainmnt'  THEN 'Entertainment'
            WHEN 'healtcare'     THEN 'Healthcare'
            WHEN 'travl'         THEN 'Travel'
            WHEN 'loanpay'       THEN 'Loan Payment'
            WHEN 'transfer'      THEN 'Personal Transfer'
            WHEN 'withdrawal'    THEN 'Cash Withdrawal'
            WHEN 'deposit'       THEN 'Cash Deposit'
            ELSE CONCAT(UPPER(LEFT(TRIM(p.category), 1)),
                        LOWER(SUBSTRING(TRIM(p.category), 2)))
        END,
        'Uncategorized'                                                      -- missing category
    )                                                                       AS category,
    COALESCE(m.median_amount, p.parsed_amount)                               AS amount, -- 5) impute
    CASE WHEN LOWER(TRIM(p.account_type)) IN ('credit card','cc','credit','creditcard')
              AND CAST(p.balance_after_transaction AS DECIMAL(12,2)) < 0
         THEN -CAST(p.balance_after_transaction AS DECIMAL(12,2))            -- 6) fix sign
         ELSE  CAST(p.balance_after_transaction AS DECIMAL(12,2))
    END                                                                     AS balance_after_transaction,
    CASE LOWER(TRIM(p.city))                                                 -- city variants
        WHEN 'bengluru'  THEN 'Bengaluru'
        WHEN 'bangalore' THEN 'Bengaluru'
        WHEN 'chenai'    THEN 'Chennai'
        WHEN 'hydrabad'  THEN 'Hyderabad'
        WHEN 'jaipr'     THEN 'Jaipur'
        ELSE CONCAT(UPPER(LEFT(TRIM(p.city), 1)), LOWER(SUBSTRING(TRIM(p.city), 2)))
    END                                                                     AS city,
    COALESCE(                                -- 7) payment mode variants
        CASE LOWER(TRIM(p.payment_mode))
            WHEN ''                 THEN NULL
            WHEN 'netbanking'       THEN 'Net Banking'
            WHEN 'internet banking' THEN 'Net Banking'
            ELSE CONCAT(UPPER(LEFT(TRIM(p.payment_mode), 1)),
                        LOWER(SUBSTRING(TRIM(p.payment_mode), 2)))
        END,
        'Unknown'
    )                                                                       AS payment_mode,
    CONCAT(UPPER(LEFT(TRIM(p.status), 1)),
           LOWER(SUBSTRING(TRIM(p.status), 2)))                             AS status,
    CASE WHEN COALESCE(m.median_amount, p.parsed_amount) > 1000000
         THEN 1 ELSE 0 END                                                  AS is_outlier -- 8)
FROM parsed p
LEFT JOIN median_amount m ON m.category = LOWER(TRIM(p.category));

-- Q6b. How many rows ended up in the clean table?
SELECT COUNT(*) AS cleaned_rows FROM transactions;

-- #####################################################################
-- SECTION 3 - AGGREGATIONS
-- #####################################################################

-- ---------------------------------------------------------------
-- Q7. Monthly spend by category (only Debit-type spending).
--     This is the classic "big picture" report.
-- ---------------------------------------------------------------
SELECT
    DATE_FORMAT(transaction_date, '%Y-%m')   AS month,
    category,
    COUNT(*)                                 AS transaction_count,
    ROUND(SUM(amount), 2)                    AS total_spend
FROM transactions
WHERE is_outlier = 0                          -- exclude the fat-finger entries
  AND transaction_type = 'Debit'
GROUP BY DATE_FORMAT(transaction_date, '%Y-%m'), category
ORDER BY month, total_spend DESC;

-- ---------------------------------------------------------------
-- Q8. Per-customer summary: inflow, outflow and net change (2023-2024).
--     Note: Personal Transfers are counted as outflows here because the
--     CSV does not record their direction; filter by transaction_type to
--     refine if you like.
-- ---------------------------------------------------------------
SELECT
    customer_id,
    customer_name,
    COUNT(*)                    AS successful_transactions,
    ROUND(SUM(CASE WHEN transaction_type IN ('Credit','Deposit') THEN amount ELSE 0 END), 2) AS total_inflow,
    ROUND(SUM(CASE WHEN transaction_type IN ('Debit','Withdrawal') THEN amount ELSE 0 END), 2) AS total_outflow,
    ROUND(SUM(CASE WHEN transaction_type IN ('Credit','Deposit') THEN amount ELSE -amount END), 2) AS net_change
FROM transactions
WHERE is_outlier = 0
  AND status = 'Success'          -- failed / pending rows did not move money
GROUP BY customer_id, customer_name
ORDER BY net_change DESC
LIMIT 15;

-- ---------------------------------------------------------------
-- Q9. Branch-wise transaction volume (joins transactions -> customers -> branches)
-- ---------------------------------------------------------------
SELECT
    b.branch_code,
    b.city,
    b.region,
    COUNT(*)                        AS transactions,
    ROUND(SUM(t.amount), 2)         AS total_amount
FROM transactions t
JOIN customers c ON t.customer_id = c.customer_id
JOIN branches   b ON c.branch_code = b.branch_code
WHERE t.is_outlier = 0
GROUP BY b.branch_code, b.city, b.region
ORDER BY transactions DESC;

-- ---------------------------------------------------------------
-- Q10. Failure rate overall: what share of transactions failed?
-- ---------------------------------------------------------------
SELECT
    status,
    COUNT(*)                       AS count,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM transactions
GROUP BY status
ORDER BY count DESC;

-- #####################################################################
-- SECTION 4 - WINDOW FUNCTIONS
-- #####################################################################

-- ---------------------------------------------------------------
-- Q11. Running balance: running total of (inflow - outflow) over time,
--      recalculated for each customer. Classic ledger report.
-- ---------------------------------------------------------------
SELECT
    transaction_id,
    customer_id,
    transaction_date,
    transaction_type,
    amount,
    ROUND(SUM(CASE WHEN transaction_type IN ('Credit','Deposit') THEN amount
                   ELSE -amount END)
          OVER (PARTITION BY customer_id ORDER BY transaction_date, transaction_time), 2) AS running_balance
FROM transactions
WHERE is_outlier = 0
  AND status = 'Success'
ORDER BY customer_id, transaction_date, transaction_time
LIMIT 50;

-- ---------------------------------------------------------------
-- Q12. Rank customers by total spend (DENSE_RANK - ties get the same rank)
-- ---------------------------------------------------------------
WITH customer_spend AS (
    SELECT
        customer_id,
        customer_name,
        ROUND(SUM(amount), 2) AS total_spend
    FROM transactions
    WHERE transaction_type = 'Debit' AND is_outlier = 0
    GROUP BY customer_id, customer_name
)
SELECT
    customer_id,
    customer_name,
    total_spend,
    DENSE_RANK() OVER (ORDER BY total_spend DESC) AS spend_rank
FROM customer_spend
ORDER BY spend_rank
LIMIT 10;

-- ---------------------------------------------------------------
-- Q13. Month-over-month growth of total spend, using LAG().
-- ---------------------------------------------------------------
WITH monthly AS (
    SELECT
        DATE_FORMAT(transaction_date, '%Y-%m') AS month,
        ROUND(SUM(amount), 2)                  AS total_spend
    FROM transactions
    WHERE transaction_type = 'Debit' AND is_outlier = 0
    GROUP BY DATE_FORMAT(transaction_date, '%Y-%m')
)
SELECT
    month,
    total_spend,
    LAG(total_spend) OVER (ORDER BY month) AS prev_month_spend,
    ROUND(100 * (total_spend - LAG(total_spend) OVER (ORDER BY month))
                 / LAG(total_spend) OVER (ORDER BY month), 2) AS mom_growth_pct
FROM monthly
ORDER BY month;

-- #####################################################################
-- SECTION 5 - JOINS
-- #####################################################################

-- ---------------------------------------------------------------
-- Q14. Top 10 customers by spend, enriched with age, gender and city
--      (shows how transactions + customers + branches fit together).
-- ---------------------------------------------------------------
SELECT
    c.customer_id,
    c.customer_name,
    c.age,
    c.gender,
    c.city,
    b.region,
    ROUND(SUM(t.amount), 2) AS total_spend
FROM transactions t
JOIN customers c ON t.customer_id = c.customer_id
JOIN branches   b ON c.branch_code = b.branch_code
WHERE t.transaction_type = 'Debit' AND t.is_outlier = 0
GROUP BY c.customer_id, c.customer_name, c.age, c.gender, c.city, b.region
ORDER BY total_spend DESC
LIMIT 10;

-- ---------------------------------------------------------------
-- Q15. Transaction count per customer using a LEFT JOIN.
--      A customer with no transactions would appear with count = 0
--      (NULL on the right side) - that is exactly what the LEFT JOIN
--      is for. In this dataset every customer has transactions, so we
--      rank them by volume instead.
-- ---------------------------------------------------------------
SELECT
    c.customer_id,
    c.customer_name,
    COUNT(t.transaction_id) AS transaction_count
FROM customers c
LEFT JOIN transactions t ON c.customer_id = t.customer_id
GROUP BY c.customer_id, c.customer_name
ORDER BY transaction_count DESC
LIMIT 10;

-- #####################################################################
-- SECTION 6 - VIEWS FOR REPORTING
-- Views save a query and let you SELECT from it like a table.
-- #####################################################################

-- ---------------------------------------------------------------
-- Q16. View: monthly summary (spend by month + category + region).
-- ---------------------------------------------------------------
CREATE OR REPLACE VIEW v_monthly_summary AS
SELECT
    DATE_FORMAT(t.transaction_date, '%Y-%m') AS month,
    b.region,
    t.category,
    COUNT(*)                     AS transaction_count,
    ROUND(SUM(t.amount), 2)      AS total_spend
FROM transactions t
JOIN customers c ON t.customer_id = c.customer_id
JOIN branches   b ON c.branch_code = b.branch_code
WHERE t.transaction_type = 'Debit' AND t.is_outlier = 0
GROUP BY DATE_FORMAT(t.transaction_date, '%Y-%m'), b.region, t.category;

-- Use the view like any table:
SELECT * FROM v_monthly_summary WHERE month = '2024-12' ORDER BY total_spend DESC LIMIT 5;

-- ---------------------------------------------------------------
-- Q17. View: per-customer spending summary (useful as a Power BI/Excel feed).
-- ---------------------------------------------------------------
CREATE OR REPLACE VIEW v_customer_spend AS
SELECT
    c.customer_id,
    c.customer_name,
    c.age,
    c.gender,
    c.city,
    c.account_type,
    ROUND(SUM(t.amount), 2)       AS total_spend,
    ROUND(AVG(t.amount), 2)       AS avg_transaction,
    COUNT(t.transaction_id)       AS num_transactions
FROM customers c
LEFT JOIN transactions t
    ON c.customer_id = t.customer_id
   AND t.transaction_type = 'Debit'
   AND t.is_outlier = 0
GROUP BY c.customer_id, c.customer_name, c.age, c.gender, c.city, c.account_type;

SELECT * FROM v_customer_spend ORDER BY total_spend DESC LIMIT 10;

-- =====================================================================
-- End of practice queries.
-- Tip: save your favourite queries as .sql files or Views so you can
-- reuse them in Power BI (Get Data -> MySQL) or connect Excel to MySQL.
-- =====================================================================
