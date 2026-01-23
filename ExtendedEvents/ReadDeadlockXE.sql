DECLARE @xel_pattern nvarchar(4000) =
N'H:\SystemDBs\MSSQL15.MSSQLSERVER\MSSQL\Log\deadlock_capture_0_134081135273820000.xel';

;WITH X AS
(
    SELECT
        f.timestamp_utc,
        CAST(f.event_data AS xml) AS ed
    FROM sys.fn_xe_file_target_read_file(@xel_pattern, NULL, NULL, NULL) AS f
),
D AS
(
    SELECT
        x.timestamp_utc,
        -- deadlock graph normalized as <deadlock>...</deadlock>
        CASE
            WHEN x.ed.exist('/deadlock') = 1
                THEN x.ed
            ELSE
                x.ed.query('(/event/data[@name="xml_report"]/value/deadlock)[1]')
        END AS dg
    FROM X x
    WHERE
        x.ed.exist('/deadlock') = 1
        OR x.ed.exist('/event[@name="xml_deadlock_report"]') = 1
        OR x.ed.exist('/event/data[@name="xml_report"]/value/deadlock') = 1
),
Victim AS
(
    SELECT
        d.timestamp_utc,
        LTRIM(RTRIM(d.dg.value('(/deadlock/victim-list/victimProcess/@id)[1]', 'varchar(50)'))) AS victim_process_id
    FROM D d
),
Proc1 AS
(
    SELECT
        d.timestamp_utc,
        LTRIM(RTRIM(p.value('@id','varchar(50)'))) AS process_id,
        p.value('@spid','int')                     AS spid,
        p.value('@waittype','varchar(120)')        AS waittype,
        p.value('@waitresource','nvarchar(4000)')  AS waitresource,
        p.value('@loginname','sysname')            AS login_name,
        p.value('@hostname','sysname')             AS host_name,
        p.value('@clientapp','sysname')            AS app_name,
        p.value('(inputbuf/text())[1]','nvarchar(max)') AS inputbuf
    FROM D d
    CROSS APPLY d.dg.nodes('/deadlock/process-list/process') AS X(p)
),
Locks AS
(
    SELECT
        d.timestamp_utc,
        r.value('local-name(.)','sysname') AS resource_type,
        r.value('@objectname','sysname')   AS object_name,
        r.value('@indexname','sysname')    AS index_name,
        LTRIM(RTRIM(ow.value('@id','varchar(50)'))) AS process_id,
        'OWNER' AS role,
        ow.value('@mode','varchar(10)') AS lock_mode
    FROM D d
    CROSS APPLY d.dg.nodes('/deadlock/resource-list/*') AS R(r)
    CROSS APPLY r.nodes('owner-list/owner') AS O(ow)

    UNION ALL

    SELECT
        d.timestamp_utc,
        r.value('local-name(.)','sysname'),
        r.value('@objectname','sysname'),
        r.value('@indexname','sysname'),
        LTRIM(RTRIM(wt.value('@id','varchar(50)'))),
        'WAITER',
        wt.value('@mode','varchar(10)')
    FROM D d
    CROSS APPLY d.dg.nodes('/deadlock/resource-list/*') AS R(r)
    CROSS APPLY r.nodes('waiter-list/waiter') AS W(wt)
)
SELECT
    p.timestamp_utc,
    CASE WHEN p.process_id = v.victim_process_id THEN 1 ELSE 0 END AS is_victim,

    p.spid,
    p.login_name,
    p.host_name,
    p.app_name,

    p.waittype,
    p.waitresource,
    p.inputbuf,

    l.role,
    l.lock_mode,
    l.resource_type,
    l.object_name,
    l.index_name,

    v.victim_process_id  -- keep visible for verification
FROM Proc1 p
JOIN Victim v
    ON v.timestamp_utc = p.timestamp_utc
LEFT JOIN Locks l
    ON l.timestamp_utc = p.timestamp_utc
   AND l.process_id = p.process_id
ORDER BY p.timestamp_utc DESC, is_victim DESC, p.spid, l.role;
