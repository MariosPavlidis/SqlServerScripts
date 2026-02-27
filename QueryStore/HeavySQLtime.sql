 DECLARE @StartTime datetime2 = '2026-02-26 12:00:00';
 DECLARE @EndTime   datetime2 = '2026-02-26 14:30:00';

SELECT TOP (100)
       DB_NAME()                                            AS database_name,
       OBJECT_SCHEMA_NAME(q.object_id, DB_ID())             AS schema_name,
       OBJECT_NAME(q.object_id, DB_ID())                    AS object_name,
       q.query_id,
       p.plan_id,
       qt.query_sql_text,
       TRY_CONVERT(xml, p.query_plan)                       AS query_plan_xml,
       SUM(rs.count_executions)                             AS executions,
       -- durations are in microseconds; weighted average across intervals
       SUM(rs.avg_duration * 1.0 * rs.count_executions)
           / NULLIF(SUM(rs.count_executions), 0) / 1000.0   AS avg_duration_ms,
       MIN(rs.min_duration) * 1.0 / 1000.0                  AS min_duration_ms,
       MAX(rs.max_duration) * 1.0 / 1000.0                  AS max_duration_ms,
       SUM(rs.avg_duration * 1.0 * rs.count_executions)
           / 1000.0                                          AS total_duration_ms,
       MAX(rs.last_execution_time)                          AS last_execution_time,
       MAX(rsi.end_time)                                    AS last_interval
FROM   sys.query_store_runtime_stats           AS rs
JOIN   sys.query_store_plan                    AS p
           ON rs.plan_id = p.plan_id
JOIN   sys.query_store_query                   AS q
           ON p.query_id = q.query_id
JOIN   sys.query_store_query_text              AS qt
           ON q.query_text_id = qt.query_text_id
JOIN   sys.query_store_runtime_stats_interval  AS rsi
           ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
WHERE  rsi.start_time < @EndTime   -- interval overlaps the window
  AND  rsi.end_time   > @StartTime
GROUP BY
       q.query_id,
       p.plan_id,
       qt.query_sql_text,
       p.query_plan,
       q.object_id
ORDER BY
       avg_duration_ms DESC;  -- change to min_duration_ms / max_duration_ms / total_duration_ms
