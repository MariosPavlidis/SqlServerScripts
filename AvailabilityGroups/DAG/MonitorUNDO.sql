SELECT 
    r.session_id,
    r.command,
    r.status,
    r.percent_complete,
    r.estimated_completion_time / 1000 AS est_seconds_remaining,
    r.cpu_time,
    r.total_elapsed_time / 1000 AS elapsed_seconds,
    r.database_id,
    DB_NAME(r.database_id) AS database_name
FROM sys.dm_exec_requests AS r
WHERE r.command IN ('DB STARTUP', 'ROLLBACK', 'UNDO');