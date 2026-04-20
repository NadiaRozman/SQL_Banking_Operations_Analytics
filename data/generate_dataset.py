"""
=============================================================================
Retail Banking Operations — Synthetic Dataset Generator
=============================================================================
Generates 5 relational tables saved as CSVs and loaded into SQLite:
    1. customers          — demographic and account info
    2. products           — bank product catalogue
    3. transactions       — daily transaction ledger
    4. complaints         — customer service complaints
    5. sla_targets        — SLA resolution targets per complaint category

All data is synthetic and randomly generated using Faker + NumPy.
Designed to mirror realistic retail banking operations in Southeast Asia.
=============================================================================
"""

import sqlite3
import pandas as pd
import numpy as np
from faker import Faker
from datetime import datetime, timedelta
import random
import os

# ── Reproducibility ────────────────────────────────────────────────────────
SEED = 42
random.seed(SEED)
np.random.seed(SEED)
fake = Faker("en_US")          # en_US locale (Malaysian names added via STATES/manual lists)
Faker.seed(SEED)

# ── Paths ───────────────────────────────────────────────────────────────────
DATA_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH  = os.path.join(DATA_DIR, "banking.db")

# ── Constants ────────────────────────────────────────────────────────────────
N_CUSTOMERS    = 2_000
N_TRANSACTIONS = 18_000
N_COMPLAINTS   = 1_200

STATES = [
    "Selangor", "Kuala Lumpur", "Johor", "Penang", "Sabah",
    "Sarawak", "Perak", "Kedah", "Pahang", "Negeri Sembilan"
]
SEGMENTS = ["Mass", "Mass Affluent", "Affluent", "Private Banking"]
SEG_WEIGHTS = [0.55, 0.25, 0.15, 0.05]

PRODUCTS = [
    ("P001", "Basic Savings Account",       "Savings",     0),
    ("P002", "Premier Savings Account",     "Savings",     500),
    ("P003", "Fixed Deposit 3M",            "Deposit",     1_000),
    ("P004", "Fixed Deposit 12M",           "Deposit",     5_000),
    ("P005", "Personal Loan",               "Loan",        10_000),
    ("P006", "Home Financing",              "Loan",        50_000),
    ("P007", "Classic Credit Card",         "Card",        0),
    ("P008", "Platinum Credit Card",        "Card",        0),
    ("P009", "Business Current Account",    "Current",     1_000),
    ("P010", "Digital Wallet",              "Digital",     0),
]

COMPLAINT_CATS = [
    "Transaction Dispute",
    "Card Blocked / Lost",
    "Incorrect Charges",
    "Online Banking Issue",
    "Loan Statement Error",
    "Account Access",
    "Poor Service",
    "Fraud Report",
]

CHANNELS = ["Branch", "Online Banking", "Mobile App", "Call Centre", "ATM"]
TXN_TYPES = ["Purchase", "Transfer", "Bill Payment", "Withdrawal", "Refund", "Top-Up"]

START_DATE = datetime(2023, 1, 1)
END_DATE   = datetime(2024, 12, 31)
DATE_RANGE = (END_DATE - START_DATE).days


# ─────────────────────────────────────────────────────────────────────────────
# 1. PRODUCTS TABLE
# ─────────────────────────────────────────────────────────────────────────────
def make_products():
    rows = []
    for pid, name, category, min_bal in PRODUCTS:
        rows.append({
            "product_id":      pid,
            "product_name":    name,
            "product_category": category,
            "min_balance":     min_bal,
            "interest_rate":   round(random.uniform(0.5, 6.5), 2),
            "annual_fee":      random.choice([0, 0, 0, 95, 120, 200, 350]),
        })
    return pd.DataFrame(rows)


# ─────────────────────────────────────────────────────────────────────────────
# 2. CUSTOMERS TABLE
# ─────────────────────────────────────────────────────────────────────────────
def make_customers(products_df):
    rows = []
    product_ids = products_df["product_id"].tolist()

    for i in range(1, N_CUSTOMERS + 1):
        joined_days_ago = random.randint(30, 365 * 8)
        joined_date = (datetime.today() - timedelta(days=joined_days_ago)).date()
        age = random.randint(21, 72)
        segment = random.choices(SEGMENTS, weights=SEG_WEIGHTS)[0]

        # Higher segments → more products
        n_products = random.choices([1, 2, 3, 4], weights=[0.4, 0.35, 0.2, 0.05])[0]
        if segment in ("Affluent", "Private Banking"):
            n_products = min(n_products + 1, 4)

        held = random.sample(product_ids, n_products)

        rows.append({
            "customer_id":        f"C{i:05d}",
            "full_name":          fake.name(),
            "age":                age,
            "gender":             random.choice(["M", "F"]),
            "state":              random.choice(STATES),
            "customer_segment":   segment,
            "products_held":      "|".join(held),      # pipe-delimited list
            "num_products":       n_products,
            "account_open_date":  str(joined_date),
            "account_tenure_days": joined_days_ago,
            "is_active":          random.choices([1, 0], weights=[0.88, 0.12])[0],
            "monthly_income_myr": round(
                np.random.lognormal(
                    mean={"Mass": 8.2, "Mass Affluent": 8.9,
                          "Affluent": 9.5, "Private Banking": 10.5}[segment],
                    sigma=0.35
                )
            ),
        })
    return pd.DataFrame(rows)


# ─────────────────────────────────────────────────────────────────────────────
# 3. TRANSACTIONS TABLE
# ─────────────────────────────────────────────────────────────────────────────
def make_transactions(customers_df, products_df):
    rows = []
    customer_ids = customers_df["customer_id"].tolist()
    product_ids  = products_df["product_id"].tolist()

    for i in range(1, N_TRANSACTIONS + 1):
        cid = random.choice(customer_ids)
        pid = random.choice(product_ids)
        txn_date = START_DATE + timedelta(days=random.randint(0, DATE_RANGE))
        txn_type = random.choices(
            TXN_TYPES,
            weights=[0.30, 0.25, 0.20, 0.10, 0.08, 0.07]
        )[0]

        amount = round(
            np.random.lognormal(mean=5.5, sigma=1.1), 2
        )
        if txn_type == "Withdrawal":
            amount = round(random.choice([100, 200, 300, 500, 1000, 2000]), 2)

        rows.append({
            "transaction_id":   f"T{i:06d}",
            "customer_id":      cid,
            "product_id":       pid,
            "transaction_date": txn_date.strftime("%Y-%m-%d"),
            "transaction_month": txn_date.strftime("%Y-%m"),
            "transaction_type": txn_type,
            "amount_myr":       amount,
            "channel":          random.choices(
                CHANNELS, weights=[0.15, 0.30, 0.35, 0.12, 0.08]
            )[0],
            "status":           random.choices(
                ["Successful", "Failed", "Reversed"],
                weights=[0.93, 0.05, 0.02]
            )[0],
        })
    return pd.DataFrame(rows)


# ─────────────────────────────────────────────────────────────────────────────
# 4. SLA TARGETS TABLE
# ─────────────────────────────────────────────────────────────────────────────
def make_sla_targets():
    rows = []
    for cat in COMPLAINT_CATS:
        target = {
            "Fraud Report":            1,
            "Card Blocked / Lost":     2,
            "Transaction Dispute":     5,
            "Incorrect Charges":       5,
            "Account Access":          3,
            "Online Banking Issue":    3,
            "Loan Statement Error":    7,
            "Poor Service":           10,
        }[cat]
        rows.append({
            "complaint_category":    cat,
            "sla_target_days":       target,
            "priority":              "High" if target <= 3 else ("Medium" if target <= 7 else "Low"),
        })
    return pd.DataFrame(rows)


# ─────────────────────────────────────────────────────────────────────────────
# 5. COMPLAINTS TABLE
# ─────────────────────────────────────────────────────────────────────────────
def make_complaints(customers_df, products_df, sla_df):
    rows = []
    customer_ids = customers_df["customer_id"].tolist()
    product_ids  = products_df["product_id"].tolist()
    sla_map      = sla_df.set_index("complaint_category")["sla_target_days"].to_dict()

    statuses = ["Resolved", "Resolved", "Resolved", "Pending", "Escalated"]

    for i in range(1, N_COMPLAINTS + 1):
        cat          = random.choice(COMPLAINT_CATS)
        sla_target   = sla_map[cat]
        filed_date   = START_DATE + timedelta(days=random.randint(0, DATE_RANGE))

        # Resolution days — some breach SLA intentionally
        if random.random() < 0.25:          # 25% breach
            resolution_days = sla_target + random.randint(1, 10)
        else:
            resolution_days = random.randint(1, sla_target)

        resolved_date = filed_date + timedelta(days=resolution_days)
        if resolved_date > END_DATE:
            resolved_date = END_DATE

        rows.append({
            "complaint_id":        f"CMP{i:05d}",
            "customer_id":         random.choice(customer_ids),
            "product_id":          random.choice(product_ids),
            "complaint_category":  cat,
            "filed_date":          filed_date.strftime("%Y-%m-%d"),
            "resolved_date":       resolved_date.strftime("%Y-%m-%d"),
            "resolution_days":     resolution_days,
            "sla_target_days":     sla_target,
            "sla_breached":        1 if resolution_days > sla_target else 0,
            "channel":             random.choices(
                CHANNELS, weights=[0.20, 0.25, 0.30, 0.20, 0.05]
            )[0],
            "status":              random.choice(statuses),
            "csat_score":          random.choices(
                [1, 2, 3, 4, 5],
                weights=[0.05, 0.10, 0.20, 0.35, 0.30]
            )[0],
        })
    return pd.DataFrame(rows)


# ─────────────────────────────────────────────────────────────────────────────
# BUILD DATABASE
# ─────────────────────────────────────────────────────────────────────────────
def build_database():
    print("Generating tables...")
    products_df     = make_products()
    customers_df    = make_customers(products_df)
    transactions_df = make_transactions(customers_df, products_df)
    sla_df          = make_sla_targets()
    complaints_df   = make_complaints(customers_df, products_df, sla_df)

    # Save CSVs
    for name, df in [
        ("products",     products_df),
        ("customers",    customers_df),
        ("transactions", transactions_df),
        ("sla_targets",  sla_df),
        ("complaints",   complaints_df),
    ]:
        path = os.path.join(DATA_DIR, f"{name}.csv")
        df.to_csv(path, index=False)
        print(f"  ✓ {name}.csv — {len(df):,} rows")

    # Load into SQLite
    conn = sqlite3.connect(DB_PATH)
    for name, df in [
        ("products",     products_df),
        ("customers",    customers_df),
        ("transactions", transactions_df),
        ("sla_targets",  sla_df),
        ("complaints",   complaints_df),
    ]:
        df.to_sql(name, conn, if_exists="replace", index=False)

    # Add indexes for query performance
    cur = conn.cursor()
    cur.execute("CREATE INDEX IF NOT EXISTS idx_txn_customer ON transactions(customer_id)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_txn_date    ON transactions(transaction_date)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_cmp_customer ON complaints(customer_id)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_cmp_date    ON complaints(filed_date)")
    conn.commit()
    conn.close()

    print(f"\n✓ SQLite database created: {DB_PATH}")
    print(f"  Tables: products, customers, transactions, sla_targets, complaints")


if __name__ == "__main__":
    build_database()
