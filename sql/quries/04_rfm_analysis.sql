-- =============================================
-- File: 04_rfm_analysis.sql
-- Purpose: Join transactions_clean with customer_profiles to build the 
--          foundation for RFM (Recency, Frequency, Monetary) scoring.
--          transactions_clean leads the join (LEFT JOIN) since it holds 
--          the actual purchasing behavior RFM depends on; customer_profiles 
--          is supplementary enrichment and may not have a match for every 
--          transaction (guest checkouts, unmatched customer_ids).
-- =============================================

-- =============================================
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
-- =============================================
SELECT *
FROM transactions_clean tc
LEFT JOIN customer_profiles cp ON tc.customer_id = cp.customer_id
LIMIT 50;

-- Row count after join — should match transactions_clean exactly (1,021,361)
SELECT COUNT(*)
FROM transactions_clean tc
LEFT JOIN customer_profiles cp ON tc.customer_id = cp.customer_id;

-- Unmatched rows (includes null customer_id guest checkouts)
SELECT COUNT(*)
FROM transactions_clean tc
LEFT JOIN customer_profiles cp ON tc.customer_id = cp.customer_id
WHERE cp.customer_id IS NULL;

-- Unmatched rows with a real (non-null) customer_id specifically
SELECT COUNT(*)
FROM transactions_clean tc
LEFT JOIN customer_profiles cp ON tc.customer_id = cp.customer_id
WHERE tc.customer_id IS NOT NULL AND cp.customer_id IS NULL;