-- All active sessions with full SQL text
SELECT
    s.session_id,
    s.login_name,
    s.host_name,
    s.program_name,
    s.status,
    r.command,
    r.wait_type,
    r.wait_time,
    r.blocking_session_id,
    r.cpu_time,
    r.total_elapsed_time,
    t.text AS sql_fulltext
FROM
    sys.dm_exec_sessions s
JOIN
    sys.dm_exec_requests r ON s.session_id = r.session_id
CROSS APPLY
    sys.dm_exec_sql_text(r.sql_handle) t
WHERE
    s.is_user_process = 1
ORDER BY
    r.total_elapsed_time DESC;