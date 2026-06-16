# BigQuery SQL Changelog — Farm Equipment Market Downturn Tracker

**Project:** Sandhills Global — Market Indicator Build  
**Purpose:** Rebuild the farm-equipment supply-chain contraction from raw FRED macro data; establish a leading-indicator framework for listing volume, auction activity, and dealer ad-spend pressure.  
**Dataset:** `my-project-sh-interview-28683.Sandhills_Equipment_Tracker`  
**Result:** 22.48% inventory drawdown from 2022 peak; YoY deceleration to −1.67%; inventory↔corn correlation weakens from 0.65 (levels) to 0.25 (YoY detrended); lead-lag peak at 9-month corn→inventory lag (0.466).

---

## 01 — Raw Load

- Loaded four FRED CSV series via BigQuery console upload → `a33ati_raw`, `a33avs_raw`, `fedfunds_raw`, `wpu012202_raw`.
- Settings: auto-detect schema; **Header rows to skip = 1**.
- Column names auto-mapped: `observation_date` (DATE) + series code as value column (e.g., `A33ATI` as FLOAT64).
  - *Different FRED series use different column names; inline code maps them at load time (`A33ATI` → `inventory_usd_m`, etc.) so downstream references are semantic, not series-code-dependent.*
- Coverage verified: inventory & shipments 1992-01 → 2026-04 (412 rows); fed_funds 1954-07 → 2026-04 (863 rows); corn 1971-11 → 2026-04 (665 rows).

---

## 02 — Cleaning & Staging (`stg_market_long`)

- **Numeric coercion:** `SAFE_CAST(value AS FLOAT64)` for all numeric columns.
  - *SAFE_CAST returns null for non-numeric, non-null values instead of failing the query. Defers the "is this a real null or a data error?" decision to downstream inspection.*
- **Column mapping:** each raw table mapped to semantic names during the UNION:
  - `A33ATI` → `inventory_usd_m` (Farm machinery inventories, millions)
  - `A33AVS` → `shipments_usd_m` (Farm machinery shipments, millions)
  - `FEDFUNDS` → `fed_funds_pct` (Federal funds rate, percent)
  - `WPU012202` → `corn_ppi_idx` (Corn PPI, index 1982=100)
- **Data status flag:** `reported`/`missing` for later null-flagging.
- **Tidy long format:** one row per series per month, keyed by `(series_id, month_date)`.
- **Deduplication guard:** `QUALIFY ROW_NUMBER() OVER (PARTITION BY series_id, month_date ORDER BY value DESC) = 1`.
  - *Deterministic tiebreak (ORDER BY value DESC) so duplicate dates within a series prefer the highest value (edge-case defense; all four inputs verified clean, so this never fires in practice).*

---

## 03 — Star Schema: Dimensions

**`dim_date` (time dimension)**
- Generated via `GENERATE_DATE_ARRAY('1954-07-01', '2026-12-31', INTERVAL 1 MONTH)` + `UNNEST()`.
  - *Spans the earliest FRED series (fed_funds, 1954-07) through 2026-12, so no fact row ever drops in a left join. If a new series starts in 1971, it just has nulls for 1954-1970.*
- Grain: one row per month-start date.
- Composite key: `month_date` (primary lookup key).

**`dim_series` (series metadata reference table)**
- Built inline as a `STRUCT` array in the main query, four rows:
  ```
  STRUCT('INV', 'Farm Equipment Inventory', 'USD Millions', 'FRED A33ATI'),
  STRUCT('SHIP', 'Farm Equipment Shipments', 'USD Millions', 'FRED A33AVS'),
  STRUCT('CORN', 'Corn Price Index', '1982=100', 'FRED WPU012202'),
  STRUCT('FF', 'Federal Funds Rate', 'Percent', 'FRED FEDFUNDS')
  ```
- Composite key: `series_id`.
- *Alternative: could be a static reference table in the schema; inline is leaner for a 4-row, rarely-changing reference.*

---

## 04 — Metrics Layer (`fact_market_metrics`)

Window functions applied to calculate month-over-month, year-over-year, rolling averages, and drawdown metrics.

**Month-over-month & year-over-year change:**
- `LAG(value, 1) OVER (PARTITION BY series_id ORDER BY month_date)` → `mom_pct = (value / lag_1 - 1)`
- `LAG(value, 12) OVER (PARTITION BY series_id ORDER BY month_date)` → `yoy_pct = (value / lag_12 - 1)`
  - *Lag-12 avoids seasonal noise; lag-1 shows single-month momentum. Both use `SAFE_DIVIDE` to return null for first periods rather than errors.*

**Running peak & drawdown:**
- `MAX(value) OVER (PARTITION BY series_id ORDER BY month_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)` → `running_peak`
- `pct_off_peak = (value / running_peak - 1)` → ranges from 0 (at peak) to negative (below peak).
  - *For inventory: Oct 2022 peak is 7,225; Apr 2026 value is 5,601; drawdown = −22.48%.*

**3-month trailing average:**
- `AVG(value) OVER (PARTITION BY series_id ORDER BY month_date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)` → `ma_3m`
  - *Smooths month-to-month noise; current month + 2 prior months.*

**Rebase to index (100 = earliest period):**
- `FIRST_VALUE(value) OVER (PARTITION BY series_id ORDER BY month_date) → first_value`
- `index_rebased_100 = value / first_value * 100`
  - *Allows cross-series comparison on one axis despite different units (USD millions vs. percent vs. index).*

---

## 05 — Analysis Views

**`vw_market_long` (tidy format — feeds line charts, YoY heatmap)**
- Fact joined to both dimensions: `fact_market_metrics f USING (series_id) JOIN dim_date d USING (month_date) UNION JOIN dim_series s USING (series_id)`.
- Output columns: `month_date`, `series_id`, `series_name`, `series_unit`, `value`, `yoy_pct`, `mom_pct`, `pct_off_peak`, `ma_3m`, `index_rebased_100`.
- One row per series per month; ready for Tableau/Power BI long-format drags (series as legend, values as measures).

**`vw_market_wide` (pivoted — feeds correlation, scatter)**
- Pivots `stg_market_long` using `MAX(IF(...))` pattern so each series becomes a column, one row per month.
  ```sql
  MAX(IF(series_id = 'INV', value)) AS inventory_usd_m,
  MAX(IF(series_id = 'SHIP', value)) AS shipments_usd_m,
  ...
  ```
- Derives `months_of_inventory = inventory_usd_m / (shipments_usd_m / 1)` inline.
  - *Shipments is monthly; inventory is a stock; months_of_inventory = how many months of current-pace sales the stock would cover.*
- One row per month with all four series side-by-side; grain compatible with `CORR()` aggregation and scatter plots.

---

## 06 — Validation Checks

- **Row count check:** inventory & shipments should have identical date ranges (both from 1992-01 onward).
  - Query: `GROUP BY series_id HAVING COUNT(*)` → INV and SHIP both **412**.
- **NULL / non-numeric scan:** `SAFE_CAST` in staging returns null for any non-numeric value; check how many nulls per series.
  - Query: `GROUP BY series_id HAVING COUNT(*)` vs. `COUNT(value IS NOT NULL)` → **zero nulls** in all four.
- **Duplicate-date check:** ensure one row per series per month.
  - Query: `GROUP BY series_id, month_date HAVING COUNT(*) > 1` → **zero rows** (no duplicates).
- **Date contiguity check:** no gaps in the monthly sequence.
  - Query: `LAG(month_date) OVER (PARTITION BY series_id ORDER BY month_date)` and check `DATE_DIFF(month_date, lag_date, MONTH) = 1` → **all gaps = 1** (contiguous).

---

## 07 — Lead-Lag Exploratory Analysis

Investigates whether upstream macro drivers (corn prices, fed funds) exhibit a lagged correlation with downstream equipment inventory and shipments — testing whether one could serve as an early-warning signal.

**Detrending strategy:**
- All series converted to year-over-year % change (`value / LAG(value, 12) - 1`) **before** correlation.
  - *Raw levels correlation is inflated by shared long-run trend. YoY strips trend and surfaces genuine month-to-month co-movement. E.g., inventory↔corn drops from 0.65 (levels) to 0.25 (YoY) — a material difference in interpretation.*

**Lead shift:**
- Corn and fed-funds shifted backward by 0, 3, 6, 9, 12 months using `LAG(yoy_pct, N)`.
  - `lag0`: same month. `lag3`: does corn 3 months ago correlate with inventory today? Etc.
  - *If corn prices **lead** inventory (the expected direction), correlation rises from lag0 to some peak lag, then falls.*

**Query output (corn → inventory, YoY):**
| Lag | Correlation |
|-----|-------------|
| lag0 | 0.252 |
| lag3 | 0.360 |
| lag6 | 0.430 |
| lag9 | **0.466** (peak) |
| lag12 | 0.443 |

- **Interpretation:** corn prices and inventory are most strongly correlated when corn is shifted ~9 months earlier. This is consistent with a lag in the causal chain (farm income → farmer/dealer buying decisions → equipment shipments → inventory levels), not with them moving together coincidentally.
- **Not causation:** correlation does not imply causation; this is framed as a timing/co-movement finding. A true causal direction would require instrumental variables or a quasi-experimental design (outside this scope).

---

## Decision Log

**Detrending for correlation (Validation 07)**
- *Decision:* Report both levels and YoY correlations, with YoY as the "honest" statistic.
- *Rationale:* Levels correlation captures shared trend (less informative); YoY removes trend (more informative for co-movement). A reader unfamiliar with detrending might anchor on the higher number, so both are shown with a framing note that YoY is the appropriate basis for causal interpretation.

**Months-of-inventory formula (vw_market_wide)**
- *Decision:* `inventory_usd_m / (shipments_usd_m / 1)` — dividing monthly shipments by 1 implicitly treats inventory as a stock covering `N` months of flow.
- *Rationale:* A month-on-month basis; if flow accelerates, months-of-inventory falls (even at the same dollar level) because the stock covers less time. This captures the dynamic the dashboard highlights: inventory is falling **both** as a dollar amount and relative to the pace of sales.

**Lagged correlation peak vs. interpretation**
- *Decision:* Frame the lag-9 peak as a "timing offset" consistent with the causal chain, not as proof of the chain.
- *Rationale:* A 9-month lag between corn prices and inventory makes sense (farmer income → buying decision → shipment order → inventory arrival). But correlation ≠ causation; confounders (general economic cycle, fed policy, credit availability) could drive both. The finding is that the timing aligns with the hypothesized mechanism, not that the mechanism is proven.

---

## Key Numbers (Verified from Query Output CSVs)

| Metric | Value | Read |
|--------|-------|------|
| Inventory peak | \$7,225M (Oct 2022) | Historical high |
| Latest inventory | \$5,601M (Apr 2026) | Current state |
| Drawdown from peak | **−22.48%** | Depth of contraction |
| Latest YoY change | **−1.67%** | Decelerating; near bottom |
| Months of inventory | **2.22** vs. ~1.81 norm | Supply backing up vs. shipments |
| Inventory ↔ Shipments (levels) | **0.86** | Tight co-movement |
| Inventory ↔ Corn (levels / YoY) | **0.65 / 0.25** | Weaker once detrended |
| Inventory ↔ Fed Funds (levels / YoY) | **−0.19 / 0.25** | Loose/weak inverse |
| Corn → Inventory (lag9, YoY) | **0.466** | Peak lead-lag correlation |

---

## Power Query → BigQuery Function Reference

| Concept | BigQuery Implementation |
|---------|------------------------|
| Null-safe type coercion | `SAFE_CAST(... AS FLOAT64)` |
| Series mapping (rename columns) | Inline `CASE WHEN series_id = 'INV' THEN 'inventory_usd_m' ...` in UNION |
| Deduplication | `QUALIFY ROW_NUMBER() OVER (...) = 1` or `SELECT DISTINCT` |
| Month-over-month % change | `(value / LAG(value, 1) OVER (...) - 1)` |
| Year-over-year % change | `(value / LAG(value, 12) OVER (...) - 1)` |
| Running max (drawdown) | `MAX(...) OVER (... UNBOUNDED PRECEDING AND CURRENT ROW)` |
| Lagged correlation (lead-lag) | `LAG(yoy_pct, N) OVER (...)`  then `CORR(...)` |
| Pivot (series → columns) | `MAX(IF(series_id = '...', value))` |
| Correlation matrix | `CORR(...)` with GROUP BY on series pairs |

---

## Revision History

### 2026-06-11
**Added**
- Lead-lag exploratory analysis (Section 07): detrends all series to YoY % change, shifts corn and fed-funds backward by 0/3/6/9/12 months, correlates with inventory/shipments. Finds corn→inventory peak at lag9 (0.466), consistent with a 9-month causal lag in the equipment supply chain. Also tests corn→shipments and fed-funds→inventory for comparison.
- Decision log explaining detrending rationale, months-of-inventory formula, and the causal-claim boundary (correlation observed, causation not proven).

**Changed**
- Updated SQL file to include lead-lag analysis as a standalone section with full documentation.
- Clarified that levels vs. YoY correlation difference (0.65 vs. 0.25 for inventory↔corn) is intentional and material to interpretation.

### 2026-06-09
**Added**
- Initial build: raw load (4 FRED CSVs), staging (`stg_market_long`), star schema (`dim_date`, `dim_series`), metrics layer (`fact_market_metrics` with window functions), analysis views (`vw_market_long`, `vw_market_wide`).
- Validation checks: row counts, nulls, duplicates, date gaps.
- Key verified numbers: inventory drawdown (−22.48%), YoY deceleration (−1.67%), months-of-inventory (2.22 vs. 1.81 norm), correlation matrix (levels and YoY).
