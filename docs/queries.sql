CREATE OR REPLACE TABLE `my-project-sh-interview-28683.Sandhills_Equipment_Tracker.dim_series` AS
SELECT * FROM UNNEST([
  STRUCT('inventory' AS series_id,
         'Farm Machinery & Equip. Inventories'        AS series_name,
         'USD millions (SA)'                          AS unit,
         'U.S. Census M3 via FRED A33ATI'             AS source,
         'Supply'                                     AS category),
  ('shipments','Farm Machinery & Equip. Value of Shipments','USD millions (SA)','U.S. Census M3 via FRED A33AVS','Supply'),
  ('fed_funds','Federal Funds Effective Rate','percent','FRED FEDFUNDS','Macro / Cost of capital'),
  ('corn_ppi','Corn Producer Price Index','index 1982=100 (NSA)','FRED WPU012202','Demand / Farm income')
]);
