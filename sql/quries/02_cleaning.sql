-- Query: Build transactions_clean
-- Purpose: Apply all findings from 01_raw_validation.sql in a single 
--          transformation — remove duplicate and unwanted rows, correct 
--          data types, and standardize the country column
-- Finding: 1,021,361 rows retained from 1,067,371 raw rows (~4.3% dropped), 
--          combining exact duplicates, internal write-offs, non-product 
--          stock codes, and negative/unexplained zero-price rows, with 
--          overlap between these categories. quantity and price cast to 
--          NUMERIC, invoice_date cast to DATE. Country naming 
--          inconsistencies standardized (EIRE→Ireland, RSA→South Africa) 
--          and placeholder values unified to "Unknown". All text columns 
--          trimmed.

CREATE TABLE transactions_clean AS
SELECT DISTINCT
    TRIM(invoice) AS invoice,
    TRIM(stock_code) AS stock_code,
    TRIM(description) AS description,
    quantity::NUMERIC AS quantity,
    invoice_date::DATE AS invoice_date,
    price::NUMERIC AS price,
    customer_id AS customer_id,
    TRIM(CASE country
        WHEN 'EIRE' THEN 'Ireland'
        WHEN 'RSA' THEN 'South Africa'
        WHEN 'Unspecified' THEN 'Unknown'
        WHEN 'European Community' THEN 'Unknown'
        ELSE country
        END) AS country
FROM transactions_raw
WHERE
    -- Exclude negative quantity on non-cancelled invoices (internal write-offs)
    NOT (invoice NOT LIKE 'C%' AND quantity::numeric < 0)

    -- Exclude the manual adjustment row
    AND invoice <> 'C496350'

    -- Exclude non-product stock codes
    AND stock_code NOT IN ('ADJUST','ADJUST2','AMAZONFEE','BANK CHARGES','POST','PADS','DOT','CRUK','C2','C3','TEST001','TEST002','SP1002','M','S','GIFT','D','B')

    -- Exclude zero-price rows with normal-format stock_code (unexplained pattern)
    AND NOT (price::numeric = 0 AND stock_code ~ '^[0-9]{5}[A-Za-z]?$')

    -- Exclude negative price (bad debt adjustments)
    AND price::numeric >= 0


-- 1. Total row count after cleaning
SELECT COUNT(*) FROM transactions_clean;

-- 2. Confirm dropped stock codes are gone
SELECT COUNT(*) FROM transactions_clean WHERE stock_code = 'ADJUST';

-- 3. Confirm country standardization worked
SELECT COUNT(*) FROM transactions_clean WHERE country = 'EIRE';

-- 4. Spot check actual values and types
SELECT invoice_date, quantity, price FROM transactions_clean LIMIT 5;

-- 5. Confirm column data types
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'transactions_clean';



-- Query: Build customer_profiles
-- Purpose: Clean customer_profiles_raw into customer_profiles — 
--          standardize country casing/whitespace, trim customer_tier, 
--          and cast signup_date to a proper DATE type. customer_id and 
--          email_opt_in are intentionally left untouched: orphaned 
--          (non-matching) customer_ids are a join-time concern, not a 
--          cleaning concern, and null email_opt_in values represent 
--          genuinely unknown data that should not be fabricated.
-- Finding: Country values normalized via INITCAP + TRIM, collapsing 57 
--          messy distinct values down to 32 clean ones. This is lower 
--          than transactions_clean's 42 distinct countries — verified 
--          this is not a cleaning bug, but because customer_profiles_raw's 
--          weighted random sampling (6,051 draws) never happened to select 
--          every low-probability country in the first place; the 32-value 
--          ceiling was already present in the raw table before cleaning.
CREATE TABLE customer_profiles AS
SELECT
    customer_id,
    INITCAP(TRIM(country)) AS country,
    signup_date::DATE AS signup_date,
    TRIM(customer_tier) AS customer_tier,
    email_opt_in
FROM customer_profiles_raw;
