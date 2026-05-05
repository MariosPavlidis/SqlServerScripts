-- Jobs that have failed at least once in the last 90 days
SELECT
    j.name                              AS JobName,
    j.enabled                           AS IsEnabled,
    SUM(CASE WHEN jh.run_status = 0 THEN 1 ELSE 0 END) AS Failures,
    SUM(CASE WHEN jh.run_status = 1 THEN 1 ELSE 0 END) AS Successes,
    MAX(CAST(CAST(jh.run_date AS VARCHAR(8)) +' '+
        STUFF(STUFF(RIGHT('000000'+CAST(jh.run_time AS VARCHAR(6)),6),3,0,':'),6,0,':')
        AS DATETIME)) AS LastRunDateTime
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobhistory jh ON jh.job_id = j.job_id
WHERE jh.run_date >= CONVERT(INT, CONVERT(VARCHAR, DATEADD(DAY,-90,GETDATE()), 112))
  AND jh.step_id <> 0
GROUP BY j.name, j.enabled
HAVING SUM(CASE WHEN jh.run_status = 0 THEN 1 ELSE 0 END) > 0
ORDER BY Failures DESC;