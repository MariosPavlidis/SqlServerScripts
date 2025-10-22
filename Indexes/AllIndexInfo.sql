/* this query returns all indexes with index size, table size, 
index rows, tablerows, index info (Clusterd/Nonclustered,PK, Unique) 
and all index columns, all included columns and the filter in case of filtered index*/

SELECT
    sc.name                                  AS schema_name,
    o.name                                   AS table_name,
    i.name                                   AS index_name,
    i.type_desc                              AS index_type,
    i.is_unique,
    i.is_primary_key,
    CASE WHEN i.has_filter = 1 THEN i.filter_definition ELSE 'N/A' END AS filter_predicate,
    MAX(s.row_count)                          AS rows_per_index,
    MAX(MAX(s.row_count)) OVER (PARTITION BY o.object_id)              AS rows_per_table,
    SUM(s.used_page_count) * 8.0 / 1024                               AS index_size_mb,
    SUM(SUM(s.used_page_count)) OVER (PARTITION BY o.object_id) * 8.0 / 1024 AS table_size_mb,
    COUNT(*) OVER (PARTITION BY o.object_id)        AS index_count,
    /* key columns in ordinal order */
    STUFF((
        SELECT ', ' + QUOTENAME(c.name)
               + CASE WHEN ic.is_descending_key = 1 THEN ' DESC' ELSE ' ASC' END
        FROM sys.index_columns ic
        JOIN sys.columns c
          ON c.object_id = ic.object_id AND c.column_id = ic.column_id
        WHERE ic.object_id = i.object_id
          AND ic.index_id  = i.index_id
          AND ic.is_included_column = 0
          AND ic.key_ordinal > 0
        ORDER BY ic.key_ordinal
        FOR XML PATH(''), TYPE).value('.','nvarchar(max)'),1,2,'')     AS key_columns,
    /* included columns in definition order */
    STUFF((
        SELECT ', ' + QUOTENAME(c.name)
        FROM sys.index_columns ic
        JOIN sys.columns c
          ON c.object_id = ic.object_id AND c.column_id = ic.column_id
        WHERE ic.object_id = i.object_id
          AND ic.index_id  = i.index_id
          AND ic.is_included_column = 1
        ORDER BY ic.index_column_id
        FOR XML PATH(''), TYPE).value('.','nvarchar(max)'),1,2,'')     AS included_columns,
    MIN(o.create_date)                       AS create_date
FROM sys.dm_db_partition_stats s
JOIN sys.objects o
  ON o.object_id = s.object_id
JOIN sys.indexes i
  ON i.object_id = o.object_id AND i.index_id = s.index_id
JOIN sys.schemas sc
  ON sc.schema_id = o.schema_id
WHERE o.is_ms_shipped = 0
  AND o.type = 'U'
  AND i.is_hypothetical = 0
GROUP BY
    sc.name, o.name, i.name, i.type_desc, i.is_unique, i.is_primary_key,
    i.has_filter, i.filter_definition, o.object_id, i.object_id, i.index_id
ORDER BY table_size_mb DESC, index_size_mb DESC, schema_name, table_name, index_name;
