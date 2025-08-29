SELECT  
    t.name AS table_name,
    SUM(ps.row_count)             AS row_count,
    SUM(ps.reserved_page_count)*8/1024.0 AS reserved_MB
   FROM sys.dm_pdw_nodes_db_partition_stats AS ps
JOIN sys.tables AS t
  ON ps.object_id = t.object_id
WHERE t.object_id = OBJECT_ID('pam.PAM_factWagerEvents_V')
GROUP BY t.name;