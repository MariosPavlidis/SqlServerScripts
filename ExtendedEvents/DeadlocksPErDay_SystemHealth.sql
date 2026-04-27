/* Group deadlocks from system_health XE by day */

SET NOCOUNT ON;

DECLARE @base_file nvarchar(4000);
DECLARE @pattern   nvarchar(4000);

SELECT @base_file =
    CAST(t.target_data AS xml).value('(/EventFileTarget/File/@name)[1]', 'nvarchar(4000)')
FROM sys.dm_xe_session_targets t
JOIN sys.dm_xe_sessions s
    ON s.address = t.event_session_address
WHERE s.name = N'system_health'
  AND t.target_name = N'event_file';

IF @base_file IS NULL
BEGIN
    RAISERROR('system_health is not running or no event_file target found.', 16, 1);
    RETURN;
END;

SET @pattern =
    LEFT(@base_file, LEN(@base_file) - CHARINDEX('_', REVERSE(@base_file)) + 1) + N'*.xel';

DECLARE @sql nvarchar(max) = N'
;WITH xe AS
(
    SELECT
        CONVERT(xml, event_data) AS event_xml
    FROM sys.fn_xe_file_target_read_file
    (
        N''' + REPLACE(@pattern, '''', '''''') + N''',
        NULL,
        NULL,
        NULL
    )
    WHERE object_name = N''xml_deadlock_report''
),
deadlocks AS
(
    SELECT
        CAST(event_xml.value(''(event/@timestamp)[1]'', ''datetime2(3)'') AS date) AS deadlock_utc_date
    FROM xe
)
SELECT
    deadlock_utc_date,
    COUNT(*) AS deadlock_count
FROM deadlocks
GROUP BY deadlock_utc_date
ORDER BY deadlock_utc_date DESC;
';

EXEC sys.sp_executesql @sql;