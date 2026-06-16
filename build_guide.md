# Equipment Market Downturn — Macro Indicator Tracker
### Step-by-step build guide (BigQuery + Power BI)

**What this project is:** a small data pipeline that rebuilds — and extends past — the
equipment-market contraction story from Sandhills Global's own market reports, using
four raw public series from FRED. It demonstrates data inspection, cleaning, exploratory
analysis, SQL window functions, and a star-schema model feeding Power BI.

**The four data files** (already downloaded):
`A33ATI.csv` (inventory), `A33AVS.csv` (shipments), `FEDFUNDS.csv` (rate), `WPU012202.csv` (corn PPI)

---

## Step 1 — Create a dataset in BigQuery

1. Open the BigQuery console (console.cloud.google.com/bigquery).
2. In the Explorer panel, click the **⋮** next to your project (you can reuse the
   project from your Bryan build) → **Create dataset**.
3. Dataset ID: **`Sandhills_Equipment_Tracker`**. Location: keep default (US). Click **Create dataset**.

---

## Step 2 — Upload the four CSVs as raw tables

Do this **four times**, once per file. For each one:

1. Click the **⋮** next to the `Sandhills_Equipment_Tracker` dataset → **Create table**.
2. **Source** → *Create table from*: **Upload**. Choose the CSV file.
3. **File format**: CSV.
4. **Table name** — use exactly these (the SQL expects them):

   | CSV file        | Table name      |
   |-----------------|-----------------|
   | A33ATI.csv      | `a33ati_raw`    |
   | A33AVS.csv      | `a33avs_raw`    |
   | FEDFUNDS.csv    | `fedfunds_raw`  |
   | WPU012202.csv   | `wpu012202_raw` |

5. **Schema**: tick **Auto detect**. (Header row becomes column names: `observation_date`
   plus the series code like `A33ATI`.)
6. Expand **Advanced options** → set **Header rows to skip = 1**. Leave the rest default.
7. Click **Create table**. Repeat for all four.

**Quick check after upload:** click each table → **Preview**. `observation_date` should be
type DATE; the value column should be INTEGER (inventory/shipments) or FLOAT (rate/corn).

---

## Step 3 — Point the SQL at your project

1. Open `equipment_market_tracker.sql`.
2. **Find-and-replace** every `your-project-id.Sandhills_Equipment_Tracker`
   with your real `your-actual-project.Sandhills_Equipment_Tracker`.
   (One replace-all does it.)

---

## Step 4 — Run the inspection + EDA (Sections 1–2)

Paste **Section 1** into a query tab and run each statement. You're confirming:
- **1a** row counts/ranges — inventory & shipments **412** rows (1992-01→2026-04),
  fed_funds **863**, corn_ppi **665**.
- **1b** NULL/non-numeric — all **zero**.
- **1c** duplicate dates — **no rows** returned.
- **1d** month gaps — **no rows** returned.

(Section 2's EDA queries read from `stg_market_long` / the views, so run them **after Step 5**.)

---

## Step 5 — Build the model (Sections 3–6, in order)

Run these top to bottom:
- **Section 3** → builds `stg_market_long` (cleaned tidy long fact).
- **Section 4** → builds `dim_date` and `dim_series`.
- **Section 5** → builds `fact_market_metrics` (the window-function metrics).
- **Section 6** → builds `vw_market_long` and `vw_market_wide`.

Then go back and run **Section 2** (EDA) and **Section 7** (sanity checks).

**Verified numbers to confirm you got it right:**
- Inventory peak **7,225** (Oct 2022) → latest **5,601** (Apr 2026) = **−22.48% off peak**.
- Months-of-inventory latest ≈ **2.22** vs ~**1.81** 10-yr avg.
- Correlation (levels): inventory↔corn **0.65**, inventory↔shipments **0.86**.
- Correlation (YoY %): inventory↔corn **0.25** (weaker once detrended — key talking point).

---

## Step 6 — Connect Power BI

1. **Get data** → **Google BigQuery** → sign in.
2. Navigate to your project → `Sandhills_Equipment_Tracker`.
3. Load these objects:
   - `vw_market_long`  (line charts, YoY heatmap, KPI cards)
   - `vw_market_wide`  (scatter / correlation)
   - `dim_date`, `dim_series`  (slicers / relationships)
4. **Import** mode is fine (data is tiny).

**Model (Model view):**
- `dim_date[month_date]` → `vw_market_long[month_date]`  (1-to-many, single direction)
- `dim_series[series_id]` → `vw_market_long[series_id]`  (1-to-many, single direction)
- Mark `dim_date` as a **date table** (`month_date`).

**Suggested visuals:**
- **KPI cards:** latest inventory, % off peak (−22.5%), months-of-inventory.
- **Line chart:** `value` by `month_date`, filtered to `series_id = inventory`; add a
  reference line at the Oct-2022 peak and annotate the drawdown.
- **Multi-line (rebased):** `index_rebased_100` by `month_date`, legend = `series_name` —
  shows all four series on one comparable axis.
- **Heatmap (matrix):** rows = `year`, columns = `month_abbr`, values = `yoy_pct` (color
  scale), filtered to inventory — makes the contraction period pop.
- **Scatter:** from `vw_market_wide`, x = `corn_ppi_idx`, y = `inventory_usd_m`, play axis =
  `month_date`. Caption it with the levels-vs-YoY correlation nuance.

---

## The line for the interview

> "I pulled four public series from FRED — farm-machinery inventory and shipments, the fed
> funds rate, and the corn PPI — cleaned and modeled them into a star schema in BigQuery,
> and rebuilt the core finding from your February market report straight from the raw data:
> inventory is down about 22.5% from its 2022 peak through April. Two things stood out that
> I'd want to dig into with your internal data — months-of-supply is actually running heavier
> than its 10-year norm even as the dollar level falls, and the inventory/corn-price
> relationship is much weaker once you detrend to year-over-year change than the raw levels
> suggest."

That shows: sourcing, cleaning, window functions, star schema, Power BI, *and* the judgment
to know what the public data can't tell you — which is the bridge to their internal data.
