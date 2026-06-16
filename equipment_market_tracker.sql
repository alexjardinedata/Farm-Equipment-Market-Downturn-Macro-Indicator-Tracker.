/* ============================================================================
   SANDHILLS GLOBAL — FARM EQUIPMENT MARKET DOWNTURN TRACKER
   
   Complete BigQuery SQL pipeline: raw inspection → cleaning → star schema →
   metrics → analysis views → lead-lag exploratory analysis → dashboard queries.
   
   Project: Rebuild farm-equipment supply contraction from FRED macro data.
   Result: 22.48% inventory drawdown; YoY deceleration at −1.67%; inventory↔corn
           correlation weakens from 0.65 (levels) to 0.25 (YoY detrended);
           lead-lag peak at 9-month corn→inventory lag (0.466 correlation).
   
   Dataset: my-project-sh-interview-28683.Sandhills_Equipment_Tracker
   Tables: a33ati_raw, a33avs_raw, fedfunds_raw, wpu012202_raw (uploaded CSVs)
   ============================================================================ */

-- ============================================================================
-- SECTION 01: RAW INSPECTION (read-only, validation only)
-- ============================================================================

-- 01a. Row counts and date coverage per series
SELECT
  'A33ATI (Inventory)' AS series,
  COUNT(*) AS row_count,
  MIN(observation_date) AS first_date,
  MAX(observation_date) AS latest_date,
  COUNT(DISTINCT observation_date) AS unique_dates
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.a33ati_raw`
UNION ALL
SELECT
  'A33AVS (Shipments)',
  COUNT(*),
  MIN(observation_date),
  MAX(observation_date),
  COUNT(DISTINCT observation_date)
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.a33avs_raw`
UNION ALL
SELECT
  'FEDFUNDS (Fed Rate)',
  COUNT(*),
  MIN(observation_date),
  MAX(observation_date),
  COUNT(DISTINCT observation_date)
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.fedfunds_raw`
UNION ALL
SELECT
  'WPU012202 (Corn PPI)',
  COUNT(*),
  MIN(observation_date),
  MAX(observation_date),
  COUNT(DISTINCT observation_date)
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.wpu012202_raw`
ORDER BY series;

-- 01b. NULL and non-numeric check
SELECT
  'A33ATI' AS series,
  COUNT(*) AS total_rows,
  COUNT(A33ATI) AS non_null_values,
  COUNT(CASE WHEN SAFE_CAST(A33ATI AS FLOAT64) IS NULL THEN 1 END) AS cast_to_null
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.a33ati_raw`
UNION ALL
SELECT
  'A33AVS',
  COUNT(*),
  COUNT(A33AVS),
  COUNT(CASE WHEN SAFE_CAST(A33AVS AS FLOAT64) IS NULL THEN 1 END)
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.a33avs_raw`
UNION ALL
SELECT
  'FEDFUNDS',
  COUNT(*),
  COUNT(FEDFUNDS),
  COUNT(CASE WHEN SAFE_CAST(FEDFUNDS AS FLOAT64) IS NULL THEN 1 END)
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.fedfunds_raw`
UNION ALL
SELECT
  'WPU012202',
  COUNT(*),
  COUNT(WPU012202),
  COUNT(CASE WHEN SAFE_CAST(WPU012202 AS FLOAT64) IS NULL THEN 1 END)
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.wpu012202_raw`
ORDER BY series;

-- 01c. Duplicate date check per series
SELECT
  'A33ATI' AS series,
  COUNT(*) AS duplicate_date_groups
FROM (
  SELECT observation_date, COUNT(*) AS cnt
  FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.a33ati_raw`
  GROUP BY observation_date
  HAVING cnt > 1
)
UNION ALL
SELECT
  'A33AVS',
  COUNT(*)
FROM (
  SELECT observation_date, COUNT(*) AS cnt
  FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.a33avs_raw`
  GROUP BY observation_date
  HAVING cnt > 1
)
UNION ALL
SELECT
  'FEDFUNDS',
  COUNT(*)
FROM (
  SELECT observation_date, COUNT(*) AS cnt
  FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.fedfunds_raw`
  GROUP BY observation_date
  HAVING cnt > 1
)
UNION ALL
SELECT
  'WPU012202',
  COUNT(*)
FROM (
  SELECT observation_date, COUNT(*) AS cnt
  FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.wpu012202_raw`
  GROUP BY observation_date
  HAVING cnt > 1
);

-- 01d. Month-gap check for contiguity
WITH gaps AS (
  SELECT
    'A33ATI' AS series,
    observation_date,
    LAG(observation_date) OVER (ORDER BY observation_date) AS prior_date,
    DATE_DIFF(observation_date, LAG(observation_date) OVER (ORDER BY observation_date), MONTH) AS month_gap
  FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.a33ati_raw`
)
SELECT
  series,
  COUNT(*) AS gap_count,
  COUNT(DISTINCT month_gap) AS unique_gap_sizes,
  MIN(month_gap) AS min_gap,
  MAX(month_gap) AS max_gap
FROM gaps
WHERE prior_date IS NOT NULL
GROUP BY series
ORDER BY series;

-- ============================================================================
-- SECTION 02: BUILD STAGING TABLE (stg_market_long)
-- Cleans and unions all four raw series into one tidy long fact.
-- ============================================================================

CREATE OR REPLACE TABLE `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.stg_market_long` AS
SELECT
  'INV' AS series_id,
  observation_date AS month_date,
  SAFE_CAST(A33ATI AS FLOAT64) AS value,
  CASE WHEN A33ATI IS NULL THEN 'missing' ELSE 'reported' END AS data_status
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.a33ati_raw`
WHERE A33ATI IS NOT NULL

UNION ALL
SELECT
  'SHIP',
  observation_date,
  SAFE_CAST(A33AVS AS FLOAT64),
  CASE WHEN A33AVS IS NULL THEN 'missing' ELSE 'reported' END
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.a33avs_raw`
WHERE A33AVS IS NOT NULL

UNION ALL
SELECT
  'CORN',
  observation_date,
  SAFE_CAST(WPU012202 AS FLOAT64),
  CASE WHEN WPU012202 IS NULL THEN 'missing' ELSE 'reported' END
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.wpu012202_raw`
WHERE WPU012202 IS NOT NULL

UNION ALL
SELECT
  'FF',
  observation_date,
  SAFE_CAST(FEDFUNDS AS FLOAT64),
  CASE WHEN FEDFUNDS IS NULL THEN 'missing' ELSE 'reported' END
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.fedfunds_raw`
WHERE FEDFUNDS IS NOT NULL

QUALIFY ROW_NUMBER() OVER (PARTITION BY series_id, month_date ORDER BY value DESC) = 1
;

-- ============================================================================
-- SECTION 03: BUILD STAR SCHEMA DIMENSIONS
-- ============================================================================

-- 03a. dim_date: one row per month, 1954-07 through 2026-12
CREATE OR REPLACE TABLE `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.dim_date` AS
SELECT
  month_date,
  EXTRACT(YEAR FROM month_date) AS year,
  EXTRACT(MONTH FROM month_date) AS month,
  FORMAT_DATE('%b', month_date) AS month_abbr,
  FORMAT_DATE('%Y-%m', month_date) AS year_month
FROM
  UNNEST(GENERATE_DATE_ARRAY('1954-07-01', '2026-12-01', INTERVAL 1 MONTH)) AS month_date
;

-- 03b. dim_series: four-row reference table (inline STRUCT array)
CREATE OR REPLACE TABLE `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.dim_series` AS
SELECT * FROM UNNEST([
  STRUCT('INV' AS series_id, 'Farm Equipment Inventory' AS series_name, 'USD Millions' AS unit, 'FRED A33ATI' AS source),
  STRUCT('SHIP', 'Farm Equipment Shipments', 'USD Millions', 'FRED A33AVS'),
  STRUCT('CORN', 'Corn Price Index', '1982=100', 'FRED WPU012202'),
  STRUCT('FF', 'Federal Funds Rate', 'Percent', 'FRED FEDFUNDS')
])
;

-- ============================================================================
-- SECTION 04: BUILD METRICS LAYER (fact_market_metrics)
-- Window functions: MoM, YoY, 3-month MA, running peak, drawdown, rebase.
-- ============================================================================

CREATE OR REPLACE TABLE `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.fact_market_metrics` AS
WITH base AS (
  SELECT
    series_id,
    month_date,
    value,
    data_status
  FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.stg_market_long`
)
SELECT
  series_id,
  month_date,
  value,
  data_status,
  -- Month-over-month % change
  SAFE_DIVIDE(value, LAG(value, 1) OVER (PARTITION BY series_id ORDER BY month_date)) - 1 AS mom_pct,
  -- Year-over-year % change (detrended)
  SAFE_DIVIDE(value, LAG(value, 12) OVER (PARTITION BY series_id ORDER BY month_date)) - 1 AS yoy_pct,
  -- 3-month trailing moving average
  AVG(value) OVER (PARTITION BY series_id ORDER BY month_date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS ma_3m,
  -- Running peak (expanding window)
  MAX(value) OVER (PARTITION BY series_id ORDER BY month_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_peak,
  -- Percent off peak (drawdown)
  SAFE_DIVIDE(value, MAX(value) OVER (PARTITION BY series_id ORDER BY month_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)) - 1 AS pct_off_peak,
  -- Rebase to index (first value = 100)
  SAFE_DIVIDE(value, FIRST_VALUE(value) OVER (PARTITION BY series_id ORDER BY month_date)) * 100 AS index_rebased_100
FROM base
ORDER BY series_id, month_date
;

-- ============================================================================
-- SECTION 05: BUILD ANALYSIS VIEWS
-- ============================================================================

-- 05a. vw_market_long: tidy format for line charts, YoY heatmap, etc.
CREATE OR REPLACE VIEW `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.vw_market_long` AS
SELECT
  f.month_date,
  f.series_id,
  s.series_name,
  s.unit,
  s.source,
  f.value,
  f.mom_pct,
  f.yoy_pct,
  f.pct_off_peak,
  f.ma_3m,
  f.index_rebased_100,
  f.data_status
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.fact_market_metrics` f
USING (series_id)
JOIN `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.dim_series` s
  USING (series_id)
JOIN `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.dim_date` d
  USING (month_date)
ORDER BY series_id, month_date
;

-- 05b. vw_market_wide: pivoted format for correlation, scatter plots
CREATE OR REPLACE VIEW `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.vw_market_wide` AS
SELECT
  month_date,
  MAX(IF(series_id = 'INV', value)) AS inventory_usd_m,
  MAX(IF(series_id = 'SHIP', value)) AS shipments_usd_m,
  MAX(IF(series_id = 'CORN', value)) AS corn_ppi_idx,
  MAX(IF(series_id = 'FF', value)) AS fed_funds_pct,
  -- Derived: months of inventory (stock / monthly flow)
  SAFE_DIVIDE(MAX(IF(series_id = 'INV', value)), MAX(IF(series_id = 'SHIP', value))) AS months_of_inventory,
  -- YoY percent changes
  MAX(IF(series_id = 'INV', yoy_pct)) AS inv_yoy_pct,
  MAX(IF(series_id = 'SHIP', yoy_pct)) AS ship_yoy_pct,
  MAX(IF(series_id = 'CORN', yoy_pct)) AS corn_yoy_pct,
  MAX(IF(series_id = 'FF', yoy_pct)) AS ff_yoy_pct
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.fact_market_metrics`
GROUP BY month_date
ORDER BY month_date
;

-- ============================================================================
-- SECTION 06: VALIDATION & SANITY CHECKS
-- ============================================================================

-- 06a. Verify no nulls in stg_market_long
SELECT
  series_id,
  COUNT(*) AS total_rows,
  COUNT(value) AS non_null_values,
  COUNT(CASE WHEN value IS NULL THEN 1 END) AS null_count
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.stg_market_long`
GROUP BY series_id
ORDER BY series_id;

-- 06b. Verify no duplicate (series_id, month_date) pairs
SELECT
  'stg_market_long duplicate check' AS check_name,
  COUNT(*) AS duplicate_key_count
FROM (
  SELECT series_id, month_date, COUNT(*) AS cnt
  FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.stg_market_long`
  GROUP BY series_id, month_date
  HAVING cnt > 1
);

-- 06c. Headline numbers: inventory peak, latest, drawdown
SELECT
  'Inventory Peak' AS metric,
  MAX(value) AS value,
  NULL AS secondary,
  'Oct 2022' AS note
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.fact_market_metrics`
WHERE series_id = 'INV'
UNION ALL
SELECT
  'Inventory Latest',
  (SELECT value FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.fact_market_metrics`
   WHERE series_id = 'INV' ORDER BY month_date DESC LIMIT 1),
  NULL,
  'Apr 2026'
UNION ALL
SELECT
  'Drawdown from Peak',
  NULL,
  (SELECT ROUND(
     (SELECT value FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.fact_market_metrics`
      WHERE series_id = 'INV' ORDER BY month_date DESC LIMIT 1)
     / MAX(value) - 1, 4)
   FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.fact_market_metrics`
   WHERE series_id = 'INV'),
  '-22.48%'
;

-- 06d. Latest YoY by series
SELECT
  series_id,
  month_date,
  ROUND(yoy_pct, 4) AS latest_yoy_pct
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.fact_market_metrics`
WHERE (series_id, month_date) IN (
  SELECT series_id, MAX(month_date)
  FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.fact_market_metrics`
  GROUP BY series_id
)
ORDER BY series_id;

-- ============================================================================
-- SECTION 07: CORRELATION MATRIX (levels and YoY detrended)
-- ============================================================================

-- 07a. Correlation matrix on raw levels
SELECT
  'INV-SHIP (levels)' AS pair,
  ROUND(CORR(inventory_usd_m, shipments_usd_m), 3) AS correlation
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.vw_market_wide`
WHERE inventory_usd_m IS NOT NULL AND shipments_usd_m IS NOT NULL
UNION ALL
SELECT
  'INV-CORN (levels)',
  ROUND(CORR(inventory_usd_m, corn_ppi_idx), 3)
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.vw_market_wide`
WHERE inventory_usd_m IS NOT NULL AND corn_ppi_idx IS NOT NULL
UNION ALL
SELECT
  'INV-FF (levels)',
  ROUND(CORR(inventory_usd_m, fed_funds_pct), 3)
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.vw_market_wide`
WHERE inventory_usd_m IS NOT NULL AND fed_funds_pct IS NOT NULL
UNION ALL
SELECT
  'INV-SHIP (YoY detrended)',
  ROUND(CORR(inv_yoy_pct, ship_yoy_pct), 3)
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.vw_market_wide`
WHERE inv_yoy_pct IS NOT NULL AND ship_yoy_pct IS NOT NULL
UNION ALL
SELECT
  'INV-CORN (YoY detrended)',
  ROUND(CORR(inv_yoy_pct, corn_yoy_pct), 3)
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.vw_market_wide`
WHERE inv_yoy_pct IS NOT NULL AND corn_yoy_pct IS NOT NULL
UNION ALL
SELECT
  'INV-FF (YoY detrended)',
  ROUND(CORR(inv_yoy_pct, ff_yoy_pct), 3)
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.vw_market_wide`
WHERE inv_yoy_pct IS NOT NULL AND ff_yoy_pct IS NOT NULL
ORDER BY pair;

-- ============================================================================
-- SECTION 08: LEAD-LAG EXPLORATORY ANALYSIS
-- Do upstream drivers (corn, fed funds) move BEFORE equipment inventory/shipments?
-- Tests whether they could serve as early-warning signals.
--
-- METHOD: All series detrended to YoY % change (removes shared long-run trend),
--         then drivers are shifted backward by 0, 3, 6, 9, 12 months using LAG.
--         If a driver LEADS, correlation should rise from lag0 to some peak lag,
--         then fall (a profile indicating the driver predicts the outcome with a delay).
--
-- INTERPRETATION: Positive lag = driver shifted earlier in time (e.g., lag9 means
--                 "does corn from 9 months ago correlate with inventory today?").
--                 A peak at lag9 = corn prices lead inventory by ~9 months.
-- ============================================================================

WITH base AS (
  -- Pull wide view, restrict to overlap window where inventory exists
  SELECT
    month_date,
    inventory_usd_m,
    shipments_usd_m,
    corn_ppi_idx,
    fed_funds_pct
  FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.vw_market_wide`
  WHERE inventory_usd_m IS NOT NULL
),
yoy_detrended AS (
  -- Convert all to YoY % change (strips shared long-run trend)
  SELECT
    month_date,
    SAFE_DIVIDE(inventory_usd_m, LAG(inventory_usd_m, 12) OVER w) - 1 AS inv_yoy,
    SAFE_DIVIDE(shipments_usd_m, LAG(shipments_usd_m, 12) OVER w) - 1 AS ship_yoy,
    SAFE_DIVIDE(corn_ppi_idx, LAG(corn_ppi_idx, 12) OVER w) - 1 AS corn_yoy,
    SAFE_DIVIDE(fed_funds_pct, LAG(fed_funds_pct, 12) OVER w) - 1 AS ff_yoy
  FROM base
  WINDOW w AS (ORDER BY month_date)
),
shifted_drivers AS (
  -- Shift drivers backward by N months so they "lead" the outcome series
  -- LAG(driver, N) puts the driver-from-N-months-ago on today's row
  SELECT
    month_date,
    inv_yoy,
    ship_yoy,
    -- Corn at various lags (testing if corn leads inventory/shipments)
    corn_yoy AS corn_lag0,
    LAG(corn_yoy, 3) OVER w AS corn_lag3,
    LAG(corn_yoy, 6) OVER w AS corn_lag6,
    LAG(corn_yoy, 9) OVER w AS corn_lag9,
    LAG(corn_yoy, 12) OVER w AS corn_lag12,
    -- Fed funds at various lags (testing if rate changes lead inventory)
    ff_yoy AS ff_lag0,
    LAG(ff_yoy, 3) OVER w AS ff_lag3,
    LAG(ff_yoy, 6) OVER w AS ff_lag6,
    LAG(ff_yoy, 9) OVER w AS ff_lag9,
    LAG(ff_yoy, 12) OVER w AS ff_lag12
  FROM yoy_detrended
  WINDOW w AS (ORDER BY month_date)
)
-- Output: correlation at each lag for each driver-outcome pair
SELECT
  'corn → inventory' AS driver_outcome,
  ROUND(CORR(inv_yoy, corn_lag0), 3) AS lag0,
  ROUND(CORR(inv_yoy, corn_lag3), 3) AS lag3,
  ROUND(CORR(inv_yoy, corn_lag6), 3) AS lag6,
  ROUND(CORR(inv_yoy, corn_lag9), 3) AS lag9,
  ROUND(CORR(inv_yoy, corn_lag12), 3) AS lag12
FROM shifted_drivers
WHERE inv_yoy IS NOT NULL AND corn_lag12 IS NOT NULL
UNION ALL
SELECT
  'corn → shipments',
  ROUND(CORR(ship_yoy, corn_lag0), 3),
  ROUND(CORR(ship_yoy, corn_lag3), 3),
  ROUND(CORR(ship_yoy, corn_lag6), 3),
  ROUND(CORR(ship_yoy, corn_lag9), 3),
  ROUND(CORR(ship_yoy, corn_lag12), 3)
FROM shifted_drivers
WHERE ship_yoy IS NOT NULL AND corn_lag12 IS NOT NULL
UNION ALL
SELECT
  'fed_funds → inventory',
  ROUND(CORR(inv_yoy, ff_lag0), 3),
  ROUND(CORR(inv_yoy, ff_lag3), 3),
  ROUND(CORR(inv_yoy, ff_lag6), 3),
  ROUND(CORR(inv_yoy, ff_lag9), 3),
  ROUND(CORR(inv_yoy, ff_lag12), 3)
FROM shifted_drivers
WHERE inv_yoy IS NOT NULL AND ff_lag12 IS NOT NULL
UNION ALL
SELECT
  'fed_funds → shipments',
  ROUND(CORR(ship_yoy, ff_lag0), 3),
  ROUND(CORR(ship_yoy, ff_lag3), 3),
  ROUND(CORR(ship_yoy, ff_lag6), 3),
  ROUND(CORR(ship_yoy, ff_lag9), 3),
  ROUND(CORR(ship_yoy, ff_lag12), 3)
FROM shifted_drivers
WHERE ship_yoy IS NOT NULL AND ff_lag12 IS NOT NULL
ORDER BY driver_outcome;

-- ============================================================================
-- SECTION 09: DASHBOARD PREP QUERIES
-- ============================================================================

-- 09a. KPI cards: latest inventory, % off peak, months of inventory
SELECT
  'Latest Inventory' AS metric,
  ROUND((SELECT value FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.fact_market_metrics`
         WHERE series_id = 'INV' ORDER BY month_date DESC LIMIT 1), 0) AS value,
  'USD Millions' AS unit
UNION ALL
SELECT
  '% Off Peak',
  ROUND((SELECT pct_off_peak FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.fact_market_metrics`
         WHERE series_id = 'INV' ORDER BY month_date DESC LIMIT 1) * 100, 2),
  'Percent'
UNION ALL
SELECT
  'Months of Inventory',
  ROUND((SELECT months_of_inventory FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.vw_market_wide`
         WHERE months_of_inventory IS NOT NULL ORDER BY month_date DESC LIMIT 1), 2),
  'Months'
;

-- 09b. Multi-series line (rebased to index 100)
SELECT
  month_date,
  series_id,
  series_name,
  ROUND(index_rebased_100, 2) AS index_value
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.vw_market_long`
WHERE month_date >= '2020-01-01'
ORDER BY series_id, month_date;

-- 09c. Scatter (inventory vs. corn) for correlation viz
SELECT
  month_date,
  inventory_usd_m,
  corn_ppi_idx,
  ROUND(months_of_inventory, 2) AS months_of_inventory
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.vw_market_wide`
WHERE inventory_usd_m IS NOT NULL AND corn_ppi_idx IS NOT NULL
ORDER BY month_date;
