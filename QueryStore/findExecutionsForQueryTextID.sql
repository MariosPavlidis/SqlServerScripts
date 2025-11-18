
SELECT 
    qsqt.query_sql_text, 
    qsqt.query_text_id, 
    qsp.query_id, 
    qsp.plan_id,CONVERT(XML, qsp.query_plan) AS QueryPlanXML,is_forced_plan,qsp.force_failure_count,
    COUNT(qsrs.execution_type) AS execution_count,
    
    -- Elapsed time (microseconds to ms)
    AVG(qsrs.avg_duration) / 1000.0 AS avg_elapsed_ms,
    MAX(qsrs.max_duration) / 1000.0 AS max_elapsed_ms,
    MIN(qsrs.min_duration) / 1000.0 AS min_elapsed_ms,
    
    -- CPU time (microseconds to ms)
    AVG(qsrs.avg_cpu_time) / 1000.0 AS avg_cpu_ms,
    MAX(qsrs.max_cpu_time) / 1000.0 AS max_cpu_ms,
    MIN(qsrs.min_cpu_time) / 1000.0 AS min_cpu_ms,
    
    -- Logical reads
    AVG(qsrs.avg_logical_io_reads) AS avg_logical_reads,
    MAX(qsrs.max_logical_io_reads) AS max_logical_reads,
    MIN(qsrs.min_logical_io_reads) AS min_logical_reads,
    
    MAX(qsrs.last_execution_time) AS last_executed

FROM 
    sys.query_store_query_text qsqt
JOIN 
    sys.query_store_query qsq ON qsqt.query_text_id = qsq.query_text_id
JOIN 
    sys.query_store_plan qsp ON qsq.query_id = qsp.query_id
JOIN 
    sys.query_store_runtime_stats qsrs ON qsp.plan_id = qsrs.plan_id
WHERE 
    qsqt.query_text_id = 69383
GROUP BY 
    qsqt.query_sql_text, 
    qsqt.query_text_id, 
    qsp.query_id, 
    qsp.plan_id,
	qsp.query_plan,qsp.force_failure_count,is_forced_plan
ORDER BY 
    last_executed DESC;
