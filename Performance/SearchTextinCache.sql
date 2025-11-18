	SELECT 
    qs.sql_handle,
    qs.plan_handle,
    qt.text,
    qs.creation_time,
    qs.execution_count
FROM 
    sys.dm_exec_query_stats qs
CROSS APPLY 
    sys.dm_exec_sql_text(qs.sql_handle) qt
WHERE 
    qt.text LIKE '%SELECT IPS_MESSAGE_HEAD01."ORDER_CODE",IPS_MESSAGE_HEAD01."FK_ORDER_CODE",IPS_MESSAGE_HEAD01."ORDER_TIMESTAMP" %';
