DECLARE @tablename sysname = 'Orders';

;WITH idx AS (
    SELECT
        schema_name(o.schema_id) AS [schema],
        o.name                    AS [table],
        ac.name                   AS [column],
        i.name                    AS [index],
        i.type_desc               AS [type],
        ic.is_included_column     AS [included],
        ic.key_ordinal,
        ic.index_column_id,
        ic.is_descending_key,
        ISNULL(i.filter_definition,'n/a') AS [filter],
        i.is_unique               AS [unique],
        i.is_primary_key          AS [PK]
    FROM sys.all_columns ac
    JOIN sys.objects o
      ON ac.object_id = o.object_id
     AND o.is_ms_shipped = 0
    JOIN sys.index_columns ic
      ON ic.object_id = o.object_id
     AND ac.column_id = ic.column_id
    JOIN sys.indexes i
      ON i.object_id = o.object_id
     AND i.index_id   = ic.index_id
    WHERE o.name LIKE @tablename
)
SELECT
    i.[schema],
    i.[table],
    i.[index],
    i.[type],
    i.[unique],
    i.[PK],
    STUFF((
        SELECT
            ',' + ii.[column] + CASE WHEN ii.is_descending_key = 1 THEN ' DESC' ELSE ' ASC' END
        FROM idx ii
        WHERE ii.[table] = i.[table]
          AND ii.[index] = i.[index]
          AND ii.included = 0
        ORDER BY ii.key_ordinal
        FOR XML PATH(''), TYPE
    ).value('.', 'nvarchar(max)'), 1, 1, '') AS [columns],
    ISNULL(STUFF((
        SELECT
            ',' + ii.[column]
        FROM idx ii
        WHERE ii.[table] = i.[table]
          AND ii.[index] = i.[index]
          AND ii.included = 1
        ORDER BY ii.index_column_id
        FOR XML PATH(''), TYPE
    ).value('.', 'nvarchar(max)'), 1, 1, ''), 'n/a') AS [included],
    i.[filter]
FROM idx i
GROUP BY
    i.[schema], i.[table], i.[index], i.[type], i.[filter], i.[unique], i.[PK];
