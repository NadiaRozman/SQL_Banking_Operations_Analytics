-- =============================================================================
-- QUERY FILE 05 — Product Performance Analysis
-- =============================================================================
-- Business Question:
--   Which products are driving the most value, and which are underperforming?
--   How does product mix correlate with customer satisfaction and complaints?
--
-- Analytical Techniques Used:
--   CTEs, multi-table JOINs, aggregation, window functions (RANK, PERCENT_RANK),
--   CASE WHEN, ROUND, conditional aggregation
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Q5.1  Product adoption — how many customers hold each product?
-- -----------------------------------------------------------------------------
-- Business use: Understand market penetration of each product within the
-- customer base to guide cross-sell prioritisation.
--
-- NOTE: products_held is stored as a pipe-delimited string (e.g. "P001|P007").
-- This query uses LIKE to count customers holding each product — a realistic
-- workaround for denormalised storage, commonly seen in operational systems.
-- -----------------------------------------------------------------------------
SELECT
    p.product_id,
    p.product_name,
    p.product_category,
    p.min_balance,
    p.annual_fee,
    COUNT(c.customer_id)                                          AS customers_holding,
    ROUND(
        COUNT(c.customer_id) * 100.0 / (SELECT COUNT(*) FROM customers), 1
    )                                                             AS penetration_rate_pct
FROM products p
LEFT JOIN customers c
    ON ('|' || c.products_held || '|') LIKE ('%|' || p.product_id || '|%')
GROUP BY p.product_id, p.product_name, p.product_category, p.min_balance, p.annual_fee
ORDER BY customers_holding DESC;


-- -----------------------------------------------------------------------------
-- Q5.2  Product revenue contribution — transaction value per product
-- -----------------------------------------------------------------------------
-- Business use: Determine which products are generating the highest
-- transaction throughput (a proxy for engagement and fee income).
-- -----------------------------------------------------------------------------
WITH product_txn AS (
    SELECT
        t.product_id,
        COUNT(t.transaction_id)          AS total_transactions,
        ROUND(SUM(t.amount_myr), 2)      AS total_value_myr,
        ROUND(AVG(t.amount_myr), 2)      AS avg_txn_value_myr,
        COUNT(DISTINCT t.customer_id)    AS unique_customers,
        ROUND(
            SUM(CASE WHEN t.status = 'Failed' THEN 1.0 ELSE 0 END)
            / COUNT(*) * 100, 2
        )                                AS failure_rate_pct
    FROM transactions t
    GROUP BY t.product_id
)
SELECT
    p.product_id,
    p.product_name,
    p.product_category,
    pt.total_transactions,
    pt.total_value_myr,
    pt.avg_txn_value_myr,
    pt.unique_customers,
    pt.failure_rate_pct,
    RANK() OVER (ORDER BY pt.total_value_myr DESC)                AS revenue_rank
FROM product_txn pt
JOIN products p ON pt.product_id = p.product_id
ORDER BY pt.total_value_myr DESC;


-- -----------------------------------------------------------------------------
-- Q5.3  Product complaint rate — which products generate the most complaints?
-- -----------------------------------------------------------------------------
-- Business use: High complaint rates on specific products signal quality
-- or process issues requiring product team intervention.
-- -----------------------------------------------------------------------------
WITH product_complaints AS (
    SELECT
        product_id,
        COUNT(*)                         AS complaint_count,
        SUM(sla_breached)                AS sla_breaches,
        ROUND(AVG(csat_score), 2)        AS avg_csat,
        ROUND(AVG(resolution_days), 1)   AS avg_resolution_days
    FROM complaints
    GROUP BY product_id
),
product_txn_count AS (
    SELECT product_id, COUNT(*) AS txn_count
    FROM transactions
    GROUP BY product_id
)
SELECT
    p.product_id,
    p.product_name,
    p.product_category,
    COALESCE(pc.complaint_count, 0)                               AS complaint_count,
    COALESCE(tc.txn_count, 0)                                     AS txn_count,
    CASE
        WHEN COALESCE(tc.txn_count, 0) = 0 THEN NULL
        ELSE ROUND(
            COALESCE(pc.complaint_count, 0) * 1000.0 / tc.txn_count, 2
        )
    END                                                           AS complaints_per_1000_txns,
    COALESCE(pc.sla_breaches, 0)                                  AS sla_breaches,
    COALESCE(pc.avg_csat, NULL)                                   AS avg_csat
FROM products p
LEFT JOIN product_complaints pc ON p.product_id = pc.product_id
LEFT JOIN product_txn_count tc ON p.product_id = tc.product_id
ORDER BY complaints_per_1000_txns DESC NULLS LAST;


-- -----------------------------------------------------------------------------
-- Q5.4  Segment × Product affinity matrix
-- -----------------------------------------------------------------------------
-- Business use: Reveal which segments gravitate toward which products.
-- A Mass customer holding a Platinum Card, for instance, could indicate
-- credit risk mis-alignment or successful up-sell.
-- -----------------------------------------------------------------------------
SELECT
    c.customer_segment,
    p.product_name,
    p.product_category,
    COUNT(c.customer_id)                                          AS customers_holding,
    ROUND(
        COUNT(c.customer_id) * 100.0
        / SUM(COUNT(c.customer_id)) OVER (PARTITION BY c.customer_segment), 1
    )                                                             AS pct_within_segment
FROM products p
JOIN customers c
    ON ('|' || c.products_held || '|') LIKE ('%|' || p.product_id || '|%')
GROUP BY c.customer_segment, p.product_name, p.product_category
ORDER BY c.customer_segment, customers_holding DESC;


-- -----------------------------------------------------------------------------
-- Q5.5  Digital product adoption by state — Digital Wallet & Online Banking
-- -----------------------------------------------------------------------------
-- Business use: Track digital channel penetration geographically to
-- guide state-level digital literacy campaigns and infrastructure investment.
-- -----------------------------------------------------------------------------
SELECT
    c.state,
    COUNT(DISTINCT c.customer_id)                                 AS total_customers,
    SUM(
        CASE WHEN ('|' || c.products_held || '|') LIKE '%|P010|%'
             THEN 1 ELSE 0 END
    )                                                             AS digital_wallet_holders,
    ROUND(
        SUM(
            CASE WHEN ('|' || c.products_held || '|') LIKE '%|P010|%'
                 THEN 1.0 ELSE 0 END
        ) / COUNT(DISTINCT c.customer_id) * 100, 1
    )                                                             AS digital_wallet_pct,
    ROUND(
        SUM(
            CASE WHEN ('|' || c.products_held || '|') LIKE '%|P001|%'
                      OR ('|' || c.products_held || '|') LIKE '%|P002|%'
                 THEN 1.0 ELSE 0 END
        ) / COUNT(DISTINCT c.customer_id) * 100, 1
    )                                                             AS savings_penetration_pct
FROM customers c
GROUP BY c.state
ORDER BY digital_wallet_pct DESC;
