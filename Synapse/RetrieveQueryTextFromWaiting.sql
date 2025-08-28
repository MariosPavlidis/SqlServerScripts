SELECT waiting.session_id AS WaitingSessionId,
       waiting.request_id AS WaitingRequestId,
       COALESCE(waiting_exec_request.command,waiting_exec_request.command2) AS WaitingExecRequestText,
       waiting.object_name AS Waiting_Object_Name,
       waiting.object_type AS Waiting_Object_Type,
       blocking.session_id AS BlockingSessionId,
       blocking.request_id AS BlockingRequestId,
       COALESCE(blocking_exec_request.command,blocking_exec_request.command2) AS BlockingExecRequestText,
       blocking.object_name AS Blocking_Object_Name,
       blocking.object_type AS Blocking_Object_Type,
       waiting.type AS Lock_Type,
       waiting.request_time AS Lock_Request_Time,
       datediff(ms, waiting.request_time, getdate())/1000.0 AS Blocking_Time_sec
FROM sys.dm_pdw_waits waiting
       INNER JOIN sys.dm_pdw_waits blocking
       ON waiting.object_type = blocking.object_type
       AND waiting.object_name = blocking.object_name
       INNER JOIN sys.dm_pdw_exec_requests blocking_exec_request
       ON blocking.request_id = blocking_exec_request.request_id
       INNER JOIN sys.dm_pdw_exec_requests waiting_exec_request
       ON waiting.request_id = waiting_exec_request.request_id
WHERE waiting.state = 'Queued'
       AND blocking.state = 'Granted'
ORDER BY Lock_Request_Time DESC;