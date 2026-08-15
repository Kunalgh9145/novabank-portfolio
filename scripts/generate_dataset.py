#!/usr/bin/env python3
"""
NovaBank Portfolio Project - Synthetic Data Generator
=====================================================
Generates three files for a beginner-friendly data analyst portfolio:

  1. data/raw_transactions.csv        - dirty data (with realistic errors)
  2. data/cleaned_transactions.csv    - the same data, fully cleaned
  3. data/customers.csv, data/branches.csv - lookup tables (for SQL joins / star schema)

The generator is deterministic (seeded) so the same files are produced on every run.

How the cleaning is done (documented rules):
  - Exact duplicate rows are removed (first occurrence kept).
  - Whitespace is trimmed; category / city / payment mode / status / name casing standardised.
  - Account Type variants (SAV, saving, CUR, CC, ...) are mapped to a canonical value.
  - Category and City typos are mapped to the canonical spelling.
  - Dates in mixed formats (YYYY-MM-DD, DD/MM/YYYY, MM-DD-YYYY, 15-Jan-2024) -> YYYY-MM-DD.
  - Amounts stored as text ("₹1,234.56") are parsed back to numbers.
  - Missing Category -> 'Uncategorized'; missing Payment Mode -> 'Unknown'.
  - Missing Amount -> filled with the median amount of that category (documented imputation).
  - Negative balances on Credit Card accounts are set to their absolute value
    (a sign-entry error from the raw file).
  - Unrealistic amounts (> 1,000,000) are kept but flagged in the 'Is_Outlier' column.
"""

import csv
import os
import random
from collections import defaultdict
from datetime import date, datetime, time, timedelta

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SEED = 42
START = date(2023, 1, 1)
END = date(2024, 12, 31)
N_CUSTOMERS = 100
OUTLIER_THRESHOLD = 1_000_000          # amounts above this are flagged as outliers
OUTLIER_AMOUNT = 99_999_999            # injected "fat finger" transactions
N_OUTLIER_ROWS = 20                    # extra unrealistic transactions added to both files

# Shared file locations (the script lives in scripts/, data lives in data/)
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(BASE_DIR, "data")

# ---------------------------------------------------------------------------
# Lookup data
# ---------------------------------------------------------------------------
CITIES = [
    ("Mumbai", "BR001", "West"), ("Delhi", "BR002", "North"),
    ("Bengaluru", "BR003", "South"), ("Hyderabad", "BR004", "South"),
    ("Chennai", "BR005", "South"), ("Kolkata", "BR006", "East"),
    ("Pune", "BR007", "West"), ("Ahmedabad", "BR008", "West"),
    ("Jaipur", "BR009", "North"), ("Lucknow", "BR010", "North"),
    ("Chandigarh", "BR011", "North"), ("Kochi", "BR012", "South"),
    ("Bhopal", "BR013", "Central"), ("Patna", "BR014", "East"),
    ("Indore", "BR015", "Central"),
]

FIRST_M = ["Aarav","Vihaan","Aditya","Vivaan","Arjun","Sai","Reyansh","Kabir","Ayaan",
           "Rohan","Karan","Rahul","Amit","Sanjay","Ravi","Vikram","Nikhil","Siddharth",
           "Manish","Pranav","Ishaan","Dev","Rohit","Akash","Arnav","Dhruv","Yash","Rajat","Om","Kush"]
FIRST_F = ["Aadhya","Ananya","Diya","Ishita","Meera","Saanvi","Aarohi","Anika","Navya",
           "Pari","Priya","Neha","Sneha","Kavya","Riya","Shreya","Anjali","Pooja","Divya",
           "Nisha","Tanvi","Sakshi","Ritika","Shweta","Aishwarya","Pallavi","Vandana","Swati","Sana","Gauri"]
LAST = ["Sharma","Verma","Patel","Reddy","Gupta","Iyer","Singh","Kumar","Mehta","Nair",
        "Rao","Joshi","Chopra","Agarwal","Malhotra","Bhatt","Menon","Kapoor","Desai",
        "Naik","Pillai","Khanna","Tiwari","Bose","Ghosh","Banerjee","Mishra","Dubey","Saxena","Gill"]

# category -> (transaction type, (min, max) amount, allowed payment modes)
CATEGORY_META = {
    "Groceries":        ("Debit",       (300, 3500),   ["UPI", "Card", "Cash"]),
    "Dining":           ("Debit",       (120, 2500),   ["UPI", "Card", "Cash"]),
    "Fuel & Transport": ("Debit",       (300, 2500),   ["UPI", "Card", "Cash"]),
    "Shopping":         ("Debit",       (400, 15000),  ["UPI", "Card", "Net Banking"]),
    "Utilities":        ("Debit",       (500, 4500),   ["UPI", "Net Banking", "Card"]),
    "Rent":             ("Debit",       (8000, 35000), ["Net Banking", "UPI", "Cheque"]),
    "Entertainment":    ("Debit",       (200, 3000),   ["UPI", "Card"]),
    "Travel":           ("Debit",       (5000, 45000), ["Card", "Net Banking"]),
    "Healthcare":       ("Debit",       (400, 25000),  ["Card", "UPI", "Cash"]),
    "Investment":       ("Debit",       (2000, 25000), ["Net Banking", "UPI"]),
    "Loan Payment":     ("Debit",       (5000, 30000), ["Net Banking", "Cheque"]),
    "Salary":           ("Credit",      None,          ["Net Banking"]),
    "Refund":           ("Credit",      (200, 3000),   ["UPI", "Net Banking"]),
    "Personal Transfer":("Transfer",    (500, 20000),  ["UPI", "Net Banking"]),
    "Cash Withdrawal":  ("Withdrawal",  (500, 10000),  ["Cash"]),
    "Cash Deposit":     ("Deposit",     (500, 15000),  ["Cash"]),
}

HOUR_WEIGHTS = [1,1,1,1,1,2,3,4,5,6,7,7,7,6,5,5,6,7,8,8,7,5,3,2]

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def rand_date():
    span = (END - START).days
    return START + timedelta(days=random.randint(0, span))

def rand_time():
    hour = random.choices(range(24), weights=HOUR_WEIGHTS, k=1)[0]
    return time(hour, random.randint(0, 59), random.randint(0, 59)).strftime("%H:%M:%S")

def last_day(y, m):
    if m == 12:
        return date(y, 12, 31).day
    return (date(y, m + 1, 1) - timedelta(days=1)).day

def day_in(y, m, d):
    return date(y, m, min(d, last_day(y, m)))

# ---------------------------------------------------------------------------
# 1) Generate customers
# ---------------------------------------------------------------------------
def make_customers():
    customers = []
    for i in range(N_CUSTOMERS):
        gender = random.choice(["M", "F"])
        name = f"{random.choice(FIRST_M if gender == 'M' else FIRST_F)} {random.choice(LAST)}"
        acct_type = random.choices(["Savings", "Current", "Credit Card"], weights=[60, 25, 15])[0]
        city, bcode, region = random.choice(CITIES)

        if acct_type == "Savings":
            salary, opening, floor = random.randint(30000, 80000), random.randint(8000, 150000), 500
        elif acct_type == "Current":
            salary, opening, floor = random.randint(50000, 200000), random.randint(30000, 600000), -10000
        else:
            salary, opening, floor = random.randint(40000, 120000), random.randint(5000, 30000), 0

        customers.append({
            "customer_id": f"CUST{i + 1001}",
            "customer_name": name,
            "age": random.randint(21, 70),
            "gender": gender,
            "city": city,
            "branch_code": bcode,
            "account_type": acct_type,
            "opening_balance": opening,
            "monthly_salary": salary,
            "rent": random.randint(8000, 35000),
            "floor": floor,
            "balance": opening,
        })
    return customers

# ---------------------------------------------------------------------------
# 2) Generate one month of transactions for a customer (category + amount only)
# ---------------------------------------------------------------------------
def month_txns(cust, y, m):
    """Returns a list of (ttype, category, amount, direction) for the month."""
    out = []

    def add(cat, amt, direction=None):
        ttype, rng, _ = CATEGORY_META[cat]
        if amt is None:
            amt = random.uniform(*rng)
        out.append((ttype, cat, round(amt, 2), direction))

    add("Salary", cust["monthly_salary"], direction="in")                      # salary on day 1-3
    add("Rent", cust["rent"], direction="out")                                 # rent on day 1-7
    if random.random() < 0.90: add("Utilities", None, direction="out")
    add("Groceries", random.uniform(300, 3500), direction="out")
    if random.random() < 0.55: add("Groceries", None, direction="out")
    if random.random() < 0.60: add("Dining", None, direction="out")
    if random.random() < 0.60: add("Fuel & Transport", None, direction="out")
    if random.random() < 0.45: add("Shopping", None, direction="out")
    if random.random() < 0.45: add("Entertainment", None, direction="out")
    if random.random() < 0.25: add("Healthcare", None, direction="out")
    if random.random() < 0.75: add("Investment", None, direction="out")
    if random.random() < (0.60 if cust["account_type"] != "Savings" else 0.10):
        add("Loan Payment", None, direction="out")
    if m in (1, 4, 7, 10) and random.random() < 0.35:
        add("Travel", None, direction="out")
    if random.random() < 0.50:
        add("Personal Transfer", None, direction=random.choice(["in", "out"]))
    if random.random() < 0.30: add("Cash Withdrawal", None, direction="out")
    if random.random() < 0.25: add("Cash Deposit", None, direction="in")
    if random.random() < 0.08: add("Refund", None, direction="in")
    return out

# ---------------------------------------------------------------------------
# 3) Build full clean transaction records (with running balance)
# ---------------------------------------------------------------------------
def build_clean_transactions(customers):
    """Returns a list of clean dicts with correct running balance."""
    all_txns = []  # (customer, date, time, ttype, category, amount, direction, payment_mode)
    txn_id = 1

    for cust in customers:
        for y in range(START.year, END.year + 1):
            for m in range(1, 13):
                items = month_txns(cust, y, m)
                for (ttype, cat, amt, direction) in items:
                    d = day_in(y, m, random.randint(1, last_day(y, m)))
                    if cat == "Salary":
                        d = day_in(y, m, random.randint(1, 3))
                    elif cat == "Rent":
                        d = day_in(y, m, random.randint(1, 7))
                    t = rand_time()
                    pm = random.choice(CATEGORY_META[cat][2])
                    all_txns.append((cust, d, t, ttype, cat, amt, direction, pm))

    # sort per customer by (date, time) so balances build correctly
    all_txns.sort(key=lambda r: (r[0]["customer_id"], r[1], r[2]))

    records = []
    for (cust, d, t, ttype, cat, amt, direction, pm) in all_txns:
        # default random status (success / failed / pending)
        roll = random.random()
        status = "Failed" if roll < 0.02 else ("Pending" if roll < 0.03 else "Success")

        # apply balance change only for successful transactions
        if status == "Success":
            delta = amt if direction == "in" else -amt
            if cust["balance"] + delta < cust["floor"]:
                status = "Failed"                       # insufficient balance
            else:
                cust["balance"] += delta

        records.append({
            "transaction_id": f"TXN{txn_id:07d}",
            "customer_id": cust["customer_id"],
            "customer_name": cust["customer_name"],
            "account_type": cust["account_type"],
            "transaction_date": d,
            "transaction_time": t,
            "transaction_type": ttype,
            "category": cat,
            "amount": amt,
            "balance_after_transaction": round(cust["balance"], 2),
            "city": cust["city"],
            "payment_mode": pm,
            "status": status,
        })
        txn_id += 1
    return records, txn_id

# ---------------------------------------------------------------------------
# 4) Inject synthetic outliers (fat-finger entries) as extra records
# ---------------------------------------------------------------------------
def add_outliers(records, next_id):
    for _ in range(N_OUTLIER_ROWS):
        cust = random.choice(records)
        rec = {
            "transaction_id": f"TXN{next_id:07d}",
            "customer_id": cust["customer_id"],
            "customer_name": cust["customer_name"],
            "account_type": cust["account_type"],
            "transaction_date": rand_date(),
            "transaction_time": rand_time(),
            "transaction_type": "Debit",
            "category": random.choice(["Shopping", "Travel", "Investment"]),
            "amount": float(OUTLIER_AMOUNT),
            "balance_after_transaction": round(random.uniform(50000, 500000), 2),
            "city": cust["city"],
            "payment_mode": random.choice(["Card", "Net Banking"]),
            "status": "Success",
        }
        records.append(rec)
        next_id += 1
    return records

# ---------------------------------------------------------------------------
# 5) Dirty the records -> raw_transactions.csv
# ---------------------------------------------------------------------------
CATEGORY_TYPOS = {
    "Groceries": ["Grocries", "Groceires", "Grocery"],
    "Entertainment": ["Entertainmnt", "Entertainment "],
    "Healthcare": ["Healtcare", "Healthcare "],
    "Shopping": ["Shooping"],
    "Utilities": ["Utilitiies"],
    "Travel": ["Travl"],
    "Fuel & Transport": ["Fuel & Transport ", "fuel & transport"],
    "Loan Payment": ["Loanpay"],
}
CITY_TYPOS = {
    "Bengaluru": ["Bengluru", "Bangalore"],
    "Chennai": ["Chenai"],
    "Hyderabad": ["Hydrabad"],
    "Jaipur": ["Jaipr"],
    "Kolkata": ["Kolkata "],
    "Pune": ["Pune "],
}
ACCOUNT_VARIANTS = {
    "Savings": ["Savings", "SAV", "saving", "savings", "Savings "],
    "Current": ["Current", "CUR", "current", "Current "],
    "Credit Card": ["Credit Card", "CC", "credit", "Credit card", "CreditCard"],
}

def fmt_raw_date(d):
    roll = random.random()
    if roll < 0.30:
        return f"{d.day:02d}/{d.month:02d}/{d.year}"
    if roll < 0.36:
        return f"{d.month:02d}-{d.day:02d}-{d.year}"
    if roll < 0.41:
        return d.strftime("%d-%b-%Y")
    return d.strftime("%Y-%m-%d")

def fmt_raw_amount(amt):
    roll = random.random()
    if roll < 0.035:
        return ""                                   # missing amount
    if roll < 0.06:
        return "₹" + f"{amt:,.2f}"                  # stored as text with symbol
    if roll < 0.09:
        return f"{amt:,.2f}"                        # stored as text with commas
    return f"{amt:.2f}"

def distort_text(value):
    """Apply random casing + whitespace noise to a text field."""
    roll = random.random()
    if roll < 0.15:
        return value.lower()
    if roll < 0.30:
        return value.upper()
    if roll < 0.38:
        return f" {value} "
    if roll < 0.42:
        return f"{value}  "
    return value

def make_raw_rows(clean_records):
    rows = []
    for r in clean_records:
        # account type variants
        at = random.choice(ACCOUNT_VARIANTS[r["account_type"]])

        # category with typo / casing / whitespace / missing
        cat = r["category"]
        if cat in CATEGORY_TYPOS and random.random() < 0.04:
            cat = random.choice(CATEGORY_TYPOS[cat])
        elif random.random() < 0.25:
            cat = distort_text(cat)
        if random.random() < 0.03:
            cat = ""                                # missing category

        # city with typo / casing / whitespace
        city = r["city"]
        if city in CITY_TYPOS and random.random() < 0.05:
            city = random.choice(CITY_TYPOS[city])
        else:
            city = distort_text(city)

        # payment mode missing / noisy
        pm = r["payment_mode"]
        if random.random() < 0.02:
            pm = ""
        else:
            pm = distort_text(pm)

        # status noisy
        status = distort_text(r["status"])

        # name noisy
        name = r["customer_name"]
        if random.random() < 0.06:
            name = random.choice([name.lower(), name.upper(), f" {name} ", name.replace(" ", "  ")])

        # balance: negative sign-entry errors on Credit Card accounts
        balance = r["balance_after_transaction"]
        if r["account_type"] == "Credit Card" and random.random() < 0.25:
            balance = -balance

        rows.append({
            "transaction_id": r["transaction_id"],
            "customer_id": r["customer_id"],
            "customer_name": name,
            "account_type": at,
            "transaction_date": fmt_raw_date(r["transaction_date"]),
            "transaction_time": r["transaction_time"],
            "transaction_type": r["transaction_type"],
            "category": cat,
            "amount": fmt_raw_amount(r["amount"]),
            "balance_after_transaction": f"{balance:.2f}",
            "city": city,
            "payment_mode": pm,
            "status": status,
        })

    # inject duplicate rows (~2.5% of the file)
    dup_count = int(len(rows) * 0.025)
    for _ in range(dup_count):
        rows.append(dict(random.choice(rows)))

    # slight shuffle so duplicates are not all at the end
    random.shuffle(rows)
    return rows

# ---------------------------------------------------------------------------
# 6) Clean the raw rows -> cleaned_transactions.csv
# ---------------------------------------------------------------------------
ACCOUNT_CLEAN = {
    "savings": "Savings", "sav": "Savings", "saving": "Savings",
    "current": "Current", "cur": "Current", "curr": "Current",
    "credit card": "Credit Card", "cc": "Credit Card", "credit": "Credit Card", "creditcard": "Credit Card",
}
CATEGORY_CLEAN = {
    "groceries": "Groceries", "grocery": "Groceries", "grocries": "Groceries", "groceires": "Groceries",
    "dining": "Dining", "diningg": "Dining",
    "fuel & transport": "Fuel & Transport", "fuel and transport": "Fuel & Transport",
    "fuel": "Fuel & Transport", "transport": "Fuel & Transport",
    "shopping": "Shopping", "shooping": "Shopping",
    "utilities": "Utilities", "utilitiies": "Utilities", "utility": "Utilities",
    "rent": "Rent",
    "entertainment": "Entertainment", "entertainmnt": "Entertainment",
    "travel": "Travel", "travl": "Travel",
    "healthcare": "Healthcare", "healtcare": "Healthcare",
    "investment": "Investment",
    "loan payment": "Loan Payment", "loanpay": "Loan Payment", "loan": "Loan Payment",
    "salary": "Salary",
    "refund": "Refund",
    "personal transfer": "Personal Transfer", "transfer": "Personal Transfer", "trnsfer": "Personal Transfer",
    "cash withdrawal": "Cash Withdrawal", "withdrawal": "Cash Withdrawal",
    "cash deposit": "Cash Deposit", "deposit": "Cash Deposit",
    "": "Uncategorized",
}
CITY_CLEAN = {
    "mumbai": "Mumbai", "delhi": "Delhi", "bengaluru": "Bengaluru", "bangalore": "Bengaluru",
    "bengluru": "Bengaluru", "hyderabad": "Hyderabad", "hydrabad": "Hyderabad",
    "chennai": "Chennai", "chenai": "Chennai", "kolkata": "Kolkata", "pune": "Pune",
    "ahmedabad": "Ahmedabad", "jaipur": "Jaipur", "jaipr": "Jaipur", "lucknow": "Lucknow",
    "chandigarh": "Chandigarh", "kochi": "Kochi", "cochin": "Kochi", "bhopal": "Bhopal",
    "patna": "Patna", "indore": "Indore",
}
PM_CLEAN = {
    "upi": "UPI", "card": "Card", "net banking": "Net Banking", "netbanking": "Net Banking",
    "internet banking": "Net Banking", "cash": "Cash", "cheque": "Cheque",
    "": "Unknown",
}
STATUS_CLEAN = {
    "success": "Success", "failed": "Failed", "pending": "Pending",
    "": "Unknown",
}

def parse_raw_amount(value):
    if value.strip() == "":
        return None
    cleaned = value.replace("₹", "").replace(",", "").strip()
    return float(cleaned)

def parse_raw_date(value):
    value = value.strip()
    for fmt in ("%Y-%m-%d", "%d/%m/%Y", "%m-%d-%Y", "%d-%b-%Y"):
        try:
            return datetime.strptime(value, fmt).date()
        except ValueError:
            continue
    return None

def clean_rows(raw_rows):
    # first pass: parse everything so we can compute category medians for imputation
    parsed = []
    for r in raw_rows:
        amount = parse_raw_amount(r["amount"])
        cat_raw = CATEGORY_CLEAN.get(r["category"].strip().lower(), r["category"].strip().title())
        parsed.append({
            "row": r,
            "amount": amount,
            "category_clean": cat_raw,
        })

    # category medians (for missing-amount imputation)
    medians = {}
    by_cat = defaultdict(list)
    for p in parsed:
        if p["amount"] is not None and p["category_clean"]:
            by_cat[p["category_clean"]].append(p["amount"])
    for cat, vals in by_cat.items():
        vals.sort()
        medians[cat] = vals[len(vals) // 2]
    all_amounts = sorted(a["amount"] for a in parsed if a["amount"] is not None)
    global_median = all_amounts[len(all_amounts) // 2]

    # second pass: build cleaned records
    cleaned = []
    seen = set()
    stats = {"duplicates_removed": 0, "missing_amount_imputed": 0,
             "negative_balances_fixed": 0, "outliers_flagged": 0}

    for p in parsed:
        r = p["row"]
        key = tuple(sorted((k, str(v)) for k, v in r.items()))
        if key in seen:                      # remove exact duplicates
            stats["duplicates_removed"] += 1
            continue
        seen.add(key)

        d = parse_raw_date(r["transaction_date"])

        amount = p["amount"]
        if amount is None:                   # impute missing amounts
            amount = medians.get(p["category_clean"], global_median)
            stats["missing_amount_imputed"] += 1

        balance = float(r["balance_after_transaction"])
        if r["account_type"].strip().lower() in ("credit", "cc", "creditcard", "credit card") and balance < 0:
            balance = abs(balance)           # fix negative balance on credit cards
            stats["negative_balances_fixed"] += 1

        is_outlier = 1 if amount > OUTLIER_THRESHOLD else 0
        if is_outlier:
            stats["outliers_flagged"] += 1

        cleaned.append({
            "transaction_id": r["transaction_id"].strip(),
            "customer_id": r["customer_id"].strip(),
            "customer_name": " ".join(r["customer_name"].strip().title().split()),
            "account_type": ACCOUNT_CLEAN.get(r["account_type"].strip().lower(), r["account_type"].strip().title()),
            "transaction_date": d.strftime("%Y-%m-%d"),
            "transaction_time": r["transaction_time"].strip(),
            "transaction_type": r["transaction_type"].strip().title(),
            "category": p["category_clean"],
            "amount": f"{amount:.2f}",
            "balance_after_transaction": f"{balance:.2f}",
            "city": CITY_CLEAN.get(r["city"].strip().lower(), r["city"].strip().title()),
            "payment_mode": PM_CLEAN.get(r["payment_mode"].strip().lower(), r["payment_mode"].strip().title()),
            "status": STATUS_CLEAN.get(r["status"].strip().lower(), r["status"].strip().title()),
            "Is_Outlier": is_outlier,
        })

    return cleaned, stats

# ---------------------------------------------------------------------------
# 7) Write outputs
# ---------------------------------------------------------------------------
COLUMNS = ["transaction_id", "customer_id", "customer_name", "account_type",
           "transaction_date", "transaction_time", "transaction_type", "category",
           "amount", "balance_after_transaction", "city", "payment_mode", "status"]

def write_csv(filename, fieldnames, rows):
    path = os.path.join(DATA_DIR, filename)
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    print(f"wrote {len(rows):,} rows -> {path}")

def main():
    random.seed(SEED)
    customers = make_customers()
    clean_records, next_id = build_clean_transactions(customers)
    clean_records = add_outliers(clean_records, next_id)

    # customers.csv / branches.csv (clean lookup tables for joins / star schema)
    cust_rows = [{
        "customer_id": c["customer_id"], "customer_name": c["customer_name"],
        "age": c["age"], "gender": c["gender"], "city": c["city"],
        "branch_code": c["branch_code"], "account_type": c["account_type"],
        "opening_balance": c["opening_balance"],
    } for c in customers]
    branch_rows = [{
        "branch_code": bc, "branch_name": f"NovaBank {city} Branch",
        "city": city, "region": region,
    } for (city, bc, region) in CITIES]

    write_csv("customers.csv",
              ["customer_id", "customer_name", "age", "gender", "city", "branch_code", "account_type", "opening_balance"],
              cust_rows)
    write_csv("branches.csv",
              ["branch_code", "branch_name", "city", "region"],
              branch_rows)

    # raw (dirty) file
    raw_rows = make_raw_rows(clean_records)
    write_csv("raw_transactions.csv", COLUMNS, raw_rows)

    # cleaned file
    cleaned_rows, stats = clean_rows(raw_rows)
    cleaned_cols = COLUMNS + ["Is_Outlier"]
    write_csv("cleaned_transactions.csv", cleaned_cols, cleaned_rows)

    # summary
    print("\n--- Cleaning summary ---")
    for k, v in stats.items():
        print(f"{k}: {v:,}")

if __name__ == "__main__":
    main()
