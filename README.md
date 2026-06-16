# Farm-Equipment Market Downturn — Macro Indicator Tracker

**Built in BigQuery SQL — four raw U.S. public series cleaned, modeled into a star schema, and turned into a leading-indicator read on an equipment-marketplace business.**

> Public manufacturing and macro data shows the farm-equipment economy down ~22.5% from its 2022 peak but decelerating — a deep-but-flattening contraction, with inventory still backing up relative to shipments. These series sit *upstream* of marketplace listing, auction, and ad-spend volume, so they read as an early signal before the downturn reaches revenue.

**Business question 1 (depth & direction):** How deep is the contraction in the farm-equipment economy that feeds the marketplaces, and is it still deteriorating or starting to stabilize — so pressure on listing volume, auction activity, and dealer ad spend can be anticipated before it shows up in revenue?

**Business question 2 (concentration risk):** How correlated are the revenue verticals, and where are the early-warning thresholds that should trigger budget or sales-effort reallocation?

---

## Project Overview

An equipment marketplace makes money when machines change hands and when dealers pay to advertise inventory. When transaction volume and dealer inventory shrink, that revenue base is directly exposed. This project rebuilds the macro contraction driving that exposure — from raw public data — as a **leading indicator** that precedes the revenue impact by weeks to months.

The causal chain the project sits on:

> Farm income falls (corn ↓) + borrowing gets expensive (fed funds ↑) → farmers and dealers buy less equipment → manufacturers cut shipments and draw down inventories → fewer machines flow to dealer lots → fewer listings, auctions, and completed transactions → less listing, ad, and auction revenue.

The four public series sit at the **front** of that chain. The point of the build is to see the macro signal that *precedes* a soft quarter, not to describe the downturn after it lands.

**What makes this more than one chart:** the full pipeline — raw inspection, cleaning, a star schema, and window-function metrics — is built end-to-end in BigQuery, with every input validated clean before modeling and every headline number reproducible from the SQL.

| | Implementation |
| --- | --- |
| **Sources** | 4 monthly series from FRED (Census M3 + Fed + BLS), CSV |
| **Pipeline** | BigQuery SQL — inspection → cleaning → star schema → window-function metrics → analysis views |
| **Output** | Interactive dashboard (GitHub Pages) + full query file |

---

## Primary Findings

**1. The contraction is deep — down ~22.5% from the 2022 peak.** Farm-machinery manufacturer inventory (FRED A33ATI) peaked at \$7,225M in October 2022 and stood at \$5,601M in April 2026 — a 22.48% drawdown, a touch deeper than the ~20.8% the published market report cited through December 2025. Pulling the live series forward shows the contraction extended, not reversed.

**2. But it's decelerating, not still falling fast.** Year-over-year change has climbed back from steep double-digit declines to roughly **−1.67%** in the latest month — the signature of a market flattening near a bottom rather than in free-fall. This matches "equipment market hits bottom after a tough year" reporting.

**3. Stock is backing up relative to flow.** Months-of-inventory (inventory ÷ monthly shipments) sits at **2.22 vs a ~1.81-month ten-year norm** — so even as the dollar level stabilizes, supply is still outpacing shipments. This is the tightest public proxy for transaction-volume pressure heading downstream.

**4. The farm vertical responds to broad macro forces — a foothold on concentration risk.** Inventory correlates with shipments (0.86) and corn prices (0.65) on levels, and is weakly inverse to the fed funds rate (−0.19). Because corn and rates are economy-wide forces, the same drivers plausibly act on construction, trucking, and aviation equipment too — the mechanism behind concentration risk (see caveat below).

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
| Inventory ↔ corn (levels / YoY) | 0.65 / **0.25** | Link weakens once detrended |
| Inventory ↔ fed funds (levels / YoY) | −0.19 / 0.25 | Macro sensitivity, loose |

**Correlation note:** levels correlation is inflated by shared long-run trend. Detrending to year-over-year is the honest "do they actually co-move month to month" read — and it cuts the inventory↔corn link from 0.65 to 0.25. Both are reported, as a pair, rather than leading with the flattering number.

---

## Scope & Honesty Caveats

These are stated up front because a reader who knows the business will check for them.

- **Manufacturer data, not marketplace data.** A33ATI is *factory/OEM* inventory, not dealer used-equipment inventory and not any platform's listing counts. This measures the macro **driver** of the core markets, not the markets themselves. It is a leading-indicator layer; the natural next step is overlaying internal listing, auction, and ad-spend data to test the lead-lag relationship directly.
- **One vertical.** The dataset is agriculture only. Concentration risk (Q2) is the multi-vertical generalization this build *gestures at* but cannot finish. The fed-funds correlation is the bridge — a force common to all verticals — but one shared driver in one vertical is an *argument* for concentration risk, not a *demonstration*.
- **Inferred revenue linkage.** The chain from these series to marketplace revenue is inferred from how the business model is described publicly, not confirmed from financials.
- **Seasonal basis.** Inventory and shipments are seasonally adjusted; corn PPI is not — so correlations involving corn are read on trend, not month-to-month seasonal noise.

---

## How It Was Built

All logic lives in one organized file: [`equipment_market_tracker.sql`](equipment_market_tracker.sql).

**1. Raw inspection (read-only).** Row counts and date coverage, NULL/non-numeric scan via `SAFE_CAST`, duplicate-date check (`GROUP BY ... HAVING COUNT(*) > 1`), and a month-gap/contiguity check using `LAG()` partitioned by series. All four inputs verified clean: no nulls, no duplicate dates, no gaps.

**2. Cleaning + staging.** Each series cleaned column-by-column (`SAFE_CAST` for defensive numeric coercion, a `reported`/`missing` status flag) and `UNION ALL`-ed into one tidy long fact, `stg_market_long`, keyed by `(series_id, month_date)`. A `QUALIFY ROW_NUMBER()` guard enforces one row per series per month with a deterministic `ORDER BY value DESC` tiebreak.

**3. Star schema.** `dim_date` generated with `GENERATE_DATE_ARRAY` + `UNNEST` (spanning 1954–2026 so no fact row is ever dropped in the join); `dim_series` defined inline as an array of structs. The fact's grain is one row per series per month, with the composite of the two foreign keys as its logical key.

**4. Metric layer (window functions).** `LAG(value,1)` and `LAG(value,12)` for month-over-month and year-over-year; a trailing 3-month `AVG OVER`; an expanding `MAX OVER (... UNBOUNDED PRECEDING ...)` running peak feeding `pct_off_peak` (drawdown); and `FIRST_VALUE` to rebase each series to 100 for cross-series comparison. `SAFE_DIVIDE` throughout so first-period nulls never error.

**5. Analysis views.** `vw_market_long` (fact joined to both dimensions on shared keys via `USING`) feeds line charts and the YoY view; `vw_market_wide` pivots the long fact back out with `MAX(IF(...))` so series sit side-by-side per month — the shape `CORR()` and the scatter need — and derives months-of-inventory inline.

---

## Recommendations & Areas for Further Investigation

**1. Overlay internal listing, auction, and ad-spend data.** *(the version that answers the revenue question directly)* These public series are upstream; the payoff is testing the lead-lag relationship against actual marketplace volume. *Needs:* internal listing counts, auction sell-through, dealer ad spend tracked monthly. *Produces:* an early-warning read that flags revenue pressure weeks before the income statement.

**2. Replicate the pipeline across all verticals.** *(connects to concentration risk, Q2)* Pull inventory/shipment series for construction (Census M3 A34-series), trucking (ACT Research / FRED freight), and aviation (GAMA / Census), and test whether they co-move with the same macro drivers. *Needs:* the parallel public series per vertical. *Produces:* a four-vertical co-movement view that turns the concentration-risk argument into a measurement.

**3. Define early-warning thresholds.** *(connects to Q2)* Set trigger levels on months-of-inventory and YoY deceleration that flag when to reallocate budget or sales effort. *Needs:* the multi-vertical build from Rec 2 plus internal revenue-by-vertical history to calibrate. *Produces:* a rules-based reallocation signal instead of a reactive one.

---

## Data Source & Currency

- **Sources:** [FRED](https://fred.stlouisfed.org) — A33ATI (Census M3, farm-machinery inventories), A33AVS (Census M3, farm-machinery shipments), FEDFUNDS (Federal Reserve), WPU012202 (BLS, corn PPI). All monthly, retrieved as CSV.
- **Coverage:** inventory & shipments 1992–2026; corn 1971–2026; fed funds 1954–2026. Headline figures current through April 2026.
- **Limitations:** see Scope & Honesty Caveats above — manufacturer (not marketplace) data, single vertical, inferred revenue linkage, mixed seasonal basis.

---

## Repository Contents

```
.
├── README.md
├── index.html                      Interactive dashboard (GitHub Pages)
├── equipment_market_tracker.sql    Full BigQuery pipeline (inspection → views)
└── *.csv                           Cleaned table + analysis query outputs
```

**Live dashboard:** [alexjardinedata.github.io/farm-equipment-market-tracker](https://alexjardinedata.github.io/farm-equipment-market-tracker/)

---

*Part of a data-analysis portfolio. See also: [NCAA Women's Basketball SQL Analysis](https://github.com/alexjardinedata/ncaa-wbb-sql-analysis) · [Nebraska ED Throughput Benchmark](https://github.com/alexjardinedata/nebraska-ed-throughput-benchmark).*
