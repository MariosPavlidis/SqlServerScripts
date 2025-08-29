SELECT
    r.request_id,
    r.status,                          -- Running, Queued, Suspended, Completed, Failed
    r.command,
    r.start_time,
    DATEDIFF(SECOND, r.start_time, GETDATE()) AS elapsed_seconds,
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
WHERE r.status NOT IN ('Completed','Failed','Cancelled')
    --and r.command like 'UPDATE STATISTICS%'
ORDER BY r.start_time;