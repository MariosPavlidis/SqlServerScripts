DECLARE @TableName sysname = N'YourTableName';   -- exact table name
DECLARE @SchemaName sysname = NULL;              -- NULL = any schema

IF OBJECT_ID('tempdb..#Results') IS NOT NULL DROP TABLE #Results;
CREATE TABLE #Results
(
    database_name sysname,
    schema_name   sysname,
    table_name    sysname
);

DECLARE @sql nvarchar(max) = N'';

SELECT @sql += N'
IF DB_ID(''' + d.name + ''') IS NOT NULL
BEGIN
    INSERT INTO #Results (database_name, schema_name, table_name)
    SELECT
        ''' + d.name + ''',
        s.name,
        t.name
    FROM ' + QUOTENAME(d.name) + '.sys.tables t
    JOIN ' + QUOTENAME(d.name) + '.sys.schemas s
        ON t.schema_id = s.schema_id
    WHERE t.name = @TableName
      AND (@SchemaName IS NULL OR s.name = @SchemaName);
END;'
FROM sys.databases d
WHERE d.state_desc = 'ONLINE'
  AND d.database_id > 4;  -- skip system DBs

EXEC sp_executesql
    @sql,
    N'@TableName sysname, @SchemaName sysname',
    @TableName = @TableName,
    @SchemaName = @SchemaName;

SELECT *
FROM #Results
ORDER BY database_name, schema_name;
