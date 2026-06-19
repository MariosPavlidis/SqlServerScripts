

DECLARE @StartTime datetime2 = '2026-05-20 12:00:00';
DECLARE @EndTime   datetime2 = '2026-05-26 14:30:00';

/* ----------------------------------------------------------------------
   1) Runtime stats aggregated per plan (durations in microseconds).
   ---------------------------------------------------------------------- */
WITH runtime_agg AS
(
    SELECT q.query_id,
           p.plan_id,
           q.object_id,
           qt.query_sql_text,
           p.query_plan,
           SUM(rs.count_executions)                              AS executions,
           SUM(rs.avg_duration * 1.0 * rs.count_executions)
               / NULLIF(SUM(rs.count_executions), 0) / 1000.0    AS avg_duration_ms,
           MIN(rs.min_duration) * 1.0 / 1000.0                   AS min_duration_ms,
           MAX(rs.max_duration) * 1.0 / 1000.0                   AS max_duration_ms,
           SUM(rs.avg_duration * 1.0 * rs.count_executions)
               / 1000.0                                          AS total_duration_ms,
           MAX(rs.last_execution_time)                           AS last_execution_time,
           MAX(rsi.end_time)                                     AS last_interval
    FROM   sys.query_store_runtime_stats          AS rs
    JOIN   sys.query_store_plan                   AS p   ON rs.plan_id = p.plan_id
    JOIN   sys.query_store_query                  AS q   ON p.query_id = q.query_id
    JOIN   sys.query_store_query_text             AS qt  ON q.query_text_id = qt.query_text_id
    JOIN   sys.query_store_runtime_stats_interval AS rsi ON rs.runtime_stats_interval_id
                                                          = rsi.runtime_stats_interval_id
    WHERE  rsi.start_time < @EndTime          -- interval overlaps the window
      AND  rsi.end_time   > @StartTime
    GROUP BY q.query_id, p.plan_id, q.object_id, qt.query_sql_text, p.query_plan
),
/* ----------------------------------------------------------------------
   2) Wait stats per plan + category (times ALREADY in milliseconds).
      Note: Query Store buckets waits into ~23 categories (CPU, Lock,
      Buffer IO, Latch, Memory, ...) -- NOT granular wait types like
      sys.dm_os_wait_stats reports (e.g. PAGEIOLATCH_SH).
   ---------------------------------------------------------------------- */
ws_by_category AS
(
    SELECT ws.plan_id,
           ws.wait_category_desc,
           SUM(ws.total_query_wait_time_ms)        AS category_wait_ms,
           MAX(ws.max_query_wait_time_ms)          AS category_max_wait_ms
    FROM   sys.query_store_wait_stats              AS ws
    JOIN   sys.query_store_runtime_stats_interval  AS wsi ON ws.runtime_stats_interval_id
                                                           = wsi.runtime_stats_interval_id
    WHERE  wsi.start_time < @EndTime
      AND  wsi.end_time   > @StartTime
    GROUP BY ws.plan_id, ws.wait_category_desc
),
/* ----------------------------------------------------------------------
   3) Roll categories up to one row per plan: total, max, and a
      "Category (ms)" breakdown ordered by heaviest wait first.
   ---------------------------------------------------------------------- */
ws_rollup AS
(
    SELECT plan_id,
           SUM(category_wait_ms)                   AS total_wait_ms,
           MAX(category_max_wait_ms)               AS max_wait_ms,
           STRING_AGG(
               CONCAT(wait_category_desc, ' (',
                      CAST(CAST(category_wait_ms AS bigint) AS varchar(20)),
                      ' ms)'),
               ' | ')
               WITHIN GROUP (ORDER BY category_wait_ms DESC) AS wait_breakdown
    FROM   ws_by_category
    GROUP BY plan_id
)
SELECT TOP (20)
       DB_NAME()                                        AS database_name,
       OBJECT_SCHEMA_NAME(ra.object_id, DB_ID())        AS schema_name,
       OBJECT_NAME(ra.object_id, DB_ID())               AS object_name,
       ra.query_id,
       ra.plan_id,
       ra.query_sql_text,
       TRY_CONVERT(xml, ra.query_plan)                  AS query_plan_xml,
       ra.executions,
       ra.avg_duration_ms,
       ra.min_duration_ms,
       ra.max_duration_ms,
       ra.total_duration_ms,
       ISNULL(ws.total_wait_ms, 0)                      AS total_wait_ms,
       ISNULL(ws.total_wait_ms, 0)
           / NULLIF(ra.executions, 0)                   AS avg_wait_ms_per_exec,
       ws.max_wait_ms,
       ws.wait_breakdown,
       ra.last_execution_time,
       ra.last_interval
FROM        runtime_agg AS ra
LEFT JOIN   ws_rollup   AS ws  ON ra.plan_id = ws.plan_id
ORDER BY    ra.total_duration_ms DESC;
-- swap ORDER BY to total_wait_ms / avg_wait_ms_per_exec to rank by wait instead