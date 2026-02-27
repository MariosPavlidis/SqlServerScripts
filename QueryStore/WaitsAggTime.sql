 DECLARE @StartTime datetime2 = '2026-02-26 12:30:00';
 DECLARE @EndTime   datetime2 = '2026-02-26 13:30:00';

  SELECT
      qsws.wait_category_desc,
      SUM(qsws.total_query_wait_time_ms)  AS total_wait_ms,
      AVG(qsws.avg_query_wait_time_ms)    AS avg_wait_ms,
      COUNT(DISTINCT qsq.query_id)        AS distinct_queries_affected
  FROM sys.query_store_wait_stats             qsws
  JOIN sys.query_store_runtime_stats_interval qsrsi
      ON qsws.runtime_stats_interval_id = qsrsi.runtime_stats_interval_id
  JOIN sys.query_store_plan                   qsp  ON qsws.plan_id   = qsp.plan_id
  JOIN sys.query_store_query                  qsq  ON qsp.query_id   = qsq.query_id
  WHERE qsrsi.start_time >= @StartTime
    AND qsrsi.end_time   <= @EndTime
  GROUP BY qsws.wait_category_desc
  ORDER BY total_wait_ms DESC;