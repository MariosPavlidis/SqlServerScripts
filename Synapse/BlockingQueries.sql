 
--blocking
SELECT
    TOP 500 blocking.request_id AS BlockingRequestId,
    waiting.request_id AS WaitingRequestId,
    blocking.session_id AS BlockingSessionId,   
    waiting.session_id waitingSession, 
    waiting.type +' '+' Lock On '+waiting.object_type +' ' +waiting.object_name  as WaitResource,
    waiting.request_time AS ObjectLockRequestTime,
    RIGHT('0' + CAST(DATEDIFF(s,waiting.request_time, GETDATE()) / 3600 AS VARCHAR(2)), 2) + ':' +
    RIGHT('0' + CAST((DATEDIFF(s,waiting.request_time, GETDATE()) % 3600) / 60 AS VARCHAR(2)), 2) + ':' +
    RIGHT('0' + CAST(DATEDIFF(s,waiting.request_time, GETDATE()) % 60 AS VARCHAR(2)), 2) AS [hh:mm:ss],
    s.login_name as BlockingLoginName,r.command as BlockingCommand,
    rw.command as WaitingCommand
FROM
    sys.dm_pdw_waits waiting
    INNER JOIN sys.dm_pdw_waits blocking
    ON waiting.object_type = blocking.object_type     AND waiting.object_name = blocking.object_name
    join sys.dm_pdw_exec_sessions s on s.session_id=blocking.session_id
    join sys.dm_pdw_exec_requests r on r.session_id=blocking.session_id
    join sys.dm_pdw_exec_requests rw on rw.session_id=waiting.session_id
WHERE
    waiting.state = 'Queued'
    AND blocking.state = 'Granted'
ORDER BY
        RIGHT('0' + CAST(DATEDIFF(s,waiting.request_time, GETDATE()) / 3600 AS VARCHAR(2)), 2) + ':' +
    RIGHT('0' + CAST((DATEDIFF(s,waiting.request_time, GETDATE()) % 3600) / 60 AS VARCHAR(2)), 2) + ':' +
    RIGHT('0' + CAST(DATEDIFF(s,waiting.request_time, GETDATE()) % 60 AS VARCHAR(2)), 2)  desc;
 