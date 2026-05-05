IF OBJECT_ID('tempdb..#DbSpace') IS NOT NULL
    DROP TABLE #DbSpace;
CREATE TABLE #DbSpace
(
    DatabaseName    sysname,
    TotalSizeMB     DECIMAL(18,2),
    FreeSpaceMB     DECIMAL(18,2),
    FreePct         DECIMAL(6,2),
    DataSizeMB      DECIMAL(18,2),
    FreeDataMB      DECIMAL(18,2),
    LogSizeMB       DECIMAL(18,2),
    FreeLogMB       DECIMAL(18,2)
);

DECLARE 
    @db  sysname,
    @sql nvarchar(max);

DECLARE db_cursor CURSOR FAST_FORWARD FOR
SELECT name
FROM sys.databases
WHERE state = 0;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
    USE ' + QUOTENAME(@db) + N';
    WITH DataFiles AS
    (
        SELECT
            DataTotalMB = SUM(size) * 8.0 / 1024.0,
            DataFreeMB  = SUM(size - FILEPROPERTY(name, ''SpaceUsed'')) * 8.0 / 1024.0
        FROM sys.database_files
        WHERE type IN (0,2)
    ),
    LogInfo AS
    (
        SELECT
            total_log_size_mb = total_log_size_in_bytes / 1024.0 / 1024.0,
            used_log_size_mb  = used_log_space_in_bytes / 1024.0 / 1024.0
        FROM sys.dm_db_log_space_usage
    )
    INSERT INTO #DbSpace
    (
        DatabaseName,
        TotalSizeMB,
        FreeSpaceMB,
        FreePct,
        DataSizeMB,
        FreeDataMB,
        LogSizeMB,
        FreeLogMB
    )
    SELECT
        DB_NAME(),
        CAST(DataTotalMB + total_log_size_mb                          AS DECIMAL(18,2)),
        CAST(DataFreeMB  + (total_log_size_mb - used_log_size_mb)     AS DECIMAL(18,2)),
        CAST(
            (DataFreeMB + (total_log_size_mb - used_log_size_mb)) * 100.0 /
            NULLIF(DataTotalMB + total_log_size_mb, 0)
        AS DECIMAL(6,2)),
        CAST(DataTotalMB                                              AS DECIMAL(18,2)),
        CAST(DataFreeMB                                               AS DECIMAL(18,2)),
        CAST(total_log_size_mb                                        AS DECIMAL(18,2)),
        CAST(total_log_size_mb - used_log_size_mb                     AS DECIMAL(18,2))
    FROM DataFiles
    CROSS JOIN LogInfo;
    ';

    EXEC sys.sp_executesql @sql;
    FETCH NEXT FROM db_cursor INTO @db;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;

SELECT
    DatabaseName,
    TotalSizeMB,
    FreeSpaceMB,
    FreePct,
    DataSizeMB,
    FreeDataMB,
    LogSizeMB,
    FreeLogMB
FROM #DbSpace
ORDER BY FreePct ASC;