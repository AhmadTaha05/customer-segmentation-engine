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

SELECT COUNT(*) AS null_count,
       ROUND((COUNT(*)::numeric/(SELECT COUNT(*) FROM transactions_raw))* 100.0,2) AS percentage
FROM transactions_raw
WHERE customer_id IS NULL;

SELECT  invoice,
        COUNT(customer_id) as non_null,
        COUNT(*) -COUNT(customer_id) as nulls
FROM transactions_raw
GROUP BY invoice
HAVING COUNT(customer_id) > 0 AND COUNT(*) -COUNT(customer_id) > 0