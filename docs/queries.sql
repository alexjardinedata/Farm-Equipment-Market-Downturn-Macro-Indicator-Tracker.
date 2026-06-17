/* ============================================================================
   FARM-EQUIPMENT MARKET DOWNTURN — MACRO INDICATOR TRACKER
   BigQuery SQL Pipeline
   Project: my-project-sh-interview-28683
   Dataset: Sandhills_Equipment_Tracker
   ----------------------------------------------------------------------------
   EXECUTION ORDER:
     SECTION 1  — Raw table inspection (read-only, run anytime)
     SECTION 2  — Build: stg_market_long
     SECTION 3  — Build: dim_date
     SECTION 4  — Build: dim_series
     SECTION 5  — Build: fact_market_metrics
     SECTION 6  — Build: vw_market_long
     SECTION 7  — Build: vw_market_wide
     SECTION 8  — EDA: descriptive stats (run after Section 2)
     SECTION 9  — Analysis: headline, correlations, lead-lag (run after Sections 5 & 7)
   ============================================================================ */


/* ============================================================================
   SECTION 1 — RAW TABLE INSPECTION
   Read-only checks. Run before building anything to verify inputs are clean.
   Expected results: no nulls, no duplicate dates, no month gaps.
   ============================================================================ */

-- 1a. Shape of each raw table: row count and date range
SELECT 'inventory' AS series,
       COUNT(*) AS n,
       MIN(observation_date) AS first_obs,
       MAX(observation_date) AS last_obs
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.a33ati_raw`

UNION ALL

SELECT 'shipments',
       COUNT(*),
       MIN(observation_date),
       MAX(observation_date)
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.a33avs_raw`

UNION ALL

SELECT 'fed_funds',
       COUNT(*),
       MIN(observation_date),
       MAX(observation_date)
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.fedfunds_raw`

UNION ALL

SELECT 'corn_ppi',
       COUNT(*),
       MIN(observation_date),
       MAX(observation_date)
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.wpu012202_raw`
ORDER BY series;


-- 1b. NULL / non-numeric check: any stray text in value columns or missing dates.
--     Expected: all zeros.
SELECT 'inventory' AS series,
       COUNTIF(SAFE_CAST(A33ATI AS FLOAT64) IS NULL) AS null_or_nonnumeric,
       COUNTIF(observation_date IS NULL)              AS null_dates
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.a33ati_raw`

UNION ALL

SELECT 'shipments',
       COUNTIF(SAFE_CAST(A33AVS AS FLOAT64) IS NULL),
       COUNTIF(observation_date IS NULL)
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.a33avs_raw`

UNION ALL

SELECT 'fed_funds',
       COUNTIF(SAFE_CAST(FEDFUNDS AS FLOAT64) IS NULL),
       COUNTIF(observation_date IS NULL)
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.fedfunds_raw`

UNION ALL

SELECT 'corn_ppi',
       COUNTIF(SAFE_CAST(WPU012202 AS FLOAT64) IS NULL),
       COUNTIF(observation_date IS NULL)
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.wpu012202_raw`;


-- 1c. Duplicate date check across all four series.
--     Expected: zero rows returned (absence of output = no duplicates = pass).
SELECT 'inventory' AS series, observation_date, COUNT(*) AS rows_for_date
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.a33ati_raw`
GROUP BY observation_date HAVING COUNT(*) > 1

UNION ALL

SELECT 'shipments', observation_date, COUNT(*)
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.a33avs_raw`
GROUP BY observation_date HAVING COUNT(*) > 1

UNION ALL

SELECT 'fed_funds', observation_date, COUNT(*)
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.fedfunds_raw`
GROUP BY observation_date HAVING COUNT(*) > 1

UNION ALL

SELECT 'corn_ppi', observation_date, COUNT(*)
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.wpu012202_raw`
GROUP BY observation_date HAVING COUNT(*) > 1
ORDER BY series, observation_date;


-- 1d. Contiguity / gap check: every month should be exactly 1 month after the prior.
--     PARTITION BY series so LAG never crosses the boundary between two tables.
--     Expected: zero rows returned (no missing months = pass).
WITH all_series AS (
  SELECT 'inventory' AS series, observation_date
  FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.a33ati_raw`
  UNION ALL
  SELECT 'shipments', observation_date
  FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.a33avs_raw`
  UNION ALL
  SELECT 'fed_funds', observation_date
  FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.fedfunds_raw`
  UNION ALL
  SELECT 'corn_ppi', observation_date
  FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.wpu012202_raw`
),
seq AS (
  SELECT
    series,
    observation_date,
    LAG(observation_date) OVER (PARTITION BY series ORDER BY observation_date) AS prev_date
  FROM all_series
)
SELECT series, prev_date, observation_date,
       DATE_DIFF(observation_date, prev_date, MONTH) AS gap_months
FROM seq
WHERE prev_date IS NOT NULL
  AND DATE_DIFF(observation_date, prev_date, MONTH) <> 1
ORDER BY series, observation_date;


/* ============================================================================
   SECTION 2 — BUILD: stg_market_long
   Cleans each raw series and UNION ALLs them into one tidy long fact table.
   One row per series per month. Grain enforced by the QUALIFY guard.
   ============================================================================ */

CREATE OR REPLACE TABLE `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.stg_market_long` AS
WITH cleaned AS (

  -- inventory (A33ATI)
  SELECT
    DATE_TRUNC(observation_date, MONTH)             AS month_date,
    'inventory'                                     AS series_id,
    'Farm Machinery & Equip. Inventories'           AS series_name,
    'USD millions (SA)'                             AS unit,
    SAFE_CAST(A33ATI AS FLOAT64)                    AS value,
    CASE WHEN SAFE_CAST(A33ATI AS FLOAT64) IS NULL
         THEN 'missing' ELSE 'reported' END         AS data_status
  FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.a33ati_raw`
  WHERE observation_date IS NOT NULL

  UNION ALL

  -- shipments (A33AVS)
  SELECT
    DATE_TRUNC(observation_date, MONTH),
    'shipments',
    'Farm Machinery & Equip. Value of Shipments',
    'USD millions (SA)',
    SAFE_CAST(A33AVS AS FLOAT64),
    CASE WHEN SAFE_CAST(A33AVS AS FLOAT64) IS NULL THEN 'missing' ELSE 'reported' END
  FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.a33avs_raw`
  WHERE observation_date IS NOT NULL

  UNION ALL

  -- federal funds rate (FEDFUNDS)
  SELECT
    DATE_TRUNC(observation_date, MONTH),
    'fed_funds',
    'Federal Funds Effective Rate',
    'percent',
    SAFE_CAST(FEDFUNDS AS FLOAT64),
    CASE WHEN SAFE_CAST(FEDFUNDS AS FLOAT64) IS NULL THEN 'missing' ELSE 'reported' END
  FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.fedfunds_raw`
  WHERE observation_date IS NOT NULL

  UNION ALL

  -- corn PPI (WPU012202)
  SELECT
    DATE_TRUNC(observation_date, MONTH),
    'corn_ppi',
    'Corn Producer Price Index',
    'index 1982=100 (NSA)',
    SAFE_CAST(WPU012202 AS FLOAT64),
    CASE WHEN SAFE_CAST(WPU012202 AS FLOAT64) IS NULL THEN 'missing' ELSE 'reported' END
  FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.wpu012202_raw`
  WHERE observation_date IS NOT NULL
)
-- Drop missing rows and enforce one row per series per month.
-- ORDER BY value DESC makes the tiebreak deterministic if a duplicate ever appears.
SELECT month_date, series_id, series_name, unit, value, data_status
FROM cleaned
WHERE data_status = 'reported'
QUALIFY ROW_NUMBER() OVER (PARTITION BY series_id, month_date ORDER BY value DESC) = 1;


/* ============================================================================
   SECTION 3 — BUILD: dim_date
   Date dimension at monthly grain. Spans 1954-07 (earliest date across all
   four series, from fed_funds) through 2026-12 so no fact row is dropped
   in the join. Inventory and shipments simply have no data before 1992.
   ============================================================================ */

CREATE OR REPLACE TABLE `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.dim_date` AS
SELECT
  d                       AS month_date,     -- PK, joins to fact_market_metrics.month_date
  EXTRACT(YEAR    FROM d) AS year,
  EXTRACT(QUARTER FROM d) AS quarter,
  EXTRACT(MONTH   FROM d) AS month_num,
  FORMAT_DATE('%b',    d) AS month_abbr,     -- 'Jan' (for heatmap axis labels)
  FORMAT_DATE('%Y-%m', d) AS year_month      -- '2026-04' (sortable label)
FROM UNNEST(GENERATE_DATE_ARRAY(DATE '1954-07-01', DATE '2026-12-01', INTERVAL 1 MONTH)) AS d;


/* ============================================================================
   SECTION 4 — BUILD: dim_series
   Series dimension: one row per series, holding metadata.
   Built inline from a STRUCT array — no source file needed.
   ============================================================================ */

CREATE OR REPLACE TABLE `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.dim_series` AS
SELECT * FROM UNNEST([
  STRUCT('inventory' AS series_id,
         'Farm Machinery & Equip. Inventories'        AS series_name,
         'USD millions (SA)'                          AS unit,
         'U.S. Census M3 via FRED A33ATI'             AS source,
         'Supply'                                     AS category),
  ('shipments', 'Farm Machinery & Equip. Value of Shipments', 'USD millions (SA)', 'U.S. Census M3 via FRED A33AVS', 'Supply'),
  ('fed_funds', 'Federal Funds Effective Rate',               'percent',            'FRED FEDFUNDS',                  'Macro / Cost of capital'),
  ('corn_ppi',  'Corn Producer Price Index',                  'index 1982=100 (NSA)', 'FRED WPU012202',               'Demand / Farm income')
]);


/* ============================================================================
   SECTION 5 — BUILD: fact_market_metrics
   Window-function metric layer. Reads from stg_market_long and adds:
     - LAG(1)  → value_prev_month  (for MoM % change)
     - LAG(12) → value_prev_year   (for YoY % change)
     - Trailing 3-month AVG         (moving average to smooth noise)
     - Expanding MAX                (running peak, for drawdown)
     - FIRST_VALUE                  (series start, for rebasing to 100)
   Outer SELECT computes the derived metrics using SAFE_DIVIDE throughout.
   ============================================================================ */

CREATE OR REPLACE TABLE `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.fact_market_metrics` AS
WITH calc AS (
  SELECT
    series_id,
    month_date,
    value,
    LAG(value, 1)  OVER (PARTITION BY series_id ORDER BY month_date) AS value_prev_month,
    LAG(value, 12) OVER (PARTITION BY series_id ORDER BY month_date) AS value_prev_year,
    AVG(value) OVER (PARTITION BY series_id ORDER BY month_date
                     ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)       AS ma_3m,
    MAX(value) OVER (PARTITION BY series_id ORDER BY month_date
                     ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_peak,
    FIRST_VALUE(value) OVER (PARTITION BY series_id ORDER BY month_date) AS first_value
  FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.stg_market_long`
)
SELECT
  series_id,
  month_date,
  value,
  value_prev_month,
  value_prev_year,
  ROUND(ma_3m, 2)                                            AS ma_3m,
  running_peak,
  SAFE_DIVIDE(value - value_prev_month, value_prev_month)    AS mom_pct,
  SAFE_DIVIDE(value - value_prev_year,  value_prev_year)     AS yoy_pct,
  SAFE_DIVIDE(value - running_peak,     running_peak)        AS pct_off_peak,
  ROUND(SAFE_DIVIDE(value, first_value) * 100, 1)            AS index_rebased_100
FROM calc;


/* ============================================================================
   SECTION 6 — BUILD: vw_market_long
   Joins fact_market_metrics to both dimensions on shared keys (USING).
   Produces a fully-labeled wide row per series per month.
   Feeds line charts, YoY heatmap, and trend visuals.
   ============================================================================ */

CREATE OR REPLACE VIEW `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.vw_market_long` AS
SELECT
  f.month_date,
  d.year, d.quarter, d.month_num, d.month_abbr, d.year_month,
  f.series_id, s.series_name, s.unit, s.category, s.source,
  f.value, f.ma_3m, f.mom_pct, f.yoy_pct, f.pct_off_peak, f.index_rebased_100
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.fact_market_metrics` f
JOIN `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.dim_date`   d USING (month_date)
JOIN `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.dim_series` s USING (series_id);


/* ============================================================================
   SECTION 7 — BUILD: vw_market_wide
   Pivots the long fact into one row per month with each series as a column.
   Uses MAX(IF(...)) pattern — each series produces one non-null value per
   month; MAX ignores NULLs, so it cleanly isolates the one real value.
   Also derives months_of_inventory (inventory ÷ shipments) inline.
   Feeds scatter plot, correlation queries, and lead-lag analysis.
   ============================================================================ */

CREATE OR REPLACE VIEW `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.vw_market_wide` AS
SELECT
  month_date,
  MAX(IF(series_id = 'inventory', value, NULL)) AS inventory_usd_m,
  MAX(IF(series_id = 'shipments', value, NULL)) AS shipments_usd_m,
  MAX(IF(series_id = 'fed_funds', value, NULL)) AS fed_funds_pct,
  MAX(IF(series_id = 'corn_ppi',  value, NULL)) AS corn_ppi_idx,
  SAFE_DIVIDE(
    MAX(IF(series_id = 'inventory', value, NULL)),
    MAX(IF(series_id = 'shipments', value, NULL))
  )                                             AS months_of_inventory
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.stg_market_long`
GROUP BY month_date;


/* ============================================================================
   SECTION 8 — EDA: DESCRIPTIVE STATS
   Run after Section 2 (stg_market_long) is built.
   Produces per-series summary statistics including IQR as a skew-robust
   spread measure alongside stddev.
   ============================================================================ */

SELECT
  series_id,
  COUNT(*)                                            AS n_obs,
  MIN(month_date)                                     AS first_month,
  MAX(month_date)                                     AS last_month,
  ROUND(MIN(value),  2)                               AS min_value,
  ROUND(MAX(value),  2)                               AS max_value,
  ROUND(AVG(value),  2)                               AS mean_value,
  ROUND(APPROX_QUANTILES(value, 100)[OFFSET(50)], 2)  AS median_value,
  ROUND(APPROX_QUANTILES(value, 100)[OFFSET(25)], 2)  AS p25_value,
  ROUND(APPROX_QUANTILES(value, 100)[OFFSET(75)], 2)  AS p75_value,
  ROUND(APPROX_QUANTILES(value, 100)[OFFSET(75)]
      - APPROX_QUANTILES(value, 100)[OFFSET(25)], 2)  AS iqr_value,
  ROUND(STDDEV(value), 2)                             AS stddev_value
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.stg_market_long`
GROUP BY series_id
ORDER BY series_id;


/* ============================================================================
   SECTION 9 — ANALYSIS QUERIES
   Run after Sections 5 (fact_market_metrics) and 7 (vw_market_wide) are built.
   ============================================================================ */

-- 9a. Headline: inventory peak, latest value, and % off peak.
--     QUALIFY ROW_NUMBER() picks the single most-recent row without hard-coding a date.
SELECT
  month_date     AS latest_month,
  value          AS latest_value,
  running_peak   AS peak_value,
  ROUND(pct_off_peak * 100, 2) AS pct_off_peak
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.fact_market_metrics`
WHERE series_id = 'inventory'
QUALIFY ROW_NUMBER() OVER (ORDER BY month_date DESC) = 1;


-- 9b. Correlation matrix on levels.
--     Note: levels correlation is amplified by shared long-run trend.
--     Compare with 9c (detrended) for the honest read.
SELECT
  ROUND(CORR(inventory_usd_m, corn_ppi_idx),    3) AS corr_inv_corn,
  ROUND(CORR(inventory_usd_m, shipments_usd_m), 3) AS corr_inv_shipments,
  ROUND(CORR(inventory_usd_m, fed_funds_pct),   3) AS corr_inv_fedfunds,
  ROUND(CORR(shipments_usd_m, corn_ppi_idx),    3) AS corr_ship_corn
FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.vw_market_wide`;


-- 9c. Correlation on detrended (year-over-year) values.
--     Strips the shared long-run trend so the result reflects genuine
--     month-to-month co-movement rather than shared drift.
WITH yoy AS (
  SELECT month_date, series_id, yoy_pct
  FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.fact_market_metrics`
  WHERE yoy_pct IS NOT NULL
),
wide AS (
  SELECT
    month_date,
    MAX(IF(series_id = 'inventory', yoy_pct, NULL)) AS inv_yoy,
    MAX(IF(series_id = 'corn_ppi',  yoy_pct, NULL)) AS corn_yoy,
    MAX(IF(series_id = 'fed_funds', yoy_pct, NULL)) AS ff_yoy
  FROM yoy
  GROUP BY month_date
)
SELECT
  ROUND(CORR(inv_yoy, corn_yoy), 3) AS corr_inv_corn_yoy,
  ROUND(CORR(inv_yoy, ff_yoy),   3) AS corr_inv_fedfunds_yoy
FROM wide
WHERE inv_yoy IS NOT NULL;


-- 9d. Lead-lag analysis (exploratory).
--     Tests whether upstream macro factors (corn price, fed funds) are
--     associated with equipment series at a time offset.
--     Detrended via YoY % change before shifting. Reads from vw_market_wide.
--     How to read: if the correlation peaks at lag6 or lag9, the association
--     is stronger when the macro factor is shifted earlier by that many months —
--     consistent with a delayed relationship. All results are correlations,
--     not causal estimates.
WITH base AS (
  SELECT
    month_date,
    inventory_usd_m,
    shipments_usd_m,
    corn_ppi_idx,
    fed_funds_pct
  FROM `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.vw_market_wide`
  WHERE inventory_usd_m IS NOT NULL
),
yoy AS (
  SELECT
    month_date,
    SAFE_DIVIDE(inventory_usd_m, LAG(inventory_usd_m, 12) OVER w) - 1 AS inv_yoy,
    SAFE_DIVIDE(shipments_usd_m, LAG(shipments_usd_m, 12) OVER w) - 1 AS ship_yoy,
    SAFE_DIVIDE(corn_ppi_idx,    LAG(corn_ppi_idx,    12) OVER w) - 1 AS corn_yoy,
    SAFE_DIVIDE(fed_funds_pct,   LAG(fed_funds_pct,   12) OVER w) - 1 AS ff_yoy
  FROM base
  WINDOW w AS (ORDER BY month_date)
),
shifted AS (
  SELECT
    month_date,
    inv_yoy,
    ship_yoy,
    corn_yoy                             AS corn_l0,
    LAG(corn_yoy, 3)  OVER w             AS corn_l3,
    LAG(corn_yoy, 6)  OVER w             AS corn_l6,
    LAG(corn_yoy, 9)  OVER w             AS corn_l9,
    LAG(corn_yoy, 12) OVER w             AS corn_l12,
    ff_yoy                               AS ff_l0,
    LAG(ff_yoy, 3)    OVER w             AS ff_l3,
    LAG(ff_yoy, 6)    OVER w             AS ff_l6,
    LAG(ff_yoy, 9)    OVER w             AS ff_l9,
    LAG(ff_yoy, 12)   OVER w             AS ff_l12
  FROM yoy
  WINDOW w AS (ORDER BY month_date)
)
SELECT 'corn -> inventory' AS pair,
  ROUND(CORR(inv_yoy, corn_l0),  3) AS lag0,
  ROUND(CORR(inv_yoy, corn_l3),  3) AS lag3,
  ROUND(CORR(inv_yoy, corn_l6),  3) AS lag6,
  ROUND(CORR(inv_yoy, corn_l9),  3) AS lag9,
  ROUND(CORR(inv_yoy, corn_l12), 3) AS lag12
FROM shifted

UNION ALL

SELECT 'fed_funds -> inventory',
  ROUND(CORR(inv_yoy, ff_l0),  3),
  ROUND(CORR(inv_yoy, ff_l3),  3),
  ROUND(CORR(inv_yoy, ff_l6),  3),
  ROUND(CORR(inv_yoy, ff_l9),  3),
  ROUND(CORR(inv_yoy, ff_l12), 3)
FROM shifted

UNION ALL

SELECT 'corn -> shipments',
  ROUND(CORR(ship_yoy, corn_l0),  3),
  ROUND(CORR(ship_yoy, corn_l3),  3),
  ROUND(CORR(ship_yoy, corn_l6),  3),
  ROUND(CORR(ship_yoy, corn_l9),  3),
  ROUND(CORR(ship_yoy, corn_l12), 3)
FROM shifted
ORDER BY pair;
