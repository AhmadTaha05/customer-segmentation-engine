-- =============================================
-- Query: Exact Duplicate Row Check
-- Purpose: Identify fully duplicated rows in transactions_raw (all 8 columns identical)
-- Finding: 34,335 redundant rows found (~3.2% of total), spread across 32,907 
--          distinct duplicate groups. These are exact copies of the same 
--          transaction line and should be removed during cleaning to avoid 
--          inflating revenue and order counts.
-- =============================================
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


-- =============================================
-- Query: Null customer_id Count
-- Purpose: Quantify how many rows are missing customer_id in the raw data
-- Finding: 243,007 rows (~22.77% of total) have a null customer_id. This is 
--          too large a share to drop outright, but too large to ignore — 
--          these rows will need to be excluded from any customer-level 
--          analysis (RFM, cohort, churn) while remaining usable for 
--          transaction-level analysis (revenue, product, country trends).
-- =============================================
SELECT COUNT(*) AS null_count,
       ROUND((COUNT(*)::numeric/(SELECT COUNT(*) FROM transactions_raw))* 100.0,2) AS percentage
FROM transactions_raw
WHERE customer_id IS NULL;


-- =============================================
-- Query: Null customer_id Invoice-Level Check
-- Purpose: Determine whether nulls occur inconsistently within an invoice 
--          (row-level error) or consistently across an entire invoice
-- Finding: Zero invoices found with a mix of null and non-null customer_id 
--          rows. Every invoice is either fully null or fully populated, 
--          ruling out row-level system errors as the cause. Whether this 
--          reflects guest checkouts or a whole-transaction system issue is 
--          tested in the next query.
-- =============================================
SELECT  invoice,
        COUNT(customer_id) AS non_null,
        COUNT(*) - COUNT(customer_id) AS nulls
FROM transactions_raw
GROUP BY invoice
HAVING COUNT(customer_id) > 0 AND COUNT(*) - COUNT(customer_id) > 0;


-- =============================================
-- Query: Null customer_id Temporal Pattern
-- Purpose: Determine whether null customer_id rows are randomly distributed 
--          over time (system error) or cluster around specific periods 
--          (business behavior)
-- Finding: Null customer_id rate ranges from ~14% to ~38% by month, with a 
--          clear seasonal spike each December-January (holiday shopping 
--          season), repeating across multiple years. This rules out a 
--          one-time system failure and instead points to more guest 
--          checkouts during high-volume holiday periods.
-- =============================================
SELECT 
    DATE_TRUNC('month', invoice_date::DATE) AS month,
    COUNT(*) AS total_rows,
    COUNT(*) - COUNT(customer_id) AS null_rows,
    ROUND((COUNT(*) - COUNT(customer_id))::numeric / COUNT(*) * 100, 2) AS null_percentage
FROM transactions_raw
GROUP BY DATE_TRUNC('month', invoice_date::DATE)
ORDER BY null_percentage;


-- =============================================
-- Query: Non-Cancelled Rows with Negative Quantity
-- Purpose: Investigate why 3,457 "Normal" (non-C-prefix) invoices show 
--          negative quantity, despite negative quantity being expected 
--          only on cancellation (C-prefix) invoices
-- Finding: All 3,457 of these rows share three traits: null customer_id, 
--          $0 price, and product descriptions like "wet," "rusty," and 
--          "dmg." This pattern doesn't match a real customer return (which 
--          would retain the item's actual price) — it points to internal 
--          inventory write-offs/damaged stock adjustments rather than 
--          actual sales. These rows carry no revenue and no customer 
--          attribution, so they should be dropped during cleaning.
-- =============================================
SELECT
    CASE WHEN invoice LIKE 'C%' THEN 'Cancelled' ELSE 'Normal' END AS invoice_type,
    COUNT(*) FILTER (WHERE quantity::numeric < 0) AS negative_qty_rows,
    COUNT(*) AS total_rows
FROM transactions_raw
GROUP BY CASE WHEN invoice LIKE 'C%' THEN 'Cancelled' ELSE 'Normal' END;

SELECT invoice, stock_code, description, quantity, price, customer_id
FROM transactions_raw
WHERE invoice NOT LIKE 'C%' AND quantity::numeric < 0;

SELECT
    COUNT(*) AS total_normal_negative_qty,
    COUNT(*) FILTER (WHERE customer_id IS NULL) AS null_customer_rows,
    COUNT(*) FILTER (WHERE price::numeric = 0) AS zero_price_rows
FROM transactions_raw
WHERE invoice NOT LIKE 'C%' AND quantity::numeric < 0;


-- =============================================
-- Query: Cancelled Invoice with Non-Negative Quantity
-- Purpose: Investigate the 1 cancelled (C-prefix) invoice that does NOT 
--          have negative quantity, since 19,493 of 19,494 cancelled 
--          invoices did show negative quantity as expected
-- Finding: The one exception (invoice C496350, stock_code 'M') has 
--          description "Manual" and a null customer_id. This is a manual 
--          internal adjustment entry, not a real cancelled sale — it 
--          reused cancellation-style invoice numbering but isn't a 
--          customer transaction. This row will be dropped during cleaning.
-- =============================================
SELECT invoice, stock_code, description, quantity, price, customer_id
FROM transactions_raw
WHERE invoice LIKE 'C%' AND quantity::numeric >= 0;


-- =============================================
-- Query: Non-Standard stock_code Investigation
-- Purpose: Identify stock_code values that don't match the documented 
--          5-digit (+ optional letter) product code format, and determine 
--          whether they represent real products or non-product entries
-- Finding: Non-standard codes split into two distinct groups. (1) Real 
--          products using alternate formats — e.g. DCGS####, gift_0001_##, 
--          79323GR — which have valid descriptions and repeat across 
--          multiple transactions; these are kept. (2) Administrative/
--          internal codes — ADJUST, POST, BANK CHARGES, TEST001, etc. — 
--          representing fees, corrections, and test entries rather than 
--          real product sales; these total 5,830 rows (~0.5% of the 
--          dataset) and will be dropped during cleaning as they carry no 
--          real product/revenue value.
-- =============================================
SELECT COUNT(*)
FROM transactions_raw
WHERE stock_code IN ('ADJUST','ADJUST2','AMAZONFEE','BANK CHARGES','POST','PADS','DOT','CRUK','C2','C3','TEST001','TEST002','SP1002','M','S','GIFT','D','B');


-- =============================================
-- Query: Zero-Price Row Investigation
-- Purpose: Determine why 6,202 rows have price = 0, and whether these 
--          represent real products or are already covered by prior 
--          findings (write-offs, admin codes)
-- Finding: Of 6,202 zero-price rows, 93 overlap with already-flagged 
--          non-product stock_codes (covered by the prior stock_code 
--          finding). The remaining 6,109 have a normal-format (real 
--          product) stock_code, but share a consistent pattern: null 
--          customer_id, null or placeholder ('?') description, and 
--          quantity that is either negative or exactly 1. The exact 
--          business cause could not be conclusively determined with the 
--          columns available, but these rows carry no revenue, no 
--          customer attribution, and largely no product identification — 
--          so they add no value to segmentation or revenue analysis and 
--          will be dropped during cleaning.
-- =============================================
SELECT
    COUNT(*) FILTER (WHERE price::numeric < 0) AS negative_price_rows,
    COUNT(*) FILTER (WHERE price::numeric = 0) AS zero_price_rows,
    COUNT(*) AS total_rows
FROM transactions_raw;

SELECT
    COUNT(*) FILTER (WHERE stock_code ~ '^[0-9]{5}[A-Za-z]?$') AS zero_price_normal_stockcode,
    COUNT(*) FILTER (WHERE stock_code !~ '^[0-9]{5}[A-Za-z]?$') AS zero_price_other_stockcode,
    COUNT(*) AS total_zero_price
FROM transactions_raw
WHERE price::numeric = 0;

SELECT invoice, stock_code, description, quantity, customer_id
FROM transactions_raw
WHERE price::numeric = 0 AND stock_code ~ '^[0-9]{5}[A-Za-z]?$';


-- =============================================
-- Query: Negative Price Row Investigation
-- Purpose: Investigate the 5 rows with negative price, since a negative 
--          price has no valid real-world meaning even for returns
-- Finding: All 5 rows share stock_code 'B', description "Adjust bad debt", 
--          null customer_id, and quantity of 1. "Bad debt" is an 
--          accounting term for adjusting revenue already written off as 
--          uncollectible — this is an internal financial correction, not 
--          a customer transaction. These rows will be dropped during 
--          cleaning.
-- =============================================
SELECT invoice, stock_code, description, quantity, price, customer_id
FROM transactions_raw
WHERE price::numeric < 0;


-- =============================================
-- Query: Country Column Standardization Check
-- Purpose: Review distinct country values for naming inconsistencies, 
--          non-country geographic labels, and placeholder/non-informative 
--          values
-- Finding: Three distinct issues found. (1) Naming inconsistencies for 
--          real countries — e.g. "EIRE" (Ireland) and "RSA" (South 
--          Africa) — to be standardized to their full country name so 
--          revenue doesn't fragment across labels. (2) Real but 
--          non-country geographic labels — "Channel Islands", "West 
--          Indies" — kept as-is; these represent real customers/revenue, 
--          just at a regional rather than country level. (3) Non-
--          informative placeholder values — "Unspecified", "European 
--          Community" — to be standardized to a single "Unknown" label, 
--          since they carry no real geographic information but the row 
--          otherwise remains valid for non-country analysis.
-- =============================================
SELECT DISTINCT country, COUNT(*) AS row_count
FROM transactions_raw
GROUP BY country
ORDER BY country;