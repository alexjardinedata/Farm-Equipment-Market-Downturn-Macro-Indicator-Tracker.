# Farm-Equipment Market Downturn — Macro Indicator Tracker

**Built in BigQuery SQL — four raw U.S. public series cleaned, modeled into a star schema, and turned into a leading-indicator read on an equipment-marketplace business.**

> Public manufacturing and macro data shows the farm-equipment economy down ~22.5% from its 2022 peak but decelerating — a deep-but-flattening contraction, with inventory still backing up relative to shipments. These series sit *upstream* of marketplace listing, auction, and ad-spend volume, so they read as an early signal before the downturn reaches revenue.

**Business question 1 (depth & direction):** How deep is the contraction in the farm-equipment economy that feeds the marketplaces, and is it still deteriorating or starting to stabilize — so pressure on listing volume, auction activity, and dealer ad spend can be anticipated before it shows up in revenue?

**Business question 2 (concentration risk):** How correlated are the revenue verticals, and where are the early-warning thresholds that should trigger budget or sales-effort reallocation?

---

## Project Overview

An equipment marketplace makes money when machines change hands and when dealers pay to advertise inventory. When transaction volume and dealer inventory shrink, that revenue base is directly exposed. This project rebuilds the macro contraction driving that exposure — from raw public data — as a **leading indicator** that precedes the revenue impact by weeks to months.

The supply-chain pattern this project sits on:

> Farm income falls (corn ↓) + borrowing gets expensive (fed funds ↑) → farmers and dealers buy less equipment → manufacturers cut shipments and draw down inventories → fewer machines flow to dealer lots → fewer listings, auctions, and completed transactions → less listing, ad, and auction revenue.

The four public series sit at the **front** of that pattern. The point of the build is to see the macro signal that *coincides with or precedes* a soft quarter, not to describe the downturn after it lands.

**What makes this more than one chart:** the full pipeline — raw inspection, cleaning, a star schema, window-function metrics, and an exploratory lead-lag analysis — is built end-to-end in BigQuery, with every input validated clean before modeling and every headline number reproducible from the SQL.

| | Implementation |
| --- | --- |
| **Sources** | 4 monthly series from FRED (Census M3 + Fed + BLS), CSV |
| **Pipeline** | BigQuery SQL — inspection → cleaning → star schema → window-function metrics → analysis views → lead-lag exploratory |
| **Output** | Interactive dashboard (GitHub Pages) + full query file |

---

## Primary Findings

**1. The contraction is deep — down ~22.5% from the 2022 peak.** Farm-machinery manufacturer inventory (FRED A33ATI) peaked at \$7,225M in October 2022 and stood at \$5,601M in April 2026 — a 22.48% drawdown, a touch deeper than the ~20.8% the published market report cited through December 2025. Pulling the live series forward shows the contraction extended, not reversed.

**2. But it's decelerating, not still falling fast.** Year-over-year change has climbed back from steep double-digit declines to roughly **−1.67%** in the latest month — the signature of a market flattening near a bottom rather than in free-fall.

**3. Stock is backing up relative to flow.** Months-of-inventory (inventory ÷ monthly shipments) sits at **2.22 vs a ~1.81-month ten-year norm** — so even as the dollar level stabilizes, supply is still outpacing shipments. This is the tightest public proxy for transaction-volume pressure heading downstream.

**4. The farm vertical co-moves with broad macro forces — a foothold on concentration risk.** Inventory correlates with shipments (0.86) and corn prices (0.65) on levels; that correlation weakens to 0.25 once both series are detrended to year-over-year change — a material difference in what the number means (see Correlation Note below). The fed-funds rate shows a loose inverse association (−0.19 levels / 0.25 YoY). Because corn prices and rates are economy-wide forces, the same associations plausibly appear across construction, trucking, and aviation equipment too — the pattern behind concentration risk (see caveat below).

**5. Corn prices and inventory show the strongest association at a 9-month offset.** A lead-lag analysis on detrended (YoY) series finds the correlation between corn prices and inventory rises from 0.252 at zero months to a peak of **0.466 at a 9-month offset** — meaning corn prices from nine months earlier are more strongly associated with current inventory levels than contemporaneous corn prices. This is consistent with the hypothesized supply-chain sequence (income → buying decision → order → delivery → inventory), but correlation at a lag does not establish causation.

**Answer to Q1:** the contraction is **deep but decelerating** — meaningful downstream pressure already baked in, with early signs of a bottom rather than continued acceleration.

**Answer to Q2 (partial, honestly):** this build establishes the *pattern and the macro sensitivity* in one vertical. It does not by itself prove cross-vertical concentration risk — that requires running the same pipeline across the other verticals (roadmap below).

---

## Evidence

| Metric | Value | Read |
| --- | --- | --- |
| Inventory drawdown from peak | **−22.48%** (\$7,225M → \$5,601M) | Depth of contraction |
| Latest year-over-year | **−1.67%** | Decelerating toward a bottom |
| Months of inventory | **2.22** vs ~1.81 norm | Supply backing up vs flow |
| Inventory ↔ shipments (levels) | 0.86 | Two faces of the same sector |
| Inventory ↔ corn (levels / YoY) | 0.65 / **0.25** | Association weakens once detrended |
| Inventory ↔ fed funds (levels / YoY) | −0.19 / 0.25 | Loose inverse association |
| Corn ↔ inventory, peak lag (YoY) | **0.466 at 9 months** | Strongest association at 9-month offset |

**Correlation note:** levels correlation is inflated by shared long-run trend. Detrending to year-over-year change is the honest "do they actually co-move month to month" read — and it cuts the inventory↔corn association from 0.65 to 0.25. Both are reported as a pair rather than leading with the higher number. Correlation at any lag is an association finding, not a causal claim.

---

## Lead-Lag Analysis

To test whether upstream macro drivers are associated with downstream inventory *with a delay*, corn prices and the fed funds rate were each shifted backward by 0, 3, 6, 9, and 12 months and correlated with inventory (detrended to YoY throughout).

| Corn → Inventory | lag0 | lag3 | lag6 | lag9 | lag12 |
| --- | --- | --- | --- | --- | --- |
| Correlation (YoY) | 0.252 | 0.360 | 0.430 | **0.466** | 0.443 |

The association rises from lag0 to a peak at 9 months and then falls — a profile consistent with corn prices being associated with inventory levels on a delayed basis rather than coincidentally. The fed-funds rate shows a weaker and flatter profile across all lags. Raw query output: [`data/lead_lag_analysis.csv`](data/lead_lag_analysis.csv).

**Interpretation boundary:** a rising correlation profile at a lag is consistent with the hypothesized supply-chain sequence; it does not establish that corn prices *cause* inventory changes. Economy-wide factors — credit conditions, general investment sentiment, commodity cycles — could simultaneously influence both series. The finding is that the timing offset *aligns with* the mechanism, not that the mechanism is proven.

---

## Scope & Honesty Caveats

These are stated up front because a reader who knows the business will check for them.

- **Manufacturer data, not marketplace data.** A33ATI is *factory/OEM* inventory, not dealer used-equipment inventory and not any platform's listing counts. This measures the macro context of the core markets, not the markets themselves. It is a leading-indicator layer; the natural next step is overlaying internal listing, auction, and ad-spend data to test the association directly.
- **One vertical.** The dataset is agriculture only. Concentration risk (Q2) is the multi-vertical generalization this build *gestures at* but cannot finish. The fed-funds association is the bridge — a force common to all verticals — but one shared driver in one vertical is an *argument* for concentration risk, not a *demonstration*.
- **Inferred revenue linkage.** The pattern from these series to marketplace revenue is inferred from how the business model is described publicly, not confirmed from financials.
- **Seasonal basis.** Inventory and shipments are seasonally adjusted; corn PPI is not — so associations involving corn are read on trend, not month-to-month seasonal noise.
- **Correlation ≠ causation.** All relationships in this project are described as associations or co-movement. No causal claims are made.

---

## How It Was Built

All logic lives in one organized file: [`docs/queries.sql`](docs/queries.sql).

**1. Raw inspection (read-only).** Row counts and date coverage, NULL/non-numeric scan via `SAFE_CAST`, duplicate-date check (`GROUP BY ... HAVING COUNT(*) > 1`), and a month-gap/contiguity check using `LAG()` partitioned by series. All four inputs verified clean: no nulls, no duplicate dates, no gaps.

**2. Cleaning + staging.** Each series cleaned column-by-column (`SAFE_CAST` for defensive numeric coercion, a `reported`/`missing` status flag) and `UNION ALL`-ed into one tidy long fact, `stg_market_long`, keyed by `(series_id, month_date)`. A `QUALIFY ROW_NUMBER()` guard enforces one row per series per month with a deterministic `ORDER BY value DESC` tiebreak.

**3. Star schema.** `dim_date` generated with `GENERATE_DATE_ARRAY` + `UNNEST` (spanning 1954–2026 so no fact row is ever dropped in the join); `dim_series` defined inline as an array of structs. The fact's grain is one row per series per month, with the composite of the two foreign keys as its logical key.

**4. Metric layer (window functions).** `LAG(value,1)` and `LAG(value,12)` for month-over-month and year-over-year; a trailing 3-month `AVG OVER`; an expanding `MAX OVER (... UNBOUNDED PRECEDING ...)` running peak feeding `pct_off_peak` (drawdown); and `FIRST_VALUE` to rebase each series to 100 for cross-series comparison. `SAFE_DIVIDE` throughout so first-period nulls never error.

**5. Analysis views.** `vw_market_long` (fact joined to both dimensions on shared keys via `USING`) feeds line charts and the YoY view; `vw_market_wide` pivots the long fact back out with `MAX(IF(...))` so series sit side-by-side per month — the shape `CORR()` and the scatter need — and derives months-of-inventory inline.

**6. Lead-lag exploratory.** All series detrended to YoY % change. Corn and fed-funds shifted backward by 0, 3, 6, 9, and 12 months using `LAG()`. `CORR()` computed at each offset for four driver→outcome pairs (corn→inventory, corn→shipments, fed-funds→inventory, fed-funds→shipments). Peak association: corn→inventory at lag9 (0.466).

---

## Recommendations & Areas for Further Investigation

**1. Overlay internal listing, auction, and ad-spend data.** *(the version that answers the revenue question directly)* These public series are upstream; the payoff is testing the association against actual marketplace volume. *Needs:* internal listing counts, auction sell-through, dealer ad spend tracked monthly. *Produces:* an early-warning read that flags revenue pressure weeks before the income statement.

**2. Replicate the pipeline across all verticals.** *(connects to concentration risk, Q2)* Pull inventory/shipment series for construction (Census M3 A34-series), trucking (ACT Research / FRED freight), and aviation (GAMA / Census), and test whether they co-move with the same macro drivers. *Needs:* the parallel public series per vertical. *Produces:* a four-vertical co-movement view that turns the concentration-risk argument into a measurement.

**3. Define early-warning thresholds.** *(connects to Q2)* Set trigger levels on months-of-inventory and YoY deceleration that flag when to reallocate budget or sales effort. *Needs:* the multi-vertical build from Rec 2 plus internal revenue-by-vertical history to calibrate. *Produces:* a rules-based reallocation signal instead of a reactive one.

---

## Data Source & Currency

- **Sources:** [FRED](https://fred.stlouisfed.org) — A33ATI (Census M3, farm-machinery inventories), A33AVS (Census M3, farm-machinery shipments), FEDFUNDS (Federal Reserve), WPU012202 (BLS, corn PPI). All monthly, retrieved as CSV.
- **Coverage:** inventory & shipments 1992–2026; corn 1971–2026; fed funds 1954–2026. Headline figures current through April 2026.
- **Limitations:** see Scope & Honesty Caveats above — manufacturer (not marketplace) data, single vertical, inferred revenue linkage, mixed seasonal basis, all relationships are associations not causal findings.

---

## Repository Contents

```
Farm-Equipment-Market-Downturn-Macro-Indicator-Tracker/
├── README.md                                        This file
├── index.html                                       Live dashboard (GitHub Pages)
│
├── data/
│   ├── A33ATI_raw.csv                               FRED: Farm machinery inventories
│   ├── A33AVS_raw.csv                               FRED: Farm machinery shipments
│   ├── FEDFUNDS_raw.csv                             FRED: Federal funds rate
│   ├── WPU012202_raw.csv                            FRED: Corn PPI
│   ├── Build_Clean_stg_market_long.csv              Staging table output
│   ├── Build_dim_date.csv                           Date dimension output
│   ├── Build_dim_series.csv                         Series dimension output
│   ├── Build_fact_market_metrics_MoM_YoY.csv        Metrics layer output
│   ├── Build_vw_market_wide_analysis.csv            Wide-format view output
│   ├── Shape_of_each_raw_table.csv                  Raw inspection results
│   ├── NULL_non-numeric_check.csv                   Null/coercion validation
│   ├── correlation_matrix_on_levels.csv             Correlation — raw levels
│   ├── correlation_on_YoY_percent_change.csv        Correlation — detrended YoY
│   ├── headline_inventory_peak_latest_percent_off_peak.csv   Key headline numbers
│   └── lead_lag_analysis.csv                        Lead-lag query output (all pairs, all lags)
│
├── docs/
│   ├── queries.sql                                  Full BigQuery pipeline (inspection → lead-lag)
│   ├── build_guide.md                               Step-by-step build walkthrough
│   └── README.md                                    Supplementary project notes
│
└── viz/
    └── SH_market_research_project_viz.pbix          Power BI source file (reference)
```

**Live dashboard:** [alexjardinedata.github.io/Farm-Equipment-Market-Downturn-Macro-Indicator-Tracker](https://alexjardinedata.github.io/Farm-Equipment-Market-Downturn-Macro-Indicator-Tracker/)

---

*Part of a data-analysis portfolio. See also: [NCAA Women's Basketball SQL Analysis](https://github.com/alexjardinedata/ncaa-wbb-sql-analysis) · [Nebraska ED Throughput Benchmark](https://github.com/alexjardinedata/nebraska-ed-throughput-benchmark).*
