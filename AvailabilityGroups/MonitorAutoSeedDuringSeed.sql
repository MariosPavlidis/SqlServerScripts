SELECT local_database_name,role_desc,internal_state_desc,transfer_rate_bytes_per_second/1024.0/1024.0 as 'Transfer MB/s',transferred_size_bytes/1024.0/1024.0 as 'MB Transferred',database_size_bytes/1024.0/1024.0 as 'Total MB',cast (transferred_size_bytes as float)/ cast(database_size_bytes as float)*100.0 as '%' ,failure_message 
FROM sys.dm_hadr_physical_seeding_stats;
