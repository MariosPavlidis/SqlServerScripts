DECLARE @table_name sysname = NULL;  -- NULL = all tables

SELECT
    sc.name AS schema_name,
    o.name  AS table_name,

    SUM(CASE WHEN s.index_id IN (0, 1)
             THEN s.row_count ELSE 0 END) AS [rows],

    o.create_date,

    SUM(s.reserved_page_count) * 8.0 / 1024.0 AS total_reserved_mb,

    SUM(CASE WHEN s.index_id IN (0, 1)
             THEN s.reserved_page_count ELSE 0 END) * 8.0 / 1024.0 AS base_table_reserved_mb,

    SUM(CASE WHEN s.index_id NOT IN (0, 1)
             THEN s.reserved_page_count ELSE 0 END) * 8.0 / 1024.0 AS nonclustered_index_reserved_mb,

    COUNT(DISTINCT s.index_id) AS index_count
FROM sys.dm_db_partition_stats AS s
JOIN sys.objects AS o
    ON o.object_id = s.object_id
JOIN sys.indexes AS i
    ON i.object_id = s.object_id
   AND i.index_id  = s.index_id
JOIN sys.schemas AS sc
    ON sc.schema_id = o.schema_id
WHERE o.is_ms_shipped = 0
  AND o.type = 'U'
  AND i.is_hypothetical = 0
  AND (@table_name IS NULL OR o.name = @table_name)
GROUP BY
    sc.name,
    o.name,
    o.create_date
ORDER BY [rows] DESC;