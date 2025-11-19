IF OBJECT_ID('tempdb..#DbSpace') IS NOT NULL
    DROP TABLE #DbSpace;

CREATE TABLE #DbSpace
(
    DatabaseName sysname,
    TotalSizeMB  DECIMAL(18,2),
    FreeSpaceMB  DECIMAL(18,2),
    FreePct      DECIMAL(6,2)
);

DECLARE 
    @db  sysname,
    @sql nvarchar(max);

DECLARE db_cursor CURSOR FAST_FORWARD FOR
SELECT name
FROM sys.databases
WHERE state = 0;          -- only online DBs

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
        WHERE type IN (0,2)   -- rows + filestream
    ),
    LogInfo AS
    (
        SELECT
            total_log_size_mb = total_log_size_in_bytes / 1024.0 / 1024.0,
            used_log_size_mb  = used_log_space_in_bytes / 1024.0 / 1024.0
        FROM sys.dm_db_log_space_usage
    )
    INSERT INTO #DbSpace (DatabaseName, TotalSizeMB, FreeSpaceMB, FreePct)
    SELECT
        DB_NAME() AS DatabaseName,
        CAST(DataTotalMB + LogInfo.total_log_size_mb AS DECIMAL(18,2)) AS TotalSizeMB,
        CAST(DataFreeMB + (LogInfo.total_log_size_mb - LogInfo.used_log_size_mb) AS DECIMAL(18,2)) AS FreeSpaceMB,
        CAST(
            (DataFreeMB + (LogInfo.total_log_size_mb - LogInfo.used_log_size_mb)) * 100.0 /
            NULLIF(DataTotalMB + LogInfo.total_log_size_mb, 0)
        AS DECIMAL(6,2)) AS FreePct
    FROM DataFiles
    CROSS JOIN LogInfo;
    ';

    EXEC sys.sp_executesql @sql;

    FETCH NEXT FROM db_cursor INTO @db;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;

SELECT *
FROM #DbSpace
ORDER BY FreePct ASC;
