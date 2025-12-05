SELECT s.session_id,
    r.request_id,
    r.status,                          -- Running, Queued, Suspended, Completed, Failed
    r.command,r.submit_time,
    r.start_time, datediff(s,r.submit_time,r.start_time) wait_s,
    total_elapsed_time/1000 AS elapsed_seconds,
    s.login_name,
    s.client_id,
    rc.name AS resource_class         -- Resource class determines slot usage
FROM sys.dm_pdw_exec_requests r
JOIN sys.dm_pdw_exec_sessions s
    ON r.session_id = s.session_id
LEFT JOIN sys.database_role_members drm
    ON s.login_name = USER_NAME(drm.member_principal_id)
LEFT JOIN sys.database_principals rc
    ON drm.role_principal_id = rc.principal_id
WHERE --r.status NOT IN ('Completed','Failed','Cancelled') --and 
   --  r.command like 'UPDATE STATISTICS%' 
    -- or r.command like 'BuildReplicatedTableCache%'
ORDER BY r.submit_time desc;
