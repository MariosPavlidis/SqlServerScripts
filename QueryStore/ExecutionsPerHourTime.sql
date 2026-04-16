DECLARE @start_time datetime2 = '2026-03-01 00:00:00';
DECLARE @end_time   datetime2 = '2026-03-02 00:00:00';

SELECT
    DATEADD(hour, DATEDIFF(hour, 0, rsi.start_time), 0) AS hour_bucket,
    SUM(rs.count_executions)                             AS executions
FROM sys.query_store_runtime_stats              rs
JOIN sys.query_store_runtime_stats_interval     rsi
    ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
WHERE rsi.start_time >= @start_time
  AND rsi.start_time <  @end_time
GROUP BY DATEADD(hour, DATEDIFF(hour, 0, rsi.start_time), 0)
ORDER BY hour_bucket;