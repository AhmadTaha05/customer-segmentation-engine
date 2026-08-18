-- Query: Orphaned customer_id Check
-- Purpose: Verify how many customer_ids in customer_profiles_raw do not 
--          exist in transactions_clean (expected: ~176 intentionally 
--          injected fake IDs)
-- Finding: found exactly 176 orphaned customer_ids, matching the intentional 
--          fake-ID injection confirming the synthetic generation 
--          logic worked correctly.
SELECT COUNT(*) AS orphaned_customer_count
FROM customer_profiles_raw cp
LEFT JOIN transactions_clean tc ON cp.customer_id = tc.customer_id
WHERE tc.customer_id IS NULL;

-- Query: Country Value Distinct Count Comparison
-- Purpose: Compare distinct country count in customer_profiles_raw against 
--          the clean baseline in transactions_clean, to confirm intentional 
--          casing/whitespace messiness is present and measurable
-- Finding: transactions_clean has 42 distinct clean country values. 
--          customer_profiles_raw has 57 — the extra 15 are casing/whitespace 
--          variants of real countries (e.g. "France", "FRANCE", " France " 
--          all counted separately). Confirms the intentional country 
--          messiness injection is present and will need standardization 
--          during cleaning, same approach used for transactions_clean.
SELECT COUNT(DISTINCT country) FROM transactions_clean;
SELECT COUNT(DISTINCT country) FROM customer_profiles_raw;


-- Query: email_opt_in Null Verification
-- Purpose: Confirm the intentional ~10% null injection in email_opt_in 
--          landed correctly in the loaded Postgres table
-- Finding: 607 of 6,051 rows (~10.03%) have a null email_opt_in, matching 
--          the intended 10% null rate from generation. Injection confirmed 
--          successful.
SELECT COUNT(*) FROM customer_profiles_raw WHERE email_opt_in IS NULL;