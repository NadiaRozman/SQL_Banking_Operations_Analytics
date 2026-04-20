-- =============================================================================
-- QUERY FILE 01 — Customer Segmentation & Portfolio Analysis
-- =============================================================================
-- Business Question:
--   Who are our customers, how are they distributed across segments, and
--   what does the product portfolio look like per segment?
--
-- Analytical Techniques Used:
--   COUNT, AVG, GROUP BY, CASE WHEN, ROUND, ORDER BY, subqueries
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Q1.1  Customer count and share (%) by segment
-- -----------------------------------------------------------------------------
-- Business use: Understand the weight of each customer tier for resource
-- allocation, marketing budget, and relationship manager headcount planning.
-- -----------------------------------------------------------------------------
SELECT
    customer_segment,
    COUNT(*)                                                      AS total_customers,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1)           AS pct_of_total,
    ROUND(AVG(monthly_income_myr), 0)                            AS avg_monthly_income_myr,
    ROUND(AVG(num_products), 2)                                   AS avg_products_held,
    SUM(CASE WHEN is_active = 1 THEN 1 ELSE 0 END)               AS active_customers,
    ROUND(
        SUM(CASE WHEN is_active = 1 THEN 1.0 ELSE 0 END)
        / COUNT(*) * 100, 1
    )                                                             AS active_rate_pct
FROM customers
GROUP BY customer_segment
ORDER BY avg_monthly_income_myr DESC;


-- -----------------------------------------------------------------------------
-- Q1.2  State-level customer distribution — top 10 states
-- -----------------------------------------------------------------------------
-- Business use: Identify geographic concentration to guide branch expansion,
-- digital adoption campaigns, and regional risk exposure.
-- -----------------------------------------------------------------------------
SELECT
    state,
    COUNT(*)                                                      AS total_customers,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM customers), 1) AS pct_of_total,
    SUM(CASE WHEN is_active = 1 THEN 1 ELSE 0 END)               AS active_customers,
    ROUND(AVG(monthly_income_myr), 0)                            AS avg_income_myr
FROM customers
GROUP BY state
ORDER BY total_customers DESC
LIMIT 10;


-- -----------------------------------------------------------------------------
-- Q1.3  Age band distribution by segment
-- -----------------------------------------------------------------------------
-- Business use: Tailor product offerings and communication strategies to
-- generational cohorts within each customer segment.
-- -----------------------------------------------------------------------------
SELECT
    customer_segment,
    CASE
        WHEN age < 30              THEN '21-29 (Young Adult)'
        WHEN age BETWEEN 30 AND 39 THEN '30-39 (Early Career)'
        WHEN age BETWEEN 40 AND 49 THEN '40-49 (Mid Career)'
        WHEN age BETWEEN 50 AND 59 THEN '50-59 (Pre-Retirement)'
        ELSE                            '60+ (Retirement)'
    END                                                           AS age_band,
    COUNT(*)                                                      AS customer_count,
    ROUND(AVG(monthly_income_myr), 0)                            AS avg_income_myr,
    ROUND(AVG(num_products), 2)                                   AS avg_products_held
FROM customers
GROUP BY customer_segment, age_band
ORDER BY customer_segment, age_band;


-- -----------------------------------------------------------------------------
-- Q1.4  Product holding distribution — how many products do customers hold?
-- -----------------------------------------------------------------------------
-- Business use: Cross-sell opportunity sizing. Customers with 1 product are
-- the primary up-sell targets. Multi-product customers show deeper engagement.
-- -----------------------------------------------------------------------------
SELECT
    num_products,
    COUNT(*)                                                      AS customer_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM customers), 1) AS pct_of_customers,
    ROUND(AVG(monthly_income_myr), 0)                            AS avg_income_myr,
    ROUND(AVG(account_tenure_days) / 365.0, 1)                   AS avg_tenure_years
FROM customers
GROUP BY num_products
ORDER BY num_products;


-- -----------------------------------------------------------------------------
-- Q1.5  Long-tenure vs short-tenure customers — income and activity profile
-- -----------------------------------------------------------------------------
-- Business use: Determine if long-standing customers are rewarded with deeper
-- engagement, or if the bank risks tenure-based attrition.
-- -----------------------------------------------------------------------------
SELECT
    CASE
        WHEN account_tenure_days < 365          THEN '< 1 Year'
        WHEN account_tenure_days < 365 * 3      THEN '1–3 Years'
        WHEN account_tenure_days < 365 * 5      THEN '3–5 Years'
        ELSE                                         '5+ Years'
    END                                                           AS tenure_band,
    COUNT(*)                                                      AS customer_count,
    ROUND(AVG(monthly_income_myr), 0)                            AS avg_income_myr,
    ROUND(AVG(num_products), 2)                                   AS avg_products,
    ROUND(
        SUM(CASE WHEN is_active = 1 THEN 1.0 ELSE 0 END)
        / COUNT(*) * 100, 1
    )                                                             AS active_rate_pct
FROM customers
GROUP BY tenure_band
ORDER BY
    CASE tenure_band
        WHEN '< 1 Year'   THEN 1
        WHEN '1–3 Years'  THEN 2
        WHEN '3–5 Years'  THEN 3
        ELSE 4
    END;
