-- =============================================================================
-- QUERY FILE 02 — Transaction Behaviour & Revenue Activity Analysis
-- =============================================================================
-- Business Question:
--   What are our transaction patterns? Which channels, products, and customer
--   segments are driving the most volume? Where are failure rates highest?
--
-- Analytical Techniques Used:
--   GROUP BY, HAVING, window functions (SUM OVER, RANK OVER, LAG),
--   CTEs, CASE WHEN, date functions, subqueries
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Q2.1  Monthly transaction volume and value trend (2023–2024)
-- -----------------------------------------------------------------------------
-- Business use: Identify seasonality, growth trends, and anomalous months
-- that may require operational investigation.
-- -----------------------------------------------------------------------------
SELECT
    transaction_month,
    COUNT(*)                                      AS total_transactions,
    ROUND(SUM(amount_myr), 2)                     AS total_value_myr,
    ROUND(AVG(amount_myr), 2)                     AS avg_txn_value_myr,
    SUM(CASE WHEN status = 'Successful'
             THEN 1 ELSE 0 END)                   AS successful_txns,
    SUM(CASE WHEN status = 'Failed'
             THEN 1 ELSE 0 END)                   AS failed_txns,
    ROUND(
        SUM(CASE WHEN status = 'Failed' THEN 1.0 ELSE 0 END)
        / COUNT(*) * 100, 2
    )                                             AS failure_rate_pct
FROM transactions
GROUP BY transaction_month
ORDER BY transaction_month;


-- -----------------------------------------------------------------------------
-- Q2.2  Month-over-month transaction volume change (using LAG window function)
-- -----------------------------------------------------------------------------
-- Business use: Detect growth acceleration or deceleration in transaction
-- volumes for forecasting and capacity planning.
-- -----------------------------------------------------------------------------
WITH monthly_summary AS (
    SELECT
        transaction_month,
        COUNT(*)               AS total_transactions,
        ROUND(SUM(amount_myr), 2) AS total_value_myr
    FROM transactions
    GROUP BY transaction_month
)
SELECT
    transaction_month,
    total_transactions,
    total_value_myr,
    LAG(total_transactions)  OVER (ORDER BY transaction_month) AS prev_month_txns,
    total_transactions
    - LAG(total_transactions) OVER (ORDER BY transaction_month) AS txn_mom_change,
    ROUND(
        (total_transactions
         - LAG(total_transactions) OVER (ORDER BY transaction_month))
        * 100.0
        / NULLIF(LAG(total_transactions) OVER (ORDER BY transaction_month), 0),
    1)                                                           AS txn_mom_pct_change
FROM monthly_summary
ORDER BY transaction_month;


-- -----------------------------------------------------------------------------
-- Q2.3  Transaction breakdown by channel
-- -----------------------------------------------------------------------------
-- Business use: Track digital adoption (Mobile App, Online Banking) vs
-- physical (Branch, ATM) to justify digital transformation investment.
-- -----------------------------------------------------------------------------
SELECT
    channel,
    COUNT(*)                                          AS total_transactions,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS pct_share,
    ROUND(SUM(amount_myr), 2)                         AS total_value_myr,
    ROUND(AVG(amount_myr), 2)                         AS avg_txn_value_myr,
    ROUND(
        SUM(CASE WHEN status = 'Failed' THEN 1.0 ELSE 0 END)
        / COUNT(*) * 100, 2
    )                                                 AS failure_rate_pct
FROM transactions
GROUP BY channel
ORDER BY total_transactions DESC;


-- -----------------------------------------------------------------------------
-- Q2.4  Transaction type analysis
-- -----------------------------------------------------------------------------
-- Business use: Understand what customers are actually doing — purchasing,
-- transferring, paying bills — to shape product and UX design decisions.
-- -----------------------------------------------------------------------------
SELECT
    transaction_type,
    COUNT(*)                                          AS total_transactions,
    ROUND(SUM(amount_myr), 2)                         AS total_value_myr,
    ROUND(AVG(amount_myr), 2)                         AS avg_txn_value_myr,
    ROUND(
        SUM(CASE WHEN status = 'Successful' THEN 1.0 ELSE 0 END)
        / COUNT(*) * 100, 1
    )                                                 AS success_rate_pct
FROM transactions
GROUP BY transaction_type
ORDER BY total_value_myr DESC;


-- -----------------------------------------------------------------------------
-- Q2.5  Top 10 most active customers by transaction volume
-- -----------------------------------------------------------------------------
-- Business use: Identify power users for VIP programmes or relationship
-- manager assignment. Also flags potential anomalous activity for fraud review.
-- -----------------------------------------------------------------------------
WITH customer_activity AS (
    SELECT
        t.customer_id,
        c.customer_segment,
        c.state,
        COUNT(t.transaction_id)        AS total_transactions,
        ROUND(SUM(t.amount_myr), 2)    AS total_spend_myr,
        ROUND(AVG(t.amount_myr), 2)    AS avg_txn_value_myr,
        COUNT(DISTINCT t.transaction_type) AS distinct_txn_types,
        COUNT(DISTINCT t.channel)      AS channels_used
    FROM transactions t
    JOIN customers c ON t.customer_id = c.customer_id
    GROUP BY t.customer_id, c.customer_segment, c.state
)
SELECT
    customer_id,
    customer_segment,
    state,
    total_transactions,
    total_spend_myr,
    avg_txn_value_myr,
    distinct_txn_types,
    channels_used,
    RANK() OVER (ORDER BY total_transactions DESC) AS activity_rank
FROM customer_activity
ORDER BY total_transactions DESC
LIMIT 10;


-- -----------------------------------------------------------------------------
-- Q2.6  Product-level transaction performance
-- -----------------------------------------------------------------------------
-- Business use: Determine which products are generating the most transaction
-- activity and flag underperforming products for review or redesign.
-- -----------------------------------------------------------------------------
SELECT
    p.product_name,
    p.product_category,
    COUNT(t.transaction_id)                           AS total_transactions,
    ROUND(SUM(t.amount_myr), 2)                       AS total_value_myr,
    ROUND(AVG(t.amount_myr), 2)                       AS avg_txn_value_myr,
    ROUND(
        SUM(CASE WHEN t.status = 'Failed' THEN 1.0 ELSE 0 END)
        / COUNT(*) * 100, 2
    )                                                 AS failure_rate_pct
FROM transactions t
JOIN products p ON t.product_id = p.product_id
GROUP BY p.product_name, p.product_category
ORDER BY total_transactions DESC;


-- -----------------------------------------------------------------------------
-- Q2.7  High-value transaction flag — customers with unusually large transactions
-- -----------------------------------------------------------------------------
-- Business use: Operational risk and anti-money-laundering screening.
-- Customers whose average transaction is more than 2x the overall average
-- warrant closer review under compliance frameworks.
-- -----------------------------------------------------------------------------
WITH overall_avg AS (
    SELECT AVG(amount_myr) AS global_avg FROM transactions
),
customer_avg AS (
    SELECT
        customer_id,
        ROUND(AVG(amount_myr), 2)   AS cust_avg_txn,
        COUNT(*)                     AS txn_count,
        ROUND(MAX(amount_myr), 2)    AS max_single_txn
    FROM transactions
    GROUP BY customer_id
)
SELECT
    ca.customer_id,
    c.customer_segment,
    ca.txn_count,
    ca.cust_avg_txn,
    ca.max_single_txn,
    ROUND(oa.global_avg, 2)                            AS global_avg_txn,
    ROUND(ca.cust_avg_txn / oa.global_avg, 2)          AS ratio_to_global_avg,
    CASE
        WHEN ca.cust_avg_txn > oa.global_avg * 3 THEN 'HIGH RISK'
        WHEN ca.cust_avg_txn > oa.global_avg * 2 THEN 'ELEVATED'
        ELSE 'NORMAL'
    END                                                AS risk_flag
FROM customer_avg ca
CROSS JOIN overall_avg oa
JOIN customers c ON ca.customer_id = c.customer_id
WHERE ca.cust_avg_txn > oa.global_avg * 2
ORDER BY ratio_to_global_avg DESC
LIMIT 20;
