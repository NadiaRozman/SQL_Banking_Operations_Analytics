-- =============================================================================
-- QUERY FILE 03 — Complaints Analysis & SLA Performance
-- =============================================================================
-- Business Question:
--   How well is the bank resolving customer complaints? Where are SLA breaches
--   most concentrated, and which segments are most affected?
--
-- Analytical Techniques Used:
--   CTEs, JOIN, window functions (RANK, NTILE, AVG OVER PARTITION BY),
--   CASE WHEN, HAVING, date arithmetic, subqueries
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Q3.1  Complaint volume by category — with SLA breach rate
-- -----------------------------------------------------------------------------
-- Business use: Prioritise which complaint types to address operationally.
-- High-breach categories signal process failures and carry regulatory risk.
-- -----------------------------------------------------------------------------
SELECT
    c.complaint_category,
    st.sla_target_days,
    st.priority,
    COUNT(c.complaint_id)                                         AS total_complaints,
    SUM(c.sla_breached)                                           AS sla_breaches,
    ROUND(SUM(c.sla_breached) * 100.0 / COUNT(*), 1)             AS breach_rate_pct,
    ROUND(AVG(c.resolution_days), 1)                              AS avg_resolution_days,
    ROUND(AVG(c.csat_score), 2)                                   AS avg_csat_score,
    MIN(c.resolution_days)                                        AS min_resolution_days,
    MAX(c.resolution_days)                                        AS max_resolution_days
FROM complaints c
JOIN sla_targets st ON c.complaint_category = st.complaint_category
GROUP BY c.complaint_category, st.sla_target_days, st.priority
ORDER BY breach_rate_pct DESC;


-- -----------------------------------------------------------------------------
-- Q3.2  Monthly complaint trend with rolling SLA breach rate
-- -----------------------------------------------------------------------------
-- Business use: Monitor whether complaint volumes and breach rates are
-- improving or deteriorating over time — key metric for ops leadership.
-- -----------------------------------------------------------------------------
WITH monthly_complaints AS (
    SELECT
        strftime('%Y-%m', filed_date)          AS complaint_month,
        COUNT(*)                               AS total_complaints,
        SUM(sla_breached)                      AS breaches,
        ROUND(AVG(resolution_days), 1)         AS avg_resolution_days,
        ROUND(AVG(csat_score), 2)              AS avg_csat
    FROM complaints
    GROUP BY complaint_month
)
SELECT
    complaint_month,
    total_complaints,
    breaches,
    ROUND(breaches * 100.0 / total_complaints, 1)                AS breach_rate_pct,
    avg_resolution_days,
    avg_csat,
    SUM(total_complaints) OVER (
        ORDER BY complaint_month
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    )                                                             AS rolling_3m_complaints,
    ROUND(AVG(CAST(breaches AS REAL)) OVER (
        ORDER BY complaint_month
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 1)                                                         AS rolling_3m_avg_breaches
FROM monthly_complaints
ORDER BY complaint_month;


-- -----------------------------------------------------------------------------
-- Q3.3  SLA performance by channel
-- -----------------------------------------------------------------------------
-- Business use: Determine if complaints filed via certain channels (e.g.
-- Call Centre vs Mobile App) are resolved faster — informs channel investment.
-- -----------------------------------------------------------------------------
SELECT
    channel,
    COUNT(*)                                                      AS total_complaints,
    SUM(sla_breached)                                             AS total_breaches,
    ROUND(SUM(sla_breached) * 100.0 / COUNT(*), 1)               AS breach_rate_pct,
    ROUND(AVG(resolution_days), 1)                                AS avg_resolution_days,
    ROUND(AVG(csat_score), 2)                                     AS avg_csat_score
FROM complaints
GROUP BY channel
ORDER BY breach_rate_pct DESC;


-- -----------------------------------------------------------------------------
-- Q3.4  Customer-level complaint frequency — repeat complainants
-- -----------------------------------------------------------------------------
-- Business use: Identify customers who have complained multiple times.
-- These are high churn-risk customers requiring proactive outreach.
-- -----------------------------------------------------------------------------
WITH complaint_freq AS (
    SELECT
        customer_id,
        COUNT(*)                              AS complaint_count,
        SUM(sla_breached)                     AS total_breaches,
        ROUND(AVG(csat_score), 2)             AS avg_csat,
        MIN(filed_date)                       AS first_complaint_date,
        MAX(filed_date)                       AS last_complaint_date
    FROM complaints
    GROUP BY customer_id
)
SELECT
    cf.customer_id,
    c.customer_segment,
    c.state,
    cf.complaint_count,
    cf.total_breaches,
    cf.avg_csat,
    cf.first_complaint_date,
    cf.last_complaint_date,
    CASE
        WHEN cf.complaint_count >= 5 THEN 'Frequent Complainant — Priority Review'
        WHEN cf.complaint_count >= 3 THEN 'Repeat Complainant — Monitor'
        ELSE 'Single/Occasional'
    END                                                           AS complainant_tier
FROM complaint_freq cf
JOIN customers c ON cf.customer_id = c.customer_id
WHERE cf.complaint_count >= 3
ORDER BY cf.complaint_count DESC, cf.avg_csat ASC
LIMIT 25;


-- -----------------------------------------------------------------------------
-- Q3.5  CSAT score distribution — complaint category vs resolution speed
-- -----------------------------------------------------------------------------
-- Business use: Validate whether faster resolution actually improves CSAT,
-- and identify categories where speed alone is not driving satisfaction.
-- -----------------------------------------------------------------------------
SELECT
    complaint_category,
    CASE
        WHEN resolution_days <= sla_target_days THEN 'Within SLA'
        ELSE 'Breached SLA'
    END                                                           AS sla_status,
    COUNT(*)                                                      AS complaint_count,
    ROUND(AVG(csat_score), 2)                                     AS avg_csat_score,
    SUM(CASE WHEN csat_score >= 4 THEN 1 ELSE 0 END)             AS satisfied_count,
    ROUND(
        SUM(CASE WHEN csat_score >= 4 THEN 1.0 ELSE 0 END)
        / COUNT(*) * 100, 1
    )                                                             AS satisfaction_rate_pct
FROM complaints
GROUP BY complaint_category, sla_status
ORDER BY complaint_category, sla_status;


-- -----------------------------------------------------------------------------
-- Q3.6  Multi-CTE: Customer Risk Scorecard (complaints + transactions)
-- -----------------------------------------------------------------------------
-- Business use: Composite view combining complaint history with transaction
-- activity to classify customers by overall operational risk. This mirrors
-- real-world CRM risk-tiering frameworks used by banks.
-- -----------------------------------------------------------------------------
WITH complaint_profile AS (
    SELECT
        customer_id,
        COUNT(*)                              AS complaint_count,
        SUM(sla_breached)                     AS breaches_experienced,
        ROUND(AVG(csat_score), 2)             AS avg_csat,
        MAX(filed_date)                       AS most_recent_complaint
    FROM complaints
    GROUP BY customer_id
),
transaction_profile AS (
    SELECT
        customer_id,
        COUNT(*)                              AS txn_count,
        ROUND(SUM(amount_myr), 2)             AS total_spend_myr,
        SUM(CASE WHEN status = 'Failed'
                 THEN 1 ELSE 0 END)           AS failed_txns,
        ROUND(
            SUM(CASE WHEN status = 'Failed' THEN 1.0 ELSE 0 END)
            / COUNT(*) * 100, 2
        )                                     AS fail_rate_pct
    FROM transactions
    GROUP BY customer_id
),
risk_score AS (
    SELECT
        c.customer_id,
        c.customer_segment,
        c.state,
        c.is_active,
        COALESCE(cp.complaint_count, 0)        AS complaint_count,
        COALESCE(cp.breaches_experienced, 0)   AS breaches_experienced,
        COALESCE(cp.avg_csat, 5)               AS avg_csat,
        COALESCE(tp.txn_count, 0)              AS txn_count,
        COALESCE(tp.total_spend_myr, 0)        AS total_spend_myr,
        COALESCE(tp.fail_rate_pct, 0)          AS fail_rate_pct,
        -- Risk score: higher = more at-risk
        (COALESCE(cp.complaint_count, 0) * 2)
        + (COALESCE(cp.breaches_experienced, 0) * 3)
        + CASE WHEN COALESCE(cp.avg_csat, 5) < 3 THEN 5 ELSE 0 END
        + CASE WHEN COALESCE(tp.fail_rate_pct, 0) > 10 THEN 3 ELSE 0 END
        + CASE WHEN c.is_active = 0 THEN 4 ELSE 0 END
                                               AS risk_score
    FROM customers c
    LEFT JOIN complaint_profile cp ON c.customer_id = cp.customer_id
    LEFT JOIN transaction_profile tp ON c.customer_id = tp.customer_id
)
SELECT
    customer_id,
    customer_segment,
    state,
    complaint_count,
    breaches_experienced,
    ROUND(avg_csat, 2)                                            AS avg_csat,
    txn_count,
    total_spend_myr,
    fail_rate_pct,
    risk_score,
    CASE
        WHEN risk_score >= 15 THEN 'CRITICAL — Immediate Outreach'
        WHEN risk_score >= 10 THEN 'HIGH — Schedule Review'
        WHEN risk_score >= 5  THEN 'MEDIUM — Monitor'
        ELSE                       'LOW — Standard'
    END                                                           AS risk_tier,
    NTILE(4) OVER (ORDER BY risk_score DESC)                      AS risk_quartile
FROM risk_score
ORDER BY risk_score DESC
LIMIT 30;
