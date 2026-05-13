SELECT 
    q.query_id,
    q.query_hash,
    qt.query_sql_text,
    COUNT(DISTINCT p.plan_id)        AS plan_count,
    COUNT(rs.execution_type)         AS total_executions,
    SUM(rs.count_executions)         AS total_execution_count,
    MIN(rs.avg_duration / 1000.0)    AS min_avg_duration_ms,
    MAX(rs.avg_duration / 1000.0)    AS max_avg_duration_ms,
    MAX(rs.avg_duration / 1000.0) 
      - MIN(rs.avg_duration / 1000.0) AS duration_variance_ms,
    MIN(rs.avg_logical_io_reads)     AS min_avg_logical_reads,
    MAX(rs.avg_logical_io_reads)     AS max_avg_logical_reads
FROM sys.query_store_query          q
JOIN sys.query_store_query_text     qt ON q.query_text_id   = qt.query_text_id
JOIN sys.query_store_plan           p  ON q.query_id        = p.query_id
JOIN sys.query_store_runtime_stats  rs ON p.plan_id         = rs.plan_id
WHERE q.is_internal_query = 0
GROUP BY 
    q.query_id,
    q.query_hash,
    qt.query_sql_text
HAVING COUNT(DISTINCT p.plan_id) > 1
ORDER BY 
    plan_count          DESC,
    duration_variance_ms DESC;