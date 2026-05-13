---Find forced plans
SELECT 
    qsq.query_id,
    qsp.plan_id,
    qsp.is_forced_plan,
    qsp.force_failure_count,
    qsp.last_execution_time
FROM 
    sys.query_store_plan qsp
JOIN 
    sys.query_store_query qsq ON qsp.query_id = qsq.query_id
WHERE 
    qsp.is_forced_plan = 1

    --- Executions per hour
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


--- Aggregate waits
DECLARE @StartTime datetime2 = '2026-02-26 12:30:00';
DECLARE @EndTime   datetime2 = '2026-02-26 13:30:00';

SELECT
    qsws.wait_category_desc,
    SUM(qsws.total_query_wait_time_ms)                          AS total_wait_ms,
    SUM(qsws.total_query_wait_time_ms)
        / NULLIF(SUM(qsws.total_query_wait_time_ms
            / NULLIF(qsws.avg_query_wait_time_ms, 0)), 0)       AS avg_wait_ms,
    MAX(qsws.max_query_wait_time_ms)                            AS max_wait_ms,
    COUNT(DISTINCT qsq.query_id)                                AS distinct_queries_affected
FROM sys.query_store_wait_stats             qsws
JOIN sys.query_store_runtime_stats_interval qsrsi
    ON qsws.runtime_stats_interval_id = qsrsi.runtime_stats_interval_id
JOIN sys.query_store_plan                   qsp  ON qsws.plan_id  = qsp.plan_id
JOIN sys.query_store_query                  qsq  ON qsp.query_id  = qsq.query_id
WHERE qsrsi.start_time >= @StartTime
  AND qsrsi.end_time   <= @EndTime
  AND qsq.query_id = 1
GROUP BY qsws.wait_category_desc
ORDER BY total_wait_ms DESC;