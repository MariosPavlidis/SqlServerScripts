-----1. All programmable objects (procs, views, functions, triggers) – definitions
SELECT 
    o.type_desc,
    SCHEMA_NAME(o.schema_id) AS SchemaName,
    o.name                    AS ObjectName,
    m.definition              AS ObjectDefinition
FROM sys.sql_modules m
JOIN sys.objects     o ON m.object_id = o.object_id
WHERE o.type IN ('P','V','FN','IF','TF','TR')  -- procs, views, scalar, inline, table-valued, triggers
  AND o.is_ms_shipped = 0
ORDER BY o.type_desc, SchemaName, ObjectName;

-----2. Script CREATE VIEW statements only
SELECT 
    'CREATE VIEW ' + QUOTENAME(SCHEMA_NAME(o.schema_id)) + '.' + QUOTENAME(o.name) 
        + ' AS' + CHAR(13) + CHAR(10)
        + m.definition AS ViewDDL
FROM sys.views v
JOIN sys.objects o       ON v.object_id = o.object_id
JOIN sys.sql_modules m   ON o.object_id = m.object_id
WHERE o.is_ms_shipped = 0
ORDER BY SCHEMA_NAME(o.schema_id), o.name;

-----3. Script CREATE PROCEDURE statements
SELECT 
    m.definition AS ProcDDL
FROM sys.procedures p
JOIN sys.sql_modules m ON p.object_id = m.object_id
WHERE p.is_ms_shipped = 0
ORDER BY SCHEMA_NAME(p.schema_id), p.name;

-----4. Script CREATE TABLE 
;WITH ColumnList AS (
    SELECT
        t.object_id,
        t.name                      AS TableName,
        SCHEMA_NAME(t.schema_id)    AS SchemaName,
        c.column_id,
        c.name                      AS ColumnName,
        TYPE_NAME(c.user_type_id)   AS DataType,
        c.max_length,
        c.precision,
        c.scale,
        c.is_nullable,
        c.is_identity
    FROM sys.tables  AS t
    JOIN sys.columns AS c ON t.object_id = c.object_id
    WHERE t.is_ms_shipped = 0
)
SELECT
    'CREATE TABLE ' 
        + QUOTENAME(c.SchemaName) + '.' + QUOTENAME(c.TableName) 
        + CHAR(13) + CHAR(10) + '(' + CHAR(13) + CHAR(10)
        + STUFF((
            SELECT CHAR(9) + ', ' 
                   + QUOTENAME(c2.ColumnName) + ' ' 
                   + CASE 
                        WHEN c2.DataType IN ('char','varchar','nchar','nvarchar','binary','varbinary') THEN
                            c2.DataType + '(' +
                                CASE 
                                    WHEN c2.max_length = -1 THEN 'MAX'
                                    WHEN c2.DataType IN ('nchar','nvarchar') THEN CAST(c2.max_length / 2 AS varchar(10))
                                    ELSE CAST(c2.max_length AS varchar(10))
                                END + ')'
                        WHEN c2.DataType IN ('decimal','numeric') THEN
                            c2.DataType + '(' + CAST(c2.precision AS varchar(10)) + ',' + CAST(c2.scale AS varchar(10)) + ')'
                        WHEN c2.DataType IN ('datetime2','datetimeoffset','time') THEN
                            c2.DataType + '(' + CAST(c2.scale AS varchar(10)) + ')'
                        ELSE
                            c2.DataType
                     END + ' '
                     + CASE WHEN c2.is_nullable = 1 THEN 'NULL' ELSE 'NOT NULL' END
                     + CASE WHEN c2.is_identity = 1 THEN ' IDENTITY(1,1)' ELSE '' END
                     + CHAR(13) + CHAR(10)
            FROM ColumnList c2
            WHERE c2.object_id = c.object_id
            ORDER BY c2.column_id
            FOR XML PATH(''), TYPE
        ).value('.','nvarchar(max)'), 1, 3, '  ')
        + ')' + CHAR(13) + CHAR(10) + 'GO' AS CreateTableDDL
FROM ColumnList c
GROUP BY c.object_id, c.SchemaName, c.TableName
ORDER BY c.SchemaName, c.TableName;

-----5. Script PRIMARY KEY constraints
SELECT
    'ALTER TABLE ' 
        + QUOTENAME(SCHEMA_NAME(t.schema_id)) + '.' + QUOTENAME(t.name)
        + ' ADD CONSTRAINT ' + QUOTENAME(k.name)
        + ' PRIMARY KEY ' 
        + CASE WHEN i.type = 1 THEN 'CLUSTERED ' ELSE 'NONCLUSTERED ' END
        + '('
        + STUFF((
            SELECT ', ' + QUOTENAME(c.name)
            FROM sys.index_columns ic
            JOIN sys.columns       c 
                 ON ic.object_id = c.object_id
                AND ic.column_id = c.column_id
            WHERE ic.object_id = t.object_id
              AND ic.index_id  = i.index_id
            ORDER BY ic.key_ordinal
            FOR XML PATH(''), TYPE
        ).value('.','nvarchar(max)'), 1, 2, '')
        + ');' AS PkDDL
FROM sys.key_constraints k
JOIN sys.tables        t ON k.parent_object_id  = t.object_id
JOIN sys.indexes       i ON k.parent_object_id  = i.object_id
                         AND k.unique_index_id  = i.index_id
WHERE k.type = 'PK'
  AND t.is_ms_shipped = 0
ORDER BY SCHEMA_NAME(t.schema_id), t.name;

-----6. Script FOREIGN KEY constraints
SELECT
    'ALTER TABLE ' 
        + QUOTENAME(SCHEMA_NAME(tp.schema_id)) + '.' + QUOTENAME(tp.name)
        + ' WITH CHECK ADD CONSTRAINT ' + QUOTENAME(fk.name)
        + ' FOREIGN KEY ('
        + STUFF((
            SELECT ', ' + QUOTENAME(cp.name)
            FROM sys.foreign_key_columns fkc2
            JOIN sys.columns cp
                 ON fkc2.parent_object_id  = cp.object_id
                AND fkc2.parent_column_id = cp.column_id
            WHERE fkc2.constraint_object_id = fk.object_id
            ORDER BY fkc2.constraint_column_id
            FOR XML PATH(''), TYPE
        ).value('.','nvarchar(max)'), 1, 2, '')
        + ') REFERENCES '
        + QUOTENAME(SCHEMA_NAME(tr.schema_id)) + '.' + QUOTENAME(tr.name)
        + ' ('
        + STUFF((
            SELECT ', ' + QUOTENAME(cr.name)
            FROM sys.foreign_key_columns fkc3
            JOIN sys.columns cr
                 ON fkc3.referenced_object_id  = cr.object_id
                AND fkc3.referenced_column_id = cr.column_id
            WHERE fkc3.constraint_object_id = fk.object_id
            ORDER BY fkc3.constraint_column_id
            FOR XML PATH(''), TYPE
        ).value('.','nvarchar(max)'), 1, 2, '')
        + ');' AS FkDDL
FROM sys.foreign_keys fk
JOIN sys.tables      tp ON fk.parent_object_id    = tp.object_id
JOIN sys.tables      tr ON fk.referenced_object_id = tr.object_id
WHERE tp.is_ms_shipped = 0
ORDER BY SCHEMA_NAME(tp.schema_id), tp.name, fk.name;

-----7. Script non-constraint indexes (nonclustered, etc.)
SELECT
    'CREATE ' 
        + CASE WHEN i.is_unique = 1 THEN 'UNIQUE ' ELSE '' END
        + CASE 
            WHEN i.type = 1 THEN 'CLUSTERED '
            WHEN i.type = 2 THEN 'NONCLUSTERED '
            ELSE ''
          END
        + 'INDEX ' + QUOTENAME(i.name)
        + ' ON ' + QUOTENAME(SCHEMA_NAME(t.schema_id)) + '.' + QUOTENAME(t.name)
        + ' ('
        + STUFF((
            SELECT ', ' + QUOTENAME(c.name)
                   + CASE WHEN ic.is_descending_key = 1 THEN ' DESC' ELSE ' ASC' END
            FROM sys.index_columns ic
            JOIN sys.columns       c
                 ON ic.object_id = c.object_id
                AND ic.column_id = c.column_id
            WHERE ic.object_id = t.object_id
              AND ic.index_id  = i.index_id
              AND ic.is_included_column = 0
            ORDER BY ic.key_ordinal
            FOR XML PATH(''), TYPE
        ).value('.','nvarchar(max)'), 1, 2, '')
        + ')'
        + ISNULL(
            ' INCLUDE (' +
            STUFF((
                SELECT ', ' + QUOTENAME(c2.name)
                FROM sys.index_columns ic2
                JOIN sys.columns       c2
                     ON ic2.object_id = c2.object_id
                    AND ic2.column_id = c2.column_id
                WHERE ic2.object_id = t.object_id
                  AND ic2.index_id  = i.index_id
                  AND ic2.is_included_column = 1
                ORDER BY ic2.index_column_id
                FOR XML PATH(''), TYPE
            ).value('.','nvarchar(max)'), 1, 2, '') + ')'
        , '')
        + CASE WHEN i.filter_definition IS NOT NULL THEN ' WHERE ' + i.filter_definition ELSE '' END
        + ';' AS IndexDDL
FROM sys.indexes i
JOIN sys.tables  t ON i.object_id = t.object_id
WHERE t.is_ms_shipped      = 0
  AND i.is_primary_key     = 0
  AND i.is_unique_constraint = 0
  AND i.name IS NOT NULL
ORDER BY SCHEMA_NAME(t.schema_id), t.name, i.name;

-----8. Script table triggers
SELECT
    '/* ' + t.name + ' */' + CHAR(13) + CHAR(10) +
    m.definition AS TableTriggerDDL
FROM sys.triggers    tr
JOIN sys.tables      t  ON tr.parent_id  = t.object_id
JOIN sys.sql_modules m  ON tr.object_id  = m.object_id
WHERE tr.is_ms_shipped = 0
ORDER BY SCHEMA_NAME(t.schema_id), t.name, tr.name;
