/*
  AllIndexInfoWithUsageStatsAndFragmentation.sql
  Extends AllIndexInfoWtihUsageStats.sql by adding physical fragmentation data
  from sys.dm_db_index_physical_stats (LIMITED mode).

  DMVs used:
    sys.dm_db_partition_stats          - row counts and page counts per partition
    sys.dm_db_index_usage_stats        - usage counters reset on service restart
    sys.dm_db_index_physical_stats     - physical fragmentation per partition (LIMITED mode)

  avg_fragmentation_pct is averaged across partitions per index.
  Indexes on tables with fewer than 8 pages return NULL (SQL Server does not
  track fragmentation below that threshold).

  Fragmentation thresholds (standard guidance):
    < 10%   - no action needed
    10-30%  - consider ALTER INDEX ... REORGANIZE
    > 30%   - consider ALTER INDEX ... REBUILD

  Use this script when planning index maintenance.
  For usage stats only (faster) see: AllIndexInfoWtihUsageStats.sql
  Note: slowest of the three index scripts due to dm_db_index_physical_stats.
*/
SELECT
    sc.name                                   AS schema_name,
    o.name                                    AS table_name,
    i.name                                    AS index_name,
    i.type_desc                               AS index_type,
    i.is_unique,
    i.is_primary_key,
    CASE WHEN i.has_filter = 1 THEN i.filter_definition ELSE 'N/A' END AS filter_predicate,

    -- usage since last service start
    COALESCE(MAX(u.user_seeks),   0)          AS user_seeks,
    COALESCE(MAX(u.user_scans),   0)          AS user_scans,
    COALESCE(MAX(u.user_lookups), 0)          AS user_lookups,
    COALESCE(MAX(u.user_updates), 0)          AS user_updates,
    MAX(u.last_user_seek)                     AS last_user_seek,
    MAX(u.last_user_scan)                     AS last_user_scan,
    MAX(u.last_user_lookup)                   AS last_user_lookup,
    MAX(u.last_user_update)                   AS last_user_update,

    MAX(s.row_count)                                                     AS rows_per_index,
    MAX(MAX(s.row_count)) OVER (PARTITION BY o.object_id)               AS rows_per_table,
    SUM(s.used_page_count) * 8.0 / 1024                                 AS index_size_mb,
    SUM(SUM(s.used_page_count)) OVER (PARTITION BY o.object_id) * 8.0 / 1024 AS table_size_mb,
    COUNT(*) OVER (PARTITION BY o.object_id)                            AS index_count,
    -- averaged across partitions; NULL for indexes smaller than 8 pages
    AVG(ips.avg_fragmentation_in_percent)                               AS avg_fragmentation_pct,

    -- key columns
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
        FOR XML PATH(''), TYPE).value('.','nvarchar(max)'),1,2,'')      AS key_columns,
    -- included columns
    STUFF((
        SELECT ', ' + QUOTENAME(c.name)
        FROM sys.index_columns ic
        JOIN sys.columns c
          ON c.object_id = ic.object_id AND c.column_id = ic.column_id
        WHERE ic.object_id = i.object_id
          AND ic.index_id  = i.index_id
          AND ic.is_included_column = 1
        ORDER BY ic.index_column_id
        FOR XML PATH(''), TYPE).value('.','nvarchar(max)'),1,2,'')      AS included_columns,

    MIN(o.create_date)                        AS create_date
FROM sys.dm_db_partition_stats s
JOIN sys.objects o
  ON o.object_id = s.object_id
JOIN sys.indexes i
  ON i.object_id = o.object_id AND i.index_id = s.index_id
LEFT JOIN sys.dm_db_index_usage_stats u
  ON u.database_id = DB_ID()
 AND u.object_id   = i.object_id
 AND u.index_id    = i.index_id
LEFT JOIN sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
  ON ips.object_id        = s.object_id
 AND ips.index_id         = s.index_id
 AND ips.partition_number = s.partition_number
JOIN sys.schemas sc
  ON sc.schema_id = o.schema_id
WHERE o.is_ms_shipped = 0
  AND o.type = 'U'
  AND i.is_hypothetical = 0
GROUP BY
    sc.name, o.name, i.name, i.type_desc, i.is_unique, i.is_primary_key,
    i.has_filter, i.filter_definition, o.object_id, i.object_id, i.index_id
    /* Use for indexes needing maintenance
    having AVG(ips.avg_fragmentation_in_percent) >= 10
    */
ORDER BY table_size_mb DESC, index_size_mb DESC, schema_name, table_name, index_name;
