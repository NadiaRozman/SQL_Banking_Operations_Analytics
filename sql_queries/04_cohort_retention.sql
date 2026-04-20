-- =============================================================================
-- QUERY FILE 04 — Cohort Analysis & Customer Retention
-- =============================================================================
-- Business Question:
--   Are newer customers behaving differently from older ones? Which acquisition
--   cohorts retain the best? How does product cross-sell evolve over tenure?
--
-- Analytical Techniques Used:
--   CTEs, window functions (SUM OVER PARTITION, FIRST_VALUE),
--   date arithmetic, CASE WHEN bucketing, multi-level GROUP BY
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Q4.1  Cohort definition — customers grouped by year of account opening
-- -----------------------------------------------------------------------------
-- Business use: Track how each "class" of customers (e.g. those who joined
-- in 2020) evolves over time in terms of product holding and activity.
-- -----------------------------------------------------------------------------
WITH cohort_base AS (
    SELECT
        customer_id,
        customer_segment,
        is_active,
        num_products,
        account_tenure_days,
        CASE
            WHEN account_tenure_days > 365 * 7  THEN '2017 and before'
            WHEN account_tenure_days > 365 * 6  THEN '2018'
            WHEN account_tenure_days > 365 * 5  THEN '2019'
            WHEN account_tenure_days > 365 * 4  THEN '2020'
            WHEN account_tenure_days > 365 * 3  THEN '2021'
            WHEN account_tenure_days > 365 * 2  THEN '2022'
            WHEN account_tenure_days > 365 * 1  THEN '2023'
            ELSE                                     '2024'
        END AS cohort_year
    FROM customers
)
SELECT
    cohort_year,
    COUNT(*)                                                      AS customers_in_cohort,
    ROUND(
        SUM(CASE WHEN is_active = 1 THEN 1.0 ELSE 0 END)
        / COUNT(*) * 100, 1
    )                                                             AS retention_rate_pct,
    ROUND(AVG(num_products), 2)                                   AS avg_products_held,
    SUM(CASE WHEN num_products >= 3 THEN 1 ELSE 0 END)           AS multi_product_customers,
    ROUND(
        SUM(CASE WHEN num_products >= 3 THEN 1.0 ELSE 0 END)
        / COUNT(*) * 100, 1
    )                                                             AS multi_product_pct
FROM cohort_base
GROUP BY cohort_year
ORDER BY cohort_year;


-- -----------------------------------------------------------------------------
-- Q4.2  Transaction engagement by customer cohort
-- -----------------------------------------------------------------------------
-- Business use: Assess whether older cohorts are still transactionally active
-- (engaged) versus dormant despite still holding an account.
-- -----------------------------------------------------------------------------
WITH cohort_base AS (
    SELECT
        customer_id,
        CASE
            WHEN account_tenure_days > 365 * 5 THEN '5+ Years'
            WHEN account_tenure_days > 365 * 3 THEN '3–5 Years'
            WHEN account_tenure_days > 365 * 1 THEN '1–3 Years'
            ELSE '< 1 Year'
        END AS tenure_cohort
    FROM customers
),
txn_summary AS (
    SELECT
        t.customer_id,
        COUNT(t.transaction_id)         AS txn_count,
        ROUND(SUM(t.amount_myr), 2)     AS total_spend
    FROM transactions t
    GROUP BY t.customer_id
)
SELECT
    cb.tenure_cohort,
    COUNT(DISTINCT cb.customer_id)                                AS total_customers,
    COUNT(DISTINCT ts.customer_id)                                AS transacting_customers,
    ROUND(
        COUNT(DISTINCT ts.customer_id) * 100.0
        / COUNT(DISTINCT cb.customer_id), 1
    )                                                             AS engagement_rate_pct,
    ROUND(AVG(COALESCE(ts.txn_count, 0)), 1)                      AS avg_txns_per_customer,
    ROUND(AVG(COALESCE(ts.total_spend, 0)), 2)                    AS avg_spend_per_customer
FROM cohort_base cb
LEFT JOIN txn_summary ts ON cb.customer_id = ts.customer_id
GROUP BY cb.tenure_cohort
ORDER BY
    CASE cb.tenure_cohort
        WHEN '< 1 Year'   THEN 1
        WHEN '1–3 Years'  THEN 2
        WHEN '3–5 Years'  THEN 3
        ELSE 4
    END;


-- -----------------------------------------------------------------------------
-- Q4.3  Dormant customer identification
-- -----------------------------------------------------------------------------
-- Business use: Find customers with no transactions in the most recent
-- 6 months of the dataset. These are candidates for reactivation campaigns.
-- -----------------------------------------------------------------------------
WITH latest_txn AS (
    SELECT
        customer_id,
        MAX(transaction_date) AS last_txn_date
    FROM transactions
    GROUP BY customer_id
),
dataset_max_date AS (
    SELECT MAX(transaction_date) AS max_date FROM transactions
)
SELECT
    c.customer_id,
    c.customer_segment,
    c.state,
    c.num_products,
    c.is_active,
    lt.last_txn_date,
    dm.max_date                                                   AS dataset_end_date,
    CAST(
        (julianday(dm.max_date) - julianday(lt.last_txn_date))
        AS INTEGER
    )                                                             AS days_since_last_txn,
    CASE
        WHEN lt.last_txn_date IS NULL THEN 'Never Transacted'
        WHEN julianday(dm.max_date) - julianday(lt.last_txn_date) > 180
             THEN 'Dormant (>6 months)'
        WHEN julianday(dm.max_date) - julianday(lt.last_txn_date) > 90
             THEN 'At Risk (3–6 months)'
        ELSE 'Active'
    END                                                           AS activity_status
FROM customers c
CROSS JOIN dataset_max_date dm
LEFT JOIN latest_txn lt ON c.customer_id = lt.customer_id
ORDER BY days_since_last_txn DESC NULLS FIRST
LIMIT 30;


-- -----------------------------------------------------------------------------
-- Q4.4  Cross-sell effectiveness — which segments converted to multi-product?
-- -----------------------------------------------------------------------------
-- Business use: Measure how effectively the bank has cross-sold products
-- across segments. Low multi-product rate in Affluent = missed revenue.
-- -----------------------------------------------------------------------------
SELECT
    customer_segment,
    COUNT(*)                                                      AS total_customers,
    SUM(CASE WHEN num_products = 1 THEN 1 ELSE 0 END)            AS single_product,
    SUM(CASE WHEN num_products = 2 THEN 1 ELSE 0 END)            AS two_products,
    SUM(CASE WHEN num_products = 3 THEN 1 ELSE 0 END)            AS three_products,
    SUM(CASE WHEN num_products >= 4 THEN 1 ELSE 0 END)           AS four_plus_products,
    ROUND(
        SUM(CASE WHEN num_products >= 2 THEN 1.0 ELSE 0 END)
        / COUNT(*) * 100, 1
    )                                                             AS cross_sell_rate_pct
FROM customers
GROUP BY customer_segment
ORDER BY cross_sell_rate_pct DESC;


-- -----------------------------------------------------------------------------
-- Q4.5  Revenue concentration — top 20% of customers by spend
-- -----------------------------------------------------------------------------
-- Business use: Pareto analysis to confirm whether the top 20% of customers
-- drive ~80% of transaction value (classic 80/20 rule validation).
-- -----------------------------------------------------------------------------
WITH customer_spend AS (
    SELECT
        customer_id,
        ROUND(SUM(amount_myr), 2) AS total_spend_myr
    FROM transactions
    GROUP BY customer_id
),
ranked AS (
    SELECT
        customer_id,
        total_spend_myr,
        NTILE(5) OVER (ORDER BY total_spend_myr DESC) AS spend_quintile
    FROM customer_spend
)
SELECT
    spend_quintile,
    CASE spend_quintile
        WHEN 1 THEN 'Top 20%'
        WHEN 2 THEN 'Next 20%'
        WHEN 3 THEN 'Middle 20%'
        WHEN 4 THEN 'Lower 20%'
        ELSE        'Bottom 20%'
    END                                                           AS quintile_label,
    COUNT(*)                                                      AS customer_count,
    ROUND(SUM(total_spend_myr), 2)                                AS total_spend_myr,
    ROUND(
        SUM(total_spend_myr) * 100.0
        / SUM(SUM(total_spend_myr)) OVER (), 1
    )                                                             AS pct_of_total_spend
FROM ranked
GROUP BY spend_quintile
ORDER BY spend_quintile;
