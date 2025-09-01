
SELECT
    TOP 500 waiting.request_id AS WaitingRequestId,waiting.type as LockType,
    waiting.object_type AS LockRequestType,
    waiting.object_name AS ObjectLockRequestName,
    waiting.request_time AS ObjectLockRequestTime,datediff (s,waiting.request_time,getdate()) secs_wait ,
    blocking.session_id AS BlockingSessionId,
    blocking.request_id AS BlockingRequestId
FROM
    sys.dm_pdw_waits waiting
    INNER JOIN sys.dm_pdw_waits blocking
    ON waiting.object_type = blocking.object_type
    AND waiting.object_name = blocking.object_name
WHERE
    waiting.state = 'Queued'
    AND blocking.state = 'Granted'
ORDER BY
    ObjectLockRequestTime ASC;