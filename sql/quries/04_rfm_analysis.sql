-- File: 04_rfm_analysis.sql
-- Purpose: Join transactions_clean with customer_profiles to build the 
--          foundation for RFM (Recency, Frequency, Monetary) scoring.
--          transactions_clean leads the join (LEFT JOIN) since it holds 
--          the actual purchasing behavior RFM depends on; customer_profiles 
--          is supplementary enrichment and may not have a match for every 
--          transaction (guest checkouts, unmatched customer_ids).

-- Query: Join Sanity Check
-- Purpose: Verify the join behaves as expected before building RFM logic 
--          on top of it — no row duplication, and understand the scope 
--          of unmatched rows
-- Finding: Row count after the join (1,021,361) exactly matches 
--          transactions_clean alone, confirming customer_profiles has no 
--          duplicate customer_ids and the join does not inflate row 
--          counts. 227,200 transaction rows have no matching profile — 
--          all of these are null-customer_id (guest checkout) rows, which 
--          were already excluded from any customer-level analysis by 
--          design. Confirmed separately that zero rows with a real, 
--          non-null customer_id lack a profile match — expected, since 
--          customer_profiles was built directly from every distinct real 
--          customer_id in transactions_clean. RFM scoring can proceed 
--          filtering only on customer_id IS NOT NULL, with no risk of 
--          losing real customers to a missing profile.
SELECT *
FROM transactions_clean tc
LEFT JOIN customer_profiles cp ON tc.customer_id = cp.customer_id
LIMIT 50;

SELECT COUNT(*)
FROM transactions_clean tc
LEFT JOIN customer_profiles cp ON tc.customer_id = cp.customer_id;

SELECT COUNT(*)
FROM transactions_clean tc
LEFT JOIN customer_profiles cp ON tc.customer_id = cp.customer_id
WHERE cp.customer_id IS NULL;

SELECT COUNT(*)
FROM transactions_clean tc
LEFT JOIN customer_profiles cp ON tc.customer_id = cp.customer_id
WHERE tc.customer_id IS NOT NULL AND cp.customer_id IS NULL;


-- Query: RFM Base Calculation (Recency, Frequency, Monetary)
-- Purpose: Calculate raw Recency, Frequency, and Monetary values per 
--          customer, using the dataset's own latest recorded date as the 
--          recency reference point, and excluding cancelled invoices and 
--          guest checkouts (null customer_id) from all three metrics
-- Finding: 5,852 customers have valid RFM values, short of the expected 
--          5,875 real customers. Verified separately that the gap is 
--          exactly 23 customers whose entire invoice history consists of 
--          cancellations (100% C-prefix invoices) — with no non-cancelled 
--          purchases, they correctly have no surviving RFM data after 
--          filtering.
WITH reference_date AS (
    SELECT MAX(invoice_date) AS max_date FROM transactions_clean
)
SELECT
    customer_id,
    (SELECT max_date FROM reference_date) - MAX(invoice_date) AS recency,
    COUNT(DISTINCT invoice) AS frequency,
    SUM(quantity * price) AS monetary
FROM transactions_clean
WHERE customer_id IS NOT NULL AND invoice NOT LIKE 'C%'
GROUP BY customer_id;

-- Row count check on the base calculation above
SELECT COUNT(*) FROM (
    WITH reference_date AS (
        SELECT MAX(invoice_date) AS max_date FROM transactions_clean
    )
    SELECT
        customer_id,
        (SELECT max_date FROM reference_date) - MAX(invoice_date) AS recency,
        COUNT(DISTINCT invoice) AS frequency,
        SUM(quantity * price) AS monetary
    FROM transactions_clean
    WHERE customer_id IS NOT NULL AND invoice NOT LIKE 'C%'
    GROUP BY customer_id
) AS base_count;

-- Verification: customers whose entire invoice history is cancellations
SELECT COUNT(*) FROM (
    SELECT customer_id
    FROM transactions_clean
    WHERE customer_id IS NOT NULL
    GROUP BY customer_id
    HAVING COUNT(*) FILTER (WHERE invoice NOT LIKE 'C%') = 0
) AS cancel_only_customers;


-- Query: RFM Quintile Scoring (NTILE)
-- Purpose: Convert raw Recency, Frequency, and Monetary values into 1-5 
--          scores using NTILE(5), with recency ordered DESC (so recent 
--          purchases score high) and frequency/monetary ordered ASC (so 
--          high activity/spend scores high) — keeping 5 = best across 
--          all three metrics
-- Finding: Verified bucket sizes come out roughly even (~1,170 customers 
--          each) across all 5 r_score groups, as expected — NTILE(5) 
--          always splits ranked rows into equal-sized buckets by design, 
--          regardless of how the underlying values are distributed.
WITH reference_date AS (
    SELECT MAX(invoice_date) AS max_date FROM transactions_clean
),
rfm_base AS (
    SELECT
        customer_id,
        (SELECT max_date FROM reference_date) - MAX(invoice_date) AS recency,
        COUNT(DISTINCT invoice) AS frequency,
        SUM(quantity * price) AS monetary
    FROM transactions_clean
    WHERE customer_id IS NOT NULL AND invoice NOT LIKE 'C%'
    GROUP BY customer_id
)
SELECT
    customer_id,
    recency,
    frequency,
    monetary,
    NTILE(5) OVER (ORDER BY recency DESC) AS r_score,
    NTILE(5) OVER (ORDER BY frequency ASC) AS f_score,
    NTILE(5) OVER (ORDER BY monetary ASC) AS m_score
FROM rfm_base;

-- Bucket size verification
WITH reference_date AS (
    SELECT MAX(invoice_date) AS max_date FROM transactions_clean
),
rfm_base AS (
    SELECT
        customer_id,
        (SELECT max_date FROM reference_date) - MAX(invoice_date) AS recency,
        COUNT(DISTINCT invoice) AS frequency,
        SUM(quantity * price) AS monetary
    FROM transactions_clean
    WHERE customer_id IS NOT NULL AND invoice NOT LIKE 'C%'
    GROUP BY customer_id
),
rfm_scored AS (
    SELECT
        customer_id,
        recency,
        frequency,
        monetary,
        NTILE(5) OVER (ORDER BY recency DESC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC) AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC) AS m_score
    FROM rfm_base
)
SELECT r_score, COUNT(*) FROM rfm_scored GROUP BY r_score ORDER BY r_score;


-- Query: RFM Segment Assignment
-- Purpose: Combine r_score and the average of f_score/m_score (fm_score) 
--          into 6 named customer segments — Champions, Loyal Customers, 
--          Potential Loyalists, New Customers, At Risk, and Lost — using 
--          an ordered CASE WHEN so each customer lands in exactly one 
--          segment
-- Finding: Final distribution: Loyal Customers 1,892 (32.3%), Lost 1,857 
--          (31.7%), Champions 610 (10.4%), At Risk 690 (11.8%), Potential 
--          Loyalists 569 (9.7%), New Customers 234 (4.0%). Champions' 
--          threshold was tightened from an initial r_score>=4/fm_score>=4 
--          rule (which produced an unrealistic 22% Champions) to 
--          r_score=5/fm_score>=4.5, bringing it in line with the typical 
--          5-10% industry benchmark. Note: "Lost" represents customers 
--          who are not actively purchasing — but some portion of this 
--          segment may reflect a dataset limitation rather than genuine 
--          churn, since the data has a fixed end date (Dec 2011); a 
--          customer who kept buying after that date would still appear 
--          as inactive here, since no purchases past that point could 
--          ever be recorded.
WITH reference_date AS (
    SELECT MAX(invoice_date) AS max_date FROM transactions_clean
),
rfm_base AS (
    SELECT
        customer_id,
        (SELECT max_date FROM reference_date) - MAX(invoice_date) AS recency,
        COUNT(DISTINCT invoice) AS frequency,
        SUM(quantity * price) AS monetary
    FROM transactions_clean
    WHERE customer_id IS NOT NULL AND invoice NOT LIKE 'C%'
    GROUP BY customer_id
),
rfm_scored AS (
    SELECT
        customer_id,
        recency,
        frequency,
        monetary,
        NTILE(5) OVER (ORDER BY recency DESC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC) AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC) AS m_score
    FROM rfm_base
),
rfm_segmented AS (
    SELECT
        customer_id,
        r_score,
        f_score,
        m_score,
        (f_score + m_score) / 2.0 AS fm_score,
        CASE
            WHEN r_score >= 5 AND (f_score + m_score) / 2.0 >= 4.5 THEN 'Champions'
            WHEN r_score >= 3 AND (f_score + m_score) / 2.0 >= 3 THEN 'Loyal Customers'
            WHEN r_score >= 3 AND (f_score + m_score) / 2.0 >= 2 THEN 'Potential Loyalists'
            WHEN r_score >= 4 THEN 'New Customers'
            WHEN r_score <= 2 AND (f_score + m_score) / 2.0 >= 3 THEN 'At Risk'
            ELSE 'Lost'
        END AS segment
    FROM rfm_scored
)
SELECT segment, COUNT(*)
FROM rfm_segmented
GROUP BY segment
ORDER BY COUNT(*) DESC;