-- =============================================================================
-- QUERY FILE 06 — Executive Operations Scorecard
-- =============================================================================
-- Business Question:
--   Give me ONE comprehensive view of the bank's operational health —
--   combining customer activity, transaction performance, complaint resolution,
--   and product engagement into a single ranked scorecard per customer segment.
--
-- This is the capstone query of the project. It demonstrates:
--   ✦ Multi-CTE chaining (5 CTEs feeding into a final SELECT)
--   ✦ LEFT JOINs across all 5 tables
--   ✦ Window functions: RANK, NTILE, SUM OVER, AVG OVER
--   ✦ Composite KPI scoring
--   ✦ Business-grade output formatting
--
-- Analytical Techniques Used:
--   5-level CTE chain, LEFT JOIN, COALESCE, NULLIF, window functions,
--   conditional aggregation, composite scoring, CASE WHEN classification
-- =============================================================================


-- =============================================================================
-- PART A — Segment-Level Executive Scorecard
-- =============================================================================
WITH
-- CTE 1: Customer base per segment
segment_customers AS (
    SELECT
        customer_segment,
        COUNT(*)                                    AS total_customers,
        SUM(CASE WHEN is_active = 1 THEN 1 ELSE 0 END) AS active_customers,
        ROUND(AVG(monthly_income_myr), 0)           AS avg_income_myr,
        ROUND(AVG(num_products), 2)                 AS avg_products_held,
        ROUND(AVG(account_tenure_days) / 365.0, 1) AS avg_tenure_years
    FROM customers
    GROUP BY customer_segment
),

-- CTE 2: Transaction metrics per segment
segment_transactions AS (
    SELECT
        c.customer_segment,
        COUNT(t.transaction_id)                     AS total_transactions,
        ROUND(SUM(t.amount_myr), 2)                 AS total_txn_value_myr,
        ROUND(AVG(t.amount_myr), 2)                 AS avg_txn_value_myr,
        ROUND(
            SUM(CASE WHEN t.status = 'Failed' THEN 1.0 ELSE 0 END)
            / NULLIF(COUNT(t.transaction_id), 0) * 100, 2
        )                                           AS txn_failure_rate_pct,
        COUNT(DISTINCT t.customer_id)               AS transacting_customers
    FROM transactions t
    JOIN customers c ON t.customer_id = c.customer_id
    GROUP BY c.customer_segment
),

-- CTE 3: Complaint and SLA metrics per segment
segment_complaints AS (
    SELECT
        c.customer_segment,
        COUNT(cmp.complaint_id)                     AS total_complaints,
        SUM(cmp.sla_breached)                       AS total_sla_breaches,
        ROUND(
            SUM(cmp.sla_breached) * 100.0
            / NULLIF(COUNT(cmp.complaint_id), 0), 1
        )                                           AS sla_breach_rate_pct,
        ROUND(AVG(cmp.csat_score), 2)               AS avg_csat_score,
        ROUND(AVG(cmp.resolution_days), 1)          AS avg_resolution_days
    FROM complaints cmp
    JOIN customers c ON cmp.customer_id = c.customer_id
    GROUP BY c.customer_segment
),

-- CTE 4: Compute complaints per 1000 customers and txns per active customer
segment_ratios AS (
    SELECT
        sc.customer_segment,
        sc.total_customers,
        sc.active_customers,
        sc.avg_income_myr,
        sc.avg_products_held,
        sc.avg_tenure_years,
        ROUND(
            sc.active_customers * 100.0 / NULLIF(sc.total_customers, 0), 1
        )                                           AS retention_rate_pct,
        st.total_transactions,
        st.total_txn_value_myr,
        st.avg_txn_value_myr,
        st.txn_failure_rate_pct,
        ROUND(
            st.total_transactions * 1.0
            / NULLIF(sc.active_customers, 0), 1
        )                                           AS txns_per_active_customer,
        ROUND(
            st.total_txn_value_myr
            / NULLIF(sc.active_customers, 0), 2
        )                                           AS value_per_active_customer,
        scp.total_complaints,
        ROUND(
            scp.total_complaints * 1000.0
            / NULLIF(sc.total_customers, 0), 1
        )                                           AS complaints_per_1000_customers,
        scp.sla_breach_rate_pct,
        scp.avg_csat_score,
        scp.avg_resolution_days
    FROM segment_customers sc
    LEFT JOIN segment_transactions st ON sc.customer_segment = st.customer_segment
    LEFT JOIN segment_complaints scp  ON sc.customer_segment = scp.customer_segment
),

-- CTE 5: Score each segment across four dimensions (0–25 each, total /100)
segment_scored AS (
    SELECT
        *,
        -- Retention score (0–25): higher retention = better score
        ROUND(retention_rate_pct / 4.0, 1)          AS score_retention,

        -- Engagement score (0–25): more txns per customer = better
        CASE
            WHEN txns_per_active_customer >= 15 THEN 25.0
            WHEN txns_per_active_customer >= 10 THEN 20.0
            WHEN txns_per_active_customer >= 7  THEN 15.0
            WHEN txns_per_active_customer >= 4  THEN 10.0
            ELSE 5.0
        END                                          AS score_engagement,

        -- SLA / complaint score (0–25): lower breach rate and CSAT ≥ 4 = better
        ROUND(
            (1 - sla_breach_rate_pct / 100.0) * 15
            + (avg_csat_score / 5.0) * 10, 1
        )                                            AS score_service,

        -- Failure rate score (0–25): lower failure = better
        ROUND(
            (1 - txn_failure_rate_pct / 100.0) * 25, 1
        )                                            AS score_reliability
    FROM segment_ratios
)

-- FINAL OUTPUT — Executive Scorecard
SELECT
    customer_segment,
    total_customers,
    ROUND(retention_rate_pct, 1)                                  AS retention_rate_pct,
    txns_per_active_customer,
    avg_txn_value_myr                                             AS avg_txn_value_myr,
    complaints_per_1000_customers,
    sla_breach_rate_pct,
    avg_csat_score,
    txn_failure_rate_pct,
    avg_products_held,
    -- Dimension scores
    score_retention,
    score_engagement,
    score_service,
    score_reliability,
    -- Composite score /100
    ROUND(
        score_retention + score_engagement + score_service + score_reliability, 1
    )                                                             AS composite_score_100,
    -- Overall health rating
    CASE
        WHEN score_retention + score_engagement + score_service + score_reliability >= 85
             THEN 'EXCELLENT'
        WHEN score_retention + score_engagement + score_service + score_reliability >= 70
             THEN 'GOOD'
        WHEN score_retention + score_engagement + score_service + score_reliability >= 55
             THEN 'FAIR'
        ELSE 'NEEDS ATTENTION'
    END                                                           AS health_rating,
    RANK() OVER (
        ORDER BY score_retention + score_engagement + score_service + score_reliability DESC
    )                                                             AS segment_rank
FROM segment_scored
ORDER BY composite_score_100 DESC;


-- =============================================================================
-- PART B — Monthly KPI Trend Dashboard (last 6 months of dataset)
-- =============================================================================
-- Business use: Summarise key operational metrics month-by-month in a
-- single result set that could feed directly into a reporting dashboard.
-- =============================================================================
WITH monthly_txns AS (
    SELECT
        transaction_month,
        COUNT(*)                               AS txn_count,
        ROUND(SUM(amount_myr), 2)              AS txn_value_myr,
        ROUND(
            SUM(CASE WHEN status = 'Failed' THEN 1.0 ELSE 0 END)
            / COUNT(*) * 100, 2
        )                                      AS failure_rate_pct
    FROM transactions
    GROUP BY transaction_month
),
monthly_complaints AS (
    SELECT
        strftime('%Y-%m', filed_date)          AS complaint_month,
        COUNT(*)                               AS complaint_count,
        SUM(sla_breached)                      AS sla_breaches,
        ROUND(AVG(csat_score), 2)              AS avg_csat
    FROM complaints
    GROUP BY complaint_month
)
SELECT
    mt.transaction_month        AS month,
    mt.txn_count,
    mt.txn_value_myr,
    mt.failure_rate_pct,
    COALESCE(mc.complaint_count, 0) AS complaint_count,
    COALESCE(mc.sla_breaches, 0)    AS sla_breaches,
    ROUND(
        COALESCE(mc.sla_breaches, 0) * 100.0
        / NULLIF(mc.complaint_count, 0), 1
    )                               AS sla_breach_pct,
    COALESCE(mc.avg_csat, NULL)     AS avg_csat_score,
    -- Running totals
    SUM(mt.txn_count) OVER (ORDER BY mt.transaction_month) AS cumulative_txns,
    SUM(mt.txn_value_myr) OVER (ORDER BY mt.transaction_month) AS cumulative_value_myr
FROM monthly_txns mt
LEFT JOIN monthly_complaints mc
    ON mt.transaction_month = mc.complaint_month
ORDER BY mt.transaction_month;
