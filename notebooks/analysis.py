"""
=============================================================================
Retail Banking Operations — SQL Analysis Notebook
=============================================================================
This script executes all SQL query files against banking.db and produces
publication-quality charts saved to the assets/ folder.

Run this file to reproduce the full analysis end-to-end.
=============================================================================
"""

import sqlite3
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import seaborn as sns
import os
import warnings
warnings.filterwarnings("ignore")

# ── Paths ────────────────────────────────────────────────────────────────────
BASE_DIR   = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB_PATH    = os.path.join(BASE_DIR, "data", "banking.db")
SQL_DIR    = os.path.join(BASE_DIR, "sql_queries")
ASSETS_DIR = os.path.join(BASE_DIR, "assets")
os.makedirs(ASSETS_DIR, exist_ok=True)

# ── Style ────────────────────────────────────────────────────────────────────
plt.rcParams.update({
    "font.family":      "DejaVu Sans",
    "axes.spines.top":  False,
    "axes.spines.right":False,
    "axes.grid":        True,
    "grid.alpha":       0.3,
    "figure.dpi":       150,
})

PALETTE = ["#1D3557", "#457B9D", "#A8DADC", "#E63946", "#F4A261", "#2A9D8F", "#264653"]

conn = sqlite3.connect(DB_PATH)

def q(sql: str) -> pd.DataFrame:
    return pd.read_sql_query(sql, conn)

print("=" * 65)
print("  Retail Banking SQL Analysis — Running All Queries")
print("=" * 65)


# =============================================================================
# SECTION 1 — Customer Segmentation
# =============================================================================
print("\n[1] Customer Segmentation & Portfolio Analysis")

seg = q("""
    SELECT customer_segment,
           COUNT(*) AS total_customers,
           ROUND(AVG(monthly_income_myr), 0) AS avg_income_myr,
           ROUND(AVG(num_products), 2) AS avg_products,
           ROUND(SUM(CASE WHEN is_active=1 THEN 1.0 ELSE 0 END)/COUNT(*)*100,1) AS active_pct
    FROM customers
    GROUP BY customer_segment
    ORDER BY avg_income_myr DESC
""")
print(seg.to_string(index=False))

fig, axes = plt.subplots(1, 3, figsize=(15, 5))
fig.suptitle("Customer Segmentation Overview", fontsize=14, fontweight="bold", y=1.02)

# Chart 1a — Customer count by segment
axes[0].barh(seg["customer_segment"], seg["total_customers"], color=PALETTE[:4])
axes[0].set_title("Customers per Segment")
axes[0].set_xlabel("Number of Customers")
for i, v in enumerate(seg["total_customers"]):
    axes[0].text(v + 5, i, str(v), va="center", fontsize=9)

# Chart 1b — Avg income by segment
axes[1].barh(seg["customer_segment"], seg["avg_income_myr"], color=PALETTE[:4])
axes[1].set_title("Avg Monthly Income (MYR)")
axes[1].set_xlabel("MYR")
for i, v in enumerate(seg["avg_income_myr"]):
    axes[1].text(v + 100, i, f"MYR {v:,.0f}", va="center", fontsize=9)

# Chart 1c — Avg products held
axes[2].barh(seg["customer_segment"], seg["avg_products"], color=PALETTE[:4])
axes[2].set_title("Avg Products Held per Customer")
axes[2].set_xlabel("Number of Products")
for i, v in enumerate(seg["avg_products"]):
    axes[2].text(v + 0.01, i, f"{v:.2f}", va="center", fontsize=9)

plt.tight_layout()
plt.savefig(os.path.join(ASSETS_DIR, "01_customer_segmentation.png"), bbox_inches="tight")
plt.close()
print("  ✓ Chart saved: 01_customer_segmentation.png")


# =============================================================================
# SECTION 2 — Transaction Analysis
# =============================================================================
print("\n[2] Transaction Behaviour Analysis")

monthly = q("""
    SELECT transaction_month,
           COUNT(*) AS total_transactions,
           ROUND(SUM(amount_myr)/1000, 1) AS total_value_000,
           ROUND(SUM(CASE WHEN status='Failed' THEN 1.0 ELSE 0 END)/COUNT(*)*100,2) AS failure_pct
    FROM transactions
    GROUP BY transaction_month
    ORDER BY transaction_month
""")

channel = q("""
    SELECT channel,
           COUNT(*) AS total_transactions,
           ROUND(SUM(CASE WHEN status='Failed' THEN 1.0 ELSE 0 END)/COUNT(*)*100,2) AS failure_pct
    FROM transactions GROUP BY channel ORDER BY total_transactions DESC
""")

fig, axes = plt.subplots(2, 2, figsize=(15, 10))
fig.suptitle("Transaction Behaviour Analysis", fontsize=14, fontweight="bold")

# Chart 2a — Monthly transaction volume
ax = axes[0, 0]
ax.bar(monthly["transaction_month"], monthly["total_transactions"], color=PALETTE[1], width=0.6)
ax.set_title("Monthly Transaction Volume")
ax.set_ylabel("Number of Transactions")
ax.set_xlabel("Month")
ax.tick_params(axis="x", rotation=45)

# Chart 2b — Monthly transaction value
ax = axes[0, 1]
ax.plot(monthly["transaction_month"], monthly["total_value_000"],
        marker="o", color=PALETTE[0], linewidth=2)
ax.fill_between(monthly["transaction_month"], monthly["total_value_000"],
                alpha=0.15, color=PALETTE[0])
ax.set_title("Monthly Transaction Value (MYR '000s)")
ax.set_ylabel("Total Value (MYR '000s)")
ax.set_xlabel("Month")
ax.tick_params(axis="x", rotation=45)

# Chart 2c — Failure rate over time
ax = axes[1, 0]
ax.plot(monthly["transaction_month"], monthly["failure_pct"],
        marker="o", color=PALETTE[3], linewidth=2)
ax.axhline(y=monthly["failure_pct"].mean(), color="gray",
           linestyle="--", alpha=0.7, label=f"Avg: {monthly['failure_pct'].mean():.1f}%")
ax.set_title("Monthly Transaction Failure Rate (%)")
ax.set_ylabel("Failure Rate (%)")
ax.set_xlabel("Month")
ax.tick_params(axis="x", rotation=45)
ax.legend()

# Chart 2d — Channel distribution
ax = axes[1, 1]
ax.barh(channel["channel"], channel["total_transactions"], color=PALETTE[:5])
ax.set_title("Transaction Volume by Channel")
ax.set_xlabel("Number of Transactions")
for i, v in enumerate(channel["total_transactions"]):
    ax.text(v + 20, i, str(v), va="center", fontsize=9)

plt.tight_layout()
plt.savefig(os.path.join(ASSETS_DIR, "02_transaction_analysis.png"), bbox_inches="tight")
plt.close()
print("  ✓ Chart saved: 02_transaction_analysis.png")


# =============================================================================
# SECTION 3 — Complaints & SLA
# =============================================================================
print("\n[3] Complaints & SLA Performance")

complaints = q("""
    SELECT c.complaint_category, st.priority,
           COUNT(*) AS total,
           ROUND(SUM(c.sla_breached)*100.0/COUNT(*),1) AS breach_pct,
           ROUND(AVG(c.csat_score),2) AS avg_csat
    FROM complaints c
    JOIN sla_targets st ON c.complaint_category = st.complaint_category
    GROUP BY c.complaint_category, st.priority
    ORDER BY breach_pct DESC
""")

channel_cmp = q("""
    SELECT channel,
           COUNT(*) AS complaints,
           ROUND(SUM(sla_breached)*100.0/COUNT(*),1) AS breach_pct,
           ROUND(AVG(csat_score),2) AS avg_csat
    FROM complaints GROUP BY channel ORDER BY breach_pct DESC
""")

fig, axes = plt.subplots(1, 3, figsize=(18, 6))
fig.suptitle("Complaints & SLA Performance", fontsize=14, fontweight="bold")

# Chart 3a — SLA breach rate by category
colors_breach = [PALETTE[3] if b > 30 else PALETTE[1]
                 for b in complaints["breach_pct"]]
bars = axes[0].barh(complaints["complaint_category"], complaints["breach_pct"],
                     color=colors_breach)
axes[0].axvline(x=25, color="gray", linestyle="--", alpha=0.6, label="25% threshold")
axes[0].set_title("SLA Breach Rate by Category (%)")
axes[0].set_xlabel("Breach Rate (%)")
axes[0].legend(fontsize=8)
for i, v in enumerate(complaints["breach_pct"]):
    axes[0].text(v + 0.3, i, f"{v}%", va="center", fontsize=9)

# Chart 3b — Avg CSAT by category
axes[1].barh(complaints["complaint_category"], complaints["avg_csat"], color=PALETTE[2])
axes[1].axvline(x=3.5, color="gray", linestyle="--", alpha=0.6, label="Acceptable (3.5)")
axes[1].set_title("Avg CSAT Score by Category")
axes[1].set_xlabel("CSAT Score (1–5)")
axes[1].set_xlim(0, 5.5)
axes[1].legend(fontsize=8)
for i, v in enumerate(complaints["avg_csat"]):
    axes[1].text(v + 0.05, i, f"{v:.2f}", va="center", fontsize=9)

# Chart 3c — Channel breach rate
axes[2].bar(channel_cmp["channel"], channel_cmp["breach_pct"], color=PALETTE[:5])
axes[2].set_title("SLA Breach Rate by Channel (%)")
axes[2].set_ylabel("Breach Rate (%)")
axes[2].tick_params(axis="x", rotation=20)
for i, v in enumerate(channel_cmp["breach_pct"]):
    axes[2].text(i, v + 0.3, f"{v}%", ha="center", fontsize=9)

plt.tight_layout()
plt.savefig(os.path.join(ASSETS_DIR, "03_complaints_sla.png"), bbox_inches="tight")
plt.close()
print("  ✓ Chart saved: 03_complaints_sla.png")


# =============================================================================
# SECTION 4 — Cohort & Retention
# =============================================================================
print("\n[4] Cohort Analysis & Retention")

cohort = q("""
    WITH cohort_base AS (
        SELECT customer_id, is_active, num_products,
               CASE
                   WHEN account_tenure_days > 365*5 THEN '5+ Years'
                   WHEN account_tenure_days > 365*3 THEN '3–5 Years'
                   WHEN account_tenure_days > 365*1 THEN '1–3 Years'
                   ELSE '< 1 Year'
               END AS tenure_cohort
        FROM customers
    )
    SELECT tenure_cohort,
           COUNT(*) AS customers,
           ROUND(SUM(CASE WHEN is_active=1 THEN 1.0 ELSE 0 END)/COUNT(*)*100,1) AS retention_pct,
           ROUND(AVG(num_products),2) AS avg_products
    FROM cohort_base
    GROUP BY tenure_cohort
    ORDER BY CASE tenure_cohort
        WHEN '< 1 Year' THEN 1 WHEN '1–3 Years' THEN 2
        WHEN '3–5 Years' THEN 3 ELSE 4 END
""")

quintile = q("""
    WITH spend AS (
        SELECT customer_id, SUM(amount_myr) AS total_spend FROM transactions GROUP BY customer_id
    ),
    ranked AS (
        SELECT customer_id, total_spend, NTILE(5) OVER (ORDER BY total_spend DESC) AS q
        FROM spend
    )
    SELECT q,
           CASE q WHEN 1 THEN 'Top 20%' WHEN 2 THEN 'Next 20%'
                  WHEN 3 THEN 'Middle 20%' WHEN 4 THEN 'Lower 20%' ELSE 'Bottom 20%' END AS label,
           COUNT(*) AS customers,
           ROUND(SUM(total_spend),2) AS total_spend,
           ROUND(SUM(total_spend)*100.0/SUM(SUM(total_spend)) OVER(),1) AS pct_spend
    FROM ranked GROUP BY q ORDER BY q
""")

fig, axes = plt.subplots(1, 3, figsize=(18, 6))
fig.suptitle("Cohort Analysis & Revenue Concentration", fontsize=14, fontweight="bold")

axes[0].bar(cohort["tenure_cohort"], cohort["retention_pct"], color=PALETTE[:4])
axes[0].set_title("Retention Rate by Tenure Cohort (%)")
axes[0].set_ylabel("Retention Rate (%)")
axes[0].set_ylim(0, 110)
for i, v in enumerate(cohort["retention_pct"]):
    axes[0].text(i, v + 1, f"{v}%", ha="center", fontsize=10, fontweight="bold")

axes[1].bar(cohort["tenure_cohort"], cohort["avg_products"], color=PALETTE[2])
axes[1].set_title("Avg Products Held by Tenure Cohort")
axes[1].set_ylabel("Avg Products")
for i, v in enumerate(cohort["avg_products"]):
    axes[1].text(i, v + 0.02, f"{v:.2f}", ha="center", fontsize=10)

wedges, texts, autotexts = axes[2].pie(
    quintile["pct_spend"], labels=quintile["label"],
    autopct="%1.1f%%", colors=PALETTE,
    startangle=140
)
axes[2].set_title("Revenue Share by Customer Spend Quintile\n(Pareto Analysis)")

plt.tight_layout()
plt.savefig(os.path.join(ASSETS_DIR, "04_cohort_retention.png"), bbox_inches="tight")
plt.close()
print("  ✓ Chart saved: 04_cohort_retention.png")


# =============================================================================
# SECTION 5 — Executive Scorecard
# =============================================================================
print("\n[5] Executive Segment Scorecard")

scorecard = q("""
WITH
seg_cust AS (
    SELECT customer_segment,
           COUNT(*) AS total_customers,
           ROUND(SUM(CASE WHEN is_active=1 THEN 1.0 ELSE 0 END)/COUNT(*)*100,1) AS retention_pct,
           ROUND(AVG(num_products),2) AS avg_products
    FROM customers GROUP BY customer_segment
),
seg_txn AS (
    SELECT c.customer_segment,
           COUNT(t.transaction_id) AS txn_count,
           ROUND(SUM(t.amount_myr),2) AS txn_value,
           ROUND(SUM(CASE WHEN t.status='Failed' THEN 1.0 ELSE 0 END)/COUNT(*)*100,2) AS fail_pct,
           COUNT(DISTINCT t.customer_id) AS txn_customers
    FROM transactions t JOIN customers c ON t.customer_id=c.customer_id
    GROUP BY c.customer_segment
),
seg_cmp AS (
    SELECT c.customer_segment,
           COUNT(cmp.complaint_id) AS complaints,
           ROUND(SUM(cmp.sla_breached)*100.0/COUNT(*),1) AS breach_pct,
           ROUND(AVG(cmp.csat_score),2) AS avg_csat
    FROM complaints cmp JOIN customers c ON cmp.customer_id=c.customer_id
    GROUP BY c.customer_segment
)
SELECT sc.customer_segment,
       sc.total_customers,
       sc.retention_pct,
       sc.avg_products,
       ROUND(st.txn_count*1.0/sc.total_customers,1) AS txns_per_customer,
       st.fail_pct AS txn_failure_pct,
       scp.breach_pct AS sla_breach_pct,
       scp.avg_csat
FROM seg_cust sc
LEFT JOIN seg_txn st ON sc.customer_segment=st.customer_segment
LEFT JOIN seg_cmp scp ON sc.customer_segment=scp.customer_segment
ORDER BY sc.total_customers DESC
""")

print(scorecard.to_string(index=False))

fig, axes = plt.subplots(2, 2, figsize=(14, 10))
fig.suptitle("Executive Operations Scorecard — By Customer Segment",
             fontsize=14, fontweight="bold")

metrics = [
    ("retention_pct",    "Retention Rate (%)",         axes[0, 0]),
    ("txns_per_customer","Transactions per Customer",   axes[0, 1]),
    ("sla_breach_pct",   "SLA Breach Rate (%)",        axes[1, 0]),
    ("avg_csat",         "Avg CSAT Score (1–5)",       axes[1, 1]),
]
for col, title, ax in metrics:
    bar_colors = [PALETTE[3] if col in ("sla_breach_pct", "txn_failure_pct")
                  else PALETTE[0]] * len(scorecard)
    ax.bar(scorecard["customer_segment"], scorecard[col], color=PALETTE[:4])
    ax.set_title(title)
    ax.tick_params(axis="x", rotation=15)
    for i, v in enumerate(scorecard[col]):
        ax.text(i, v * 1.01, f"{v:.1f}", ha="center", fontsize=9, fontweight="bold")

plt.tight_layout()
plt.savefig(os.path.join(ASSETS_DIR, "05_executive_scorecard.png"), bbox_inches="tight")
plt.close()
print("  ✓ Chart saved: 05_executive_scorecard.png")


conn.close()
print("\n" + "=" * 65)
print("  Analysis complete. All charts saved to assets/")
print("=" * 65)
