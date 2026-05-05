DECLARE @sql    NVARCHAR(MAX) = N'';
DECLARE @result TABLE (
    db_name         SYSNAME,
    sequence_schema NVARCHAR(128),
    sequence_name   NVARCHAR(128),
    minimum_value   SQL_VARIANT,
    maximum_value   SQL_VARIANT,
    increment       SQL_VARIANT,
    current_value   SQL_VARIANT,
    is_cycling      BIT,
    cache_size      INT
);

SELECT @sql += N'
    SELECT
        ''' + name + N'''                                           AS db_name,
        SCHEMA_NAME(schema_id) COLLATE DATABASE_DEFAULT            AS sequence_schema,
        name                   COLLATE DATABASE_DEFAULT            AS sequence_name,
        minimum_value,
        maximum_value,
        increment,
        current_value,
        is_cycling,
        cache_size
    FROM ' + QUOTENAME(name) + N'.sys.sequences
    WHERE is_cached = 0
    UNION ALL'
FROM sys.databases
WHERE state_desc = 'ONLINE'
  AND database_id > 4;

SET @sql = LEFT(@sql, LEN(@sql) - 9);

INSERT INTO @result
EXEC sp_executesql @sql;

SELECT *
FROM   @result
ORDER BY db_name, sequence_schema, sequence_name;