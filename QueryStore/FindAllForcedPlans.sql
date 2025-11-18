
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