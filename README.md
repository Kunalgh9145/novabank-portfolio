# NovaBank — Personal Banking Transactions Analysis

A **beginner-friendly finance data-analysis portfolio project** that walks through the
full data workflow: **data cleaning → analysis → visualization** using **SQL, Excel and
Power BI**.

> Story: *NovaBank* (fictional) is a retail bank that wants to understand how its
> customers spend money so it can improve product offers and reduce transaction failures.

---

## 1. Project story & business problem

NovaBank has a new CEO who wants to know:

1. **Where do customers spend their money?** (category mix: groceries, rent, travel, ...)
2. **How does spending change month over month?** (seasonality, growth)
3. **Which customers and which branches generate the most activity?**
4. **How healthy is our payment pipeline?** (failed / pending transaction rates)

We answer these questions from a synthetic dataset of **~22,000 personal banking
transactions** across **100 customers**, **15 branches**, over **2 years**
(Jan 2023 – Dec 2024).

The project deliberately includes a **dirty "raw" dataset** so you can demonstrate the
most important analyst skill: *finding and fixing data quality problems* before doing
any analysis.

## 2. Objectives

- Practice **data cleaning** in three tools (SQL, Excel, Power Query).
- Build **aggregations and KPIs** (spend by category, monthly trends, failed rate).
- Use **window functions** (running balance, ranking, MoM growth) in SQL.
- Build an **Excel dashboard** with Pivot Tables and formulas.
- Build a **one-page Power BI report** with DAX measures and visuals.

## 3. Files in this project

```
novabank-portfolio/
├── data/
│   ├── raw_transactions.csv      # 22,462 rows - DIRTY (with intentional errors)
│   ├── cleaned_transactions.csv  # 21,915 rows - CLEANED
│   ├── customers.csv             # 100 rows  - customer master (for JOINs)
│   └── branches.csv              # 15 rows   - branch lookup (for JOINs)
├── sql/
│   ├── schema.sql                # CREATE TABLE statements
│   ├── load_data.sql             # LOAD DATA commands to import the CSVs
│   └── queries.sql               # 15+ commented practice queries
├── scripts/
│   └── generate_dataset.py       # reproducible generator (seed = 42)
└── README.md
```

## 4. Data dictionary

| Column | Meaning | Example |
|---|---|---|
| `transaction_id` | Unique transaction code | `TXN0000001` |
| `customer_id` | Unique customer code | `CUST1001` |
| `customer_name` | Customer name | `Aarav Sharma` |
| `account_type` | Savings / Current / Credit Card | `Savings` |
| `transaction_date` | Date of transaction (YYYY-MM-DD in cleaned file) | `2024-03-15` |
| `transaction_time` | Time of transaction | `14:32:10` |
| `transaction_type` | Debit / Credit / Transfer / Withdrawal / Deposit | `Debit` |
| `category` | Spending category | `Groceries`, `Salary`, `Rent` |
| `amount` | Transaction value (₹) | `1250.50` |
| `balance_after_transaction` | Account balance after the transaction | `45230.20` |
| `city` | Branch / city of the transaction | `Mumbai` |
| `payment_mode` | UPI / Card / Net Banking / Cash / Cheque | `UPI` |
| `status` | Success / Failed / Pending | `Success` |
| `Is_Outlier` | 1 if amount > ₹1,000,000 (cleaned file only) | `0` |

## 5. Raw vs Cleaned — what was wrong and how it was fixed

The **raw** file was intentionally corrupted to look like a messy real-world export:

| Problem planted in raw | ~Share | Cleaning rule applied |
|---|---|---|
| Exact duplicate rows | 2.5% | Duplicates removed (first copy kept) |
| Missing `category` | 3% | Filled with `Uncategorized` |
| Missing `payment_mode` | 2% | Filled with `Unknown` |
| Missing `amount` | 3.4% | Imputed with the **category median** (documented) |
| Mixed date formats: `YYYY-MM-DD`, `DD/MM/YYYY`, `MM-DD-YYYY`, `15-Jan-2024` | ~41% | Converted to `YYYY-MM-DD` |
| Inconsistent casing / extra whitespace (`GROCERIES`, `" Groceries "`) | many | Trimmed + standardised casing |
| Typos (`Grocries`, `Bengluru`, `Shooping`) | ~4% | Mapped to canonical spelling |
| `amount` stored as text (`₹1,234.56`) | ~6% | Parsed back to numbers |
| Negative balance on Credit Card accounts | 3.2% | Set to absolute value (sign-entry error) |
| Unrealistic amounts (`₹99,999,999`) | 20 rows | Kept but flagged `Is_Outlier = 1` |
| Account-type variants (`SAV`, `saving`, `CUR`, `CC`) | ~40% | Mapped to `Savings` / `Current` / `Credit Card` |

**Rule of thumb for any real project:** always write down your cleaning rules (like the
table above) so your work is reproducible and defensible.

## 6. SQL component

1. Run `sql/schema.sql` to create the `novabank` database and tables.
2. Run `sql/load_data.sql` to import the CSV files (adjust file paths first).
3. Work through `sql/queries.sql` — 15+ commented queries in 6 sections:

   - **Data quality checks** — missing values, duplicates, date-format mix, text amounts, outliers
   - **Cleaning in SQL** — one `INSERT ... SELECT` that transforms staging → clean table
   - **Aggregations** — monthly spend by category, per-customer balances, branch volume, failure rate
   - **Window functions** — running balance (`SUM OVER`), customer ranking (`DENSE_RANK`), MoM growth (`LAG`)
   - **Joins** — `transactions ⟕ customers ⟕ branches` (top customers, customers without transactions)
   - **Views** — `v_monthly_summary`, `v_customer_spend` for reporting

## 7. Excel component

### 7.1 Data cleaning in Excel
1. **Remove Duplicates**: select all columns → Data → Remove Duplicates.
2. **TRIM**: add a column `=TRIM(A2)` to strip spaces, paste as values.
3. **Text to Columns** (dates & amounts): select the column → Data → Text to Columns → Delimited / Fixed width.
4. **Find & Replace**: fix text amounts — find `₹` and `,`, replace with nothing, then convert the column to Number.
5. **Date fix**: use `=DATE(RIGHT(A2,4),MID(A2,4,2),LEFT(A2,2))` for `DD/MM/YYYY`, and `=DATEVALUE()` after normalising.
6. **IFERROR**: wrap risky formulas, e.g. `=IFERROR(VLOOKUP(...), "Not found")`.
7. **Data Validation**: highlight the `category` column → Data → Data Validation → allow List, so future entries are consistent.

### 7.2 Pivot Tables to build
| Pivot report | Rows | Values |
|---|---|---|
| Spend by category | `category` | Sum of `amount` |
| Monthly trend | `transaction_date` (group by Month/Year) | Sum of `amount` |
| Branch volume | `city` | Count of `transaction_id` |
| Failure rate | `status` | Count of `transaction_id` |

### 7.3 Key formulas
```excel
=SUMIFS(amount_range, category_range, "Groceries", date_range, ">=2024-01-01")
=COUNTIFS(status_range, "Failed", category_range, "Groceries")
=XLOOKUP("CUST1001", customer_id_range, customer_name_range)   ' or VLOOKUP
=IF(amount>1000000, "Outlier", "OK")
```

### 7.4 One-sheet dashboard
Lay out a dashboard sheet like this: a title, a few **KPI cards** (Total Spend, #Transactions,
Failed %) using `SUM`/`COUNTIF`, then **2–3 PivotCharts** (bar: spend by category,
line: monthly trend, bar: branch volume). Point the charts at Pivot Tables on a hidden
"data" sheet and add **slicers** for Month and City. Format with a clean colour palette.

## 8. Power BI component

### 8.1 Import
- Get Data → **Text/CSV** → `cleaned_transactions.csv`, `customers.csv`, `branches.csv`.
- In **Power Query**, reload the same cleaning steps (Remove Duplicates, Trim, change data types).
- Promote headers, set `transaction_date` to Date, `amount` / `balance_after_transaction` to Decimal.

### 8.2 Data model (star schema)
Build a star schema in the **Model** view (drag to create relationships):

```
customers (customer_id) 1 ──── * transactions (customer_id)
branches  (branch_code) 1 ──── * customers    (branch_code)

dimensions (tables)        facts (table)
```

### 8.3 DAX measures
```dax
Total Spend = SUM(transactions[amount])   // filter by transaction_type = Debit in visuals

Total Transactions = COUNTROWS(transactions)

Avg Transaction Value =
    DIVIDE([Total Spend], COUNTROWS(transactions))

Failed Rate =
    DIVIDE(CALCULATE(COUNTROWS(transactions), transactions[status] = "Failed"),
           [Total Transactions])

MoM Growth % =
    VAR Prev =
        CALCULATE([Total Spend],
                  PREVIOUSMONTH(transactions[transaction_date]))
    RETURN DIVIDE([Total Spend] - Prev, Prev)
```

### 8.4 One-page dashboard layout
```
+----------------------------------------------------------------+
|   NovaBank - Spending & Payments Dashboard            (slicers) |
|   [KPI cards: Total Spend | Avg Tx Value | Failed Rate | #Tx]  |
|   +----------------------+  +-------------------------------+  |
|   | Line: Monthly Spend  |  | Donut: Spend by Category      |  |
|   +----------------------+  +-------------------------------+  |
|   +----------------------+  +-------------------------------+  |
|   | Bar: Spend by City   |  | Table: Top 10 Customers       |  |
|   +----------------------+  +-------------------------------+  |
+----------------------------------------------------------------+
```
Visual list: **KPI cards**, **line chart** (month on X), **donut/bar** for category mix,
**city map** (turn off outliers with a filter `Is_Outlier = 0`), and a **top-customers table**.

## 9. Suggested analysis questions (for your portfolio write-up)

1. Which 3 categories drive the most spending? What share do they represent?
2. Is spending seasonal? Which months spike (festive season)?
3. Which payment mode has the highest failure rate?
4. Who are the top 5 customers by spend, and what do they have in common?
5. Are there any outliers that would distort the dashboard if not removed?

## 10. Next steps / how to extend

- Add a **`Calendar` date table** and mark it as the date table in Power BI.
- Add **forecasting** (Power BI Analytics pane → Forecast).
- Split the project into **weekly vs weekend** analysis.
- Re-build the dashboard in **Tableau** for a second tool on your CV.

---

*Data is fully synthetic and generated by `scripts/generate_dataset.py` (seed = 42).
No real customer or banking information is used.*
