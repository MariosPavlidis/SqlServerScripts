	SELECT
    sh.object_id,
    sh.stats_id,
    sh.step_number,
    sh.range_high_key,
    sh.range_rows,
    sh.equal_rows,
    sh.distinct_range_rows,
    sh.average_range_rows
FROM sys.dm_db_stats_histogram
(
    OBJECT_ID(N'dbo.StockKeepingUnits'),
    1   -- stats_id
) AS sh
ORDER BY sh.step_number; 