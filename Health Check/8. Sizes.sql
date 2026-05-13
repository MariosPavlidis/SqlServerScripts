----- All DB Sizes
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




-- ============================================================
-- Top 20 tables by size (MB) across all databases
-- ============================================================

IF OBJECT_ID('tempdb..#TableSizes') IS NOT NULL
    DROP TABLE #TableSizes;

CREATE TABLE #TableSizes (
    database_name   SYSNAME,
    schema_name     SYSNAME,
    table_name      SYSNAME,
    row_count       BIGINT,
    total_mb        DECIMAL(12,2),
    used_mb         DECIMAL(12,2),
    data_mb         DECIMAL(12,2),
    index_mb        DECIMAL(12,2)
);

-- Cursor to iterate all online, readable databases
DECLARE @dbname  SYSNAME;
DECLARE @sql     NVARCHAR(MAX);

DECLARE db_cursor CURSOR FAST_FORWARD READ_ONLY FOR
    SELECT name
    FROM   sys.databases
    WHERE  state_desc      = 'ONLINE'
      AND  user_access_desc = 'MULTI_USER'
      AND  is_read_only     = 0
      AND  database_id      > 4          -- skip system DBs (master/model/msdb/tempdb)
    -- Remove or adjust the line above if you want system DBs included
    ORDER BY name;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @dbname;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
    USE ' + QUOTENAME(@dbname) + N';

    INSERT INTO #TableSizes
    (database_name, schema_name, table_name, row_count, total_mb, used_mb, data_mb, index_mb)
    SELECT
        DB_NAME()                                                           AS database_name,
        s.name                                                              AS schema_name,
        t.name                                                              AS table_name,
        SUM(p.rows)                                                         AS row_count,
        CAST(SUM(a.total_pages) * 8 / 1024.0 AS DECIMAL(12,2))            AS total_mb,
        CAST(SUM(a.used_pages)  * 8 / 1024.0 AS DECIMAL(12,2))            AS used_mb,
        CAST(SUM(a.data_pages)  * 8 / 1024.0 AS DECIMAL(12,2))            AS data_mb,
        CAST((SUM(a.used_pages) - SUM(a.data_pages)) * 8 / 1024.0
             AS DECIMAL(12,2))                                              AS index_mb
    FROM sys.tables          t
    JOIN sys.schemas         s  ON s.schema_id = t.schema_id
    JOIN sys.indexes         i  ON i.object_id = t.object_id
    JOIN sys.partitions      p  ON p.object_id = i.object_id
                               AND p.index_id  = i.index_id
    JOIN sys.allocation_units a ON a.container_id =
            CASE
                WHEN a.type IN (1, 3) THEN p.hobt_id
                WHEN a.type = 2       THEN p.partition_id
            END
    GROUP BY s.name, t.name;
    ';

    BEGIN TRY
        EXEC sp_executesql @sql;
    END TRY
    BEGIN CATCH
        PRINT 'Skipped database: ' + @dbname + ' — ' + ERROR_MESSAGE();
    END CATCH;

    FETCH NEXT FROM db_cursor INTO @dbname;
END;

CLOSE     db_cursor;
DEALLOCATE db_cursor;

-- ============================================================
-- Final result: top 20 tables across all databases
-- ============================================================
SELECT TOP 20
    database_name,
    schema_name,
    table_name,
    FORMAT(row_count, 'N0')  AS row_count,
    total_mb,
    used_mb,
    data_mb,
    index_mb
FROM   #TableSizes
ORDER BY database_name,total_mb DESC;

DROP TABLE #TableSizes;