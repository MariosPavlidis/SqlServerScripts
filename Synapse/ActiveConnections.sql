--There is limit of active connections so monitor this
SELECT count(*) FROM sys.dm_pdw_exec_sessions where status <> 'Closed' and session_id <> session_id();