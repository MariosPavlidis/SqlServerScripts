SELECT 
    d.name AS DatabaseName,
    CONVERT(DECIMAL(10,2), SUM(mf.size) * 8 / 1024.0) AS TotalSizeMB,
    CONVERT(DECIMAL(10,2), SUM(mf.size - mf.fileproperty(mf.name,'SpaceUsed')) * 8 / 1024.0) AS FreeSpaceMB,
    CONVERT(DECIMAL(10,2),
        (SUM(mf.size - mf.fileproperty(mf.name,'SpaceUsed')) * 100.0) / NULLIF(SUM(mf.size),0)
    ) AS FreePct
FROM sys.databases d
JOIN sys.master_files mf ON d.database_id = mf.database_id
WHERE d.state = 0   -- online only
GROUP BY d.name
ORDER BY FreePct ASC;
