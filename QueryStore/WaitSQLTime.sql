 DECLARE @StartTime datetime2 = '2026-02-26 12:30:00';
  DECLARE @EndTime   datetime2 = '2026-02-26 13:30:00';

  SELECT
      qsq.query_id,
      qsp.plan_id,
      qsqt.query_sql_text,
      qsws.wait_category_desc,
      SUM(qsws.total_query_wait_time_ms)      AS total_wait_ms,
      -- weighted average using execution count from runtime_stats
      SUM(qsws.total_query_wait_time_ms)
          / NULLIF(SUM(qsrs.count_executions), 0) AS avg_wait_ms,
      MAX(qsws.max_query_wait_time_ms)        AS max_wait_ms,
      SUM(qsrs.count_executions)              AS total_executions,
      MIN(qsrsi.start_time)                   AS interval_start,
      MAX(qsrsi.end_time)                     AS interval_end
  FROM sys.query_store_wait_stats             qsws
  JOIN sys.query_store_runtime_stats_interval qsrsi
      ON  qsws.runtime_stats_interval_id = qsrsi.runtime_stats_interval_id
  JOIN sys.query_store_plan                   qsp
      ON  qsws.plan_id = qsp.plan_id
  JOIN sys.query_store_query                  qsq
      ON  qsp.query_id = qsq.query_id
  JOIN sys.query_store_query_text             qsqt
      ON  qsq.query_text_id = qsqt.query_text_id
  JOIN sys.query_store_runtime_stats          qsrs
      ON  qsws.plan_id                    = qsrs.plan_id
      AND qsws.runtime_stats_interval_id  = qsrs.runtime_stats_interval_id
      AND qsws.execution_type             = qsrs.execution_type
  WHERE qsrsi.start_time >= @StartTime
    AND qsrsi.end_time   <= @EndTime
    AND qsws.wait_category_desc IN (
          'Lock',           -- blocking locks (your likely culprit)
          'Latch',          -- memory structure contention
          'Buffer Latch',   -- buffer pool contention
          'Buffer IO',      -- disk IO waits
          'Network IO',     -- slow client consuming results
          'Parallelism',    -- parallel query coordination
          'Memory'          -- memory pressure / grants
          -- remove filter entirely to see ALL wait types
    )
  GROUP BY
      qsq.query_id,
      qsp.plan_id,
      qsqt.query_sql_text,
      qsws.wait_category_desc
  ORDER BY total_wait_ms DESC;