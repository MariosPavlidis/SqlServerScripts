/*  Parse blocked_process_report from an Extended Events .xel file

    - Set @xel_path to your XE file(s)
    - Works when the XE session writes to event_file target
    - Extracts key fields from <blocked-process-report> XML
*/

DECLARE @xel_path nvarchar(4000) = N'D:\XE\blocked_process*.xel';  -- << change

;WITH xe AS
(
    SELECT
        CAST(event_data AS xml) AS ed
    FROM sys.fn_xe_file_target_read_file(@xel_path, NULL, NULL, NULL)
),
ev AS
(
    SELECT
        ed.value('(/event/@name)[1]'              , 'sysname')       AS event_name,
        ed.value('(/event/@timestamp)[1]'         , 'datetime2(7)')  AS event_utc,
        ed.query('(/event/data/value/*)[1]')                         AS bpr_xml  -- <blocked-process-report>...
    FROM xe
    WHERE ed.value('(/event/@name)[1]', 'sysname') IN (N'blocked_process_report', N'blocked_process_report')
),
x AS
(
    SELECT
        event_name,
        event_utc,

        bpr_xml.value('(/blocked-process-report/@monitorLoop)[1]', 'bigint') AS monitorLoop,

        -- blocked process attributes
        bpr_xml.value('(/blocked-process-report/blocked-process/process/@spid)[1]'        , 'int')            AS blocked_spid,
        bpr_xml.value('(/blocked-process-report/blocked-process/process/@clientapp)[1]'   , 'nvarchar(256)')  AS blocked_clientapp,
        bpr_xml.value('(/blocked-process-report/blocked-process/process/@hostname)[1]'    , 'nvarchar(256)')  AS blocked_hostname,
        bpr_xml.value('(/blocked-process-report/blocked-process/process/@loginname)[1]'   , 'nvarchar(256)')  AS blocked_loginname,
        bpr_xml.value('(/blocked-process-report/blocked-process/process/@isolationlevel)[1]','nvarchar(64)')  AS blocked_isolationlevel,
        bpr_xml.value('(/blocked-process-report/blocked-process/process/@transactionname)[1]','nvarchar(64)') AS blocked_transactionname,
        bpr_xml.value('(/blocked-process-report/blocked-process/process/@lockMode)[1]'    , 'nvarchar(16)')   AS blocked_lockmode,
        bpr_xml.value('(/blocked-process-report/blocked-process/process/@waitresource)[1]', 'nvarchar(256)') AS waitresource,
        bpr_xml.value('(/blocked-process-report/blocked-process/process/@waittime)[1]'    , 'bigint')         AS waittime_ms,
        bpr_xml.value('(/blocked-process-report/blocked-process/process/@currentdbname)[1]','sysname')        AS currentdbname,
        bpr_xml.value('(/blocked-process-report/blocked-process/process/@currentdb)[1]'   , 'int')            AS currentdb,
        NULLIF(LTRIM(RTRIM(bpr_xml.value('(/blocked-process-report/blocked-process/process/inputbuf/text())[1]',
                                          'nvarchar(max)'))), N'')                                            AS blocked_inputbuf,

        -- blocking process attributes
        bpr_xml.value('(/blocked-process-report/blocking-process/process/@spid)[1]'       , 'int')            AS blocking_spid,
        bpr_xml.value('(/blocked-process-report/blocking-process/process/@clientapp)[1]'  , 'nvarchar(256)')  AS blocking_clientapp,
        bpr_xml.value('(/blocked-process-report/blocking-process/process/@hostname)[1]'   , 'nvarchar(256)')  AS blocking_hostname,
        bpr_xml.value('(/blocked-process-report/blocking-process/process/@loginname)[1]'  , 'nvarchar(256)')  AS blocking_loginname,
        bpr_xml.value('(/blocked-process-report/blocking-process/process/@isolationlevel)[1]','nvarchar(64)') AS blocking_isolationlevel,
        bpr_xml.value('(/blocked-process-report/blocking-process/process/@waittime)[1]'   , 'bigint')         AS blocking_waittime_ms,
        NULLIF(LTRIM(RTRIM(bpr_xml.value('(/blocked-process-report/blocking-process/process/inputbuf/text())[1]',
                                          'nvarchar(max)'))), N'')                                            AS blocking_inputbuf,

        -- first frame handles (often enough to correlate with Query Store / plans)
        bpr_xml.value('(/blocked-process-report/blocked-process/process/executionStack/frame[1]/@sqlhandle)[1]',
                      'varbinary(64)') AS blocked_sqlhandle,
        bpr_xml.value('(/blocked-process-report/blocking-process/process/executionStack/frame[1]/@sqlhandle)[1]',
                      'varbinary(64)') AS blocking_sqlhandle,

        bpr_xml AS blocked_process_report_xml
    FROM ev
)
SELECT
    event_utc,
    monitorLoop,

    currentdbname,
    waitresource,
    waittime_ms,

    blocked_spid,
    blocked_lockmode,
    blocked_transactionname,
    blocked_isolationlevel,
    blocked_loginname,
    blocked_clientapp,
    blocked_inputbuf,
    blocked_sqlhandle,

    blocking_spid,
    blocking_isolationlevel,
    blocking_loginname,
    blocking_clientapp,
    blocking_inputbuf,
    blocking_sqlhandle,

    blocked_process_report_xml
FROM x
ORDER BY event_utc DESC;
