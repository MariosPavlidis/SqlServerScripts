/* Read lock_escalation from an XE .xel file and extract:
   timestamp_utc, database_id, hobt_id, object_id, sql_text,
   escalation_cause, escalated_lock_count, transaction_id.

   Notes:
   - lock_escalation is an <event> wrapper (not a raw <deadlock> root).
   - Some fields are XE "data" nodes, sql_text is usually an "action".
*/

DECLARE @xel_pattern nvarchar(4000) =
N'H:\SystemDBs\MSSQL15.MSSQLSERVER\MSSQL\Log\Lock_Escalation_0_134110466602650000.xel';  -- adjust

;WITH XE AS
(
    SELECT
        f.timestamp_utc,
        CAST(f.event_data AS xml) AS ed
    FROM sys.fn_xe_file_target_read_file(@xel_pattern, NULL, NULL, NULL) AS f
),
L AS
(
    SELECT
        x.timestamp_utc,

        x.ed.value('(/event/@name)[1]', 'sysname') AS event_name,

        -- data fields
        x.ed.value('(/event/data[@name="database_id"]/value)[1]', 'int') AS database_id,
        x.ed.value('(/event/data[@name="hobt_id"]/value)[1]', 'bigint')  AS hobt_id,
        x.ed.value('(/event/data[@name="object_id"]/value)[1]', 'int')   AS object_id,

        x.ed.value('(/event/data[@name="escalation_cause"]/text)[1]', 'nvarchar(200)') AS escalation_cause,
        x.ed.value('(/event/data[@name="escalated_lock_count"]/value)[1]', 'bigint')   AS escalated_lock_count,
        x.ed.value('(/event/data[@name="transaction_id"]/value)[1]', 'bigint')         AS transaction_id,

        -- actions (may be null if not captured)
        x.ed.value('(/event/action[@name="sql_text"]/value)[1]', 'nvarchar(max)') AS sql_text,
        x.ed.value('(/event/action[@name="client_app_name"]/value)[1]', 'sysname') AS app_name,
        x.ed.value('(/event/action[@name="client_hostname"]/value)[1]', 'sysname') AS host_name,
        x.ed.value('(/event/action[@name="server_principal_name"]/value)[1]', 'sysname') AS login_name,
        x.ed.value('(/event/action[@name="session_id"]/value)[1]', 'int') AS session_id
    FROM XE x
    WHERE x.ed.exist('/event[@name="lock_escalation"]') = 1
)
SELECT top 1000
    l.timestamp_utc,
   db_name( l.database_id),
    l.hobt_id,
    l.object_id,object_name(l.object_id),
    l.sql_text,
    l.escalation_cause,
    l.escalated_lock_count,
    l.transaction_id,
    l.session_id,
    l.login_name,
    l.host_name,
    l.app_name
FROM L l
ORDER BY l.timestamp_utc DESC;
