SELECT 
    s.name AS session_name,
    t.target_name,
    CAST(t.target_data AS XML).value('(/EventFileTarget/File/@name)[1]', 'nvarchar(4000)') AS full_path,
    CAST(t.target_data AS XML).value('(/EventFileTarget/File/@maxFileSize)[1]', 'int') AS max_file_size_mb,
    CAST(t.target_data AS XML).value('(/EventFileTarget/File/@maxRolloverFiles)[1]', 'int') AS rollover_files
FROM sys.dm_xe_sessions s
JOIN sys.dm_xe_session_targets t 
    ON s.address = t.event_session_address
WHERE t.target_name = 'event_file';