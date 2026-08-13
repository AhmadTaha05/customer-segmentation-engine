-- Query: Exact Duplicate Row Check
-- Purpose: Identify fully duplicated rows in transactions_raw (all 8 columns identical)
-- Finding: 34,335 redundant rows found (~3.2% of total), spread across 32,907 
--          distinct duplicate groups. These are exact copies of the same 
--          transaction line and should be removed during cleaning to avoid 
--          inflating revenue and order counts.

WITH find_duplicates AS (
    SELECT invoice, stock_code, description, quantity, invoice_date, price, customer_id, country,
           COUNT(*) AS times_repeated
    FROM transactions_raw
    GROUP BY invoice, stock_code, description, quantity, invoice_date, price, customer_id, country
    HAVING COUNT(*) > 1
)
SELECT 
    COUNT(*) AS duplicate_groups,
    SUM(times_repeated - 1) AS redundant_rows
FROM find_duplicates;


-- Query: Null customer_id Count
-- Purpose: Quantify how many rows are missing customer_id in the raw data
-- Finding: 243,007 rows (~22.77% of total) have a null customer_id. This is 
--          too large a share to drop outright, but too large to ignore — 
--          these rows will need to be excluded from any customer-level 
--          analysis (RFM, cohort, churn) while remaining usable for 
--          transaction-level analysis (revenue, product, country trends).
SELECT COUNT(*) AS null_count,
       ROUND((COUNT(*)::numeric/(SELECT COUNT(*) FROM transactions_raw))* 100.0,2) AS percentage
FROM transactions_raw
WHERE customer_id IS NULL;


-- Query: Null customer_id Invoice-Level Check
-- Purpose: Determine whether nulls occur inconsistently within an invoice 
--          (row-level error) or consistently across an entire invoice
-- Finding: Zero invoices found with a mix of null and non-null customer_id 
--          rows. Every invoice is either fully null or fully populated, 
--          ruling out row-level system errors as the cause. Whether this 
--          reflects guest checkouts or a whole-transaction system issue is 
--          tested in the next query.
SELECT  invoice,
        COUNT(customer_id) as non_null,
        COUNT(*) -COUNT(customer_id) as nulls
FROM transactions_raw
GROUP BY invoice
HAVING COUNT(customer_id) > 0 AND COUNT(*) -COUNT(customer_id) > 0;


-- Query: Null customer_id Temporal Pattern
-- Purpose: Determine whether null customer_id rows are randomly distributed 
--          over time (system error) or cluster around specific periods 
--          (business behavior)
-- Finding: Null customer_id rate ranges from ~14% to ~38% by month, with a 
--          clear seasonal spike each December-January (holiday shopping 
--          season), repeating across multiple years. This rules out a 
--          one-time system failure and instead points to more guest 
--          checkouts during high-volume holiday periods.
SELECT 
    DATE_TRUNC('month', invoice_date::DATE) AS month,
    COUNT(*) AS total_rows,
    COUNT(*) - COUNT(customer_id) AS null_rows,
    ROUND((COUNT(*) - COUNT(customer_id))::numeric / COUNT(*) * 100, 2) AS null_percentage
FROM transactions_raw
GROUP BY DATE_TRUNC('month', invoice_date::DATE)
ORDER BY null_percentage;

