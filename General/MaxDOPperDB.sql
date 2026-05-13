DROP TABLE IF EXISTS #maxdop;

CREATE TABLE #maxdop
(
    database_name   sysname,
    maxdop_value    int,
    effective_maxdop varchar(50)
);

DECLARE @instance_maxdop int;
SELECT @instance_maxdop = CAST(value_in_use AS int)
FROM sys.configurations
WHERE name = 'max degree of parallelism';

DECLARE @db     sysname,
        @sql    nvarchar(500);

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM sys.databases
    WHERE state_desc = 'ONLINE'
    AND   name NOT IN ('tempdb')
    ORDER BY name;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
        INSERT INTO #maxdop (database_name, maxdop_value, effective_maxdop)
        SELECT 
            '''+QUOTENAME(@db) +''',
            CAST(value AS int),
            CASE CAST(value AS int)
                WHEN 0 THEN ''Inherits instance ('' + CAST(' + CAST(@instance_maxdop AS nvarchar) + N' AS varchar) + '')''
                ELSE CAST(value AS varchar)
            END
        FROM ' + QUOTENAME(@db) + N'.sys.database_scoped_configurations
        WHERE name = ''MAXDOP'';';

    EXEC sp_executesql @sql;

    FETCH NEXT FROM db_cursor INTO @db;
END;

CLOSE db_cursor;
DEALLOCATE db_cursor;

SELECT 
    database_name,
    maxdop_value,
    effective_maxdop
FROM #maxdop
ORDER BY database_name;
