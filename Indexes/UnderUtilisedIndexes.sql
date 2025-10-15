SELECT DB_NAME(s.database_id) AS 'database_name', OBJECT_NAME(s.object_id) AS 'table_name',
i.name AS 'index_name',
s.user_seeks, s.user_scans, s.user_lookups, s.user_updates,
s.last_user_seek, s.last_user_scan, s.last_user_lookup, s.last_user_update
FROM sys.dm_db_index_usage_stats AS s
JOIN sys.indexes AS i ON s.index_id = i.index_id
AND s.object_id = i.object_id
WHERE s.database_id = DB_ID()
AND s.user_updates > (s.user_seeks + s.user_scans + s.user_lookups)
AND s.index_id > 1
order by 2;
GO