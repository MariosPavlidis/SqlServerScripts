---Job Owner and next execution
---- Tables are updated every 20 minutes so frequent jobs info might be misleading'
with schedules as (select schedule_id,name as [ScheduleName],enabled as [ScheduleEnabled],'Frequency' = CASE dbo.sysschedules.freq_type
      WHEN 1 THEN 'Once'
      WHEN 4 THEN 'Daily'
      WHEN 8 THEN 'Weekly'
      WHEN 16 THEN 'Monthly'
      WHEN 32 THEN 'Monthly relative'
      WHEN 64 THEN 'When SQLServer Agent starts'
	  WHEN 128 THEN 'Runs when the computer is idle'
   END from dbo.sysschedules),
 jobschedules as (select schedule_id,job_id,'Next Date' = CASE next_run_date
      WHEN 0 THEN null
      ELSE
      substring(convert(varchar(15),next_run_date),1,4) + '/' + 
      substring(convert(varchar(15),next_run_date),5,2) + '/' + 
      substring(convert(varchar(15),next_run_date),7,2)
   END,'Next Time' = CASE len(next_run_time)
      WHEN 1 THEN cast('00:00:0' + right(next_run_time,2) as char(8))
      WHEN 2 THEN cast('00:00:' + right(next_run_time,2) as char(8))
      WHEN 3 THEN cast('00:0' 
            + Left(right(next_run_time,3),1)  
            +':' + right(next_run_time,2) as char (8))
      WHEN 4 THEN cast('00:' 
            + Left(right(next_run_time,4),2)  
            +':' + right(next_run_time,2) as char (8))
      WHEN 5 THEN cast('0' + Left(right(next_run_time,5),1) 
            +':' + Left(right(next_run_time,4),2)  
            +':' + right(next_run_time,2) as char (8))
      WHEN 6 THEN cast(Left(right(next_run_time,6),2) 
            +':' + Left(right(next_run_time,4),2)  
            +':' + right(next_run_time,2) as char (8))
   END from dbo.sysjobschedules),
   jobs as (select job_id,'JobName' =sj.name,'JobEnabled' = enabled,description,'JobOwner' = sl.name from dbo.sysjobs sj, sys.syslogins sl
where sl.sid=sj.owner_sid)
select j.JobName,j.JobEnabled,j.JobOwner,s.ScheduleName,s.Frequency,js.[Next Date],js.[Next Time]
from schedules s right outer join jobschedules js on js.schedule_id=s.schedule_id join jobs j on j.job_id=js.job_id
 order by JobEnabled desc,[Next Date],[Next Time]


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


---- Jopbs Schedule and max duration
--Jobs schedules
USE msdb
Go
SELECT dbo.sysjobs.name AS 'Job Name', 
   'Job Enabled' = CASE dbo.sysjobs.enabled
      WHEN 1 THEN 'Yes'
      WHEN 0 THEN 'No'
   END,
   'Frequency' = CASE dbo.sysschedules.freq_type
      WHEN 1 THEN 'Once'
      WHEN 4 THEN 'Daily'
      WHEN 8 THEN 'Weekly'
      WHEN 16 THEN 'Monthly'
      WHEN 32 THEN 'Monthly relative'
      WHEN 64 THEN 'When SQLServer Agent starts'
   END, 
   'Next Date' = CASE active_start_date
      WHEN 0 THEN null
      ELSE
      substring(convert(varchar(15),active_start_date),1,4) + '/' + 
      substring(convert(varchar(15),active_start_date),5,2) + '/' + 
      substring(convert(varchar(15),active_start_date),7,2)
   END,
   'Next Time' = CASE len(active_start_time)
      WHEN 1 THEN cast('00:00:0' + right(active_start_time,2) as char(8))
      WHEN 2 THEN cast('00:00:' + right(active_start_time,2) as char(8))
      WHEN 3 THEN cast('00:0' 
            + Left(right(active_start_time,3),1)  
            +':' + right(active_start_time,2) as char (8))
      WHEN 4 THEN cast('00:' 
            + Left(right(active_start_time,4),2)  
            +':' + right(active_start_time,2) as char (8))
      WHEN 5 THEN cast('0' 
            + Left(right(active_start_time,5),1) 
            +':' + Left(right(active_start_time,4),2)  
            +':' + right(active_start_time,2) as char (8))
      WHEN 6 THEN cast(Left(right(active_start_time,6),2) 
            +':' + Left(right(active_start_time,4),2)  
            +':' + right(active_start_time,2) as char (8))
   END,
--   active_start_time as 'Start Time',
   CASE len(run_duration)
      WHEN 1 THEN cast('00:00:0'
            + cast(run_duration as char) as char (8))
      WHEN 2 THEN cast('00:00:'
            + cast(run_duration as char) as char (8))
      WHEN 3 THEN cast('00:0' 
            + Left(right(run_duration,3),1)  
            +':' + right(run_duration,2) as char (8))
      WHEN 4 THEN cast('00:' 
            + Left(right(run_duration,4),2)  
            +':' + right(run_duration,2) as char (8))
      WHEN 5 THEN cast('0' 
            + Left(right(run_duration,5),1) 
            +':' + Left(right(run_duration,4),2)  
            +':' + right(run_duration,2) as char (8))
      WHEN 6 THEN cast(Left(right(run_duration,6),2) 
            +':' + Left(right(run_duration,4),2)  
            +':' + right(run_duration,2) as char (8))
   END as 'Max Duration',
    CASE(dbo.sysschedules.freq_subday_interval)
      WHEN 0 THEN 'Once'
      ELSE cast('Every ' 
            + right(dbo.sysschedules.freq_subday_interval,2) 
            + ' '
            +     CASE(dbo.sysschedules.freq_subday_type)
                     WHEN 1 THEN 'Once'
                     WHEN 4 THEN 'Minutes'
                     WHEN 8 THEN 'Hours'
                  END as char(16))
    END as 'Subday Frequency'
FROM dbo.sysjobs 
LEFT OUTER JOIN dbo.sysjobschedules 
ON dbo.sysjobs.job_id = dbo.sysjobschedules.job_id
INNER JOIN dbo.sysschedules ON dbo.sysjobschedules.schedule_id = dbo.sysschedules.schedule_id 
LEFT OUTER JOIN (SELECT job_id, max(run_duration) AS run_duration
      FROM dbo.sysjobhistory
      GROUP BY job_id) Q1
ON dbo.sysjobs.job_id = Q1.job_id
WHERE next_run_time = 0

UNION

SELECT dbo.sysjobs.name AS 'Job Name', 
   'Job Enabled' = CASE dbo.sysjobs.enabled
      WHEN 1 THEN 'Yes'
      WHEN 0 THEN 'No'
   END,
   'Frequency' = CASE dbo.sysschedules.freq_type
      WHEN 1 THEN 'Once'
      WHEN 4 THEN 'Daily'
      WHEN 8 THEN 'Weekly'
      WHEN 16 THEN 'Monthly'
      WHEN 32 THEN 'Monthly relative'
      WHEN 64 THEN 'When SQLServer Agent starts'
   END, 
   'Next Date' = CASE next_run_date
      WHEN 0 THEN null
      ELSE
      substring(convert(varchar(15),next_run_date),1,4) + '/' + 
      substring(convert(varchar(15),next_run_date),5,2) + '/' + 
      substring(convert(varchar(15),next_run_date),7,2)
   END,
   'Next Time' = CASE len(next_run_time)
      WHEN 1 THEN cast('00:00:0' + right(next_run_time,2) as char(8))
      WHEN 2 THEN cast('00:00:' + right(next_run_time,2) as char(8))
      WHEN 3 THEN cast('00:0' 
            + Left(right(next_run_time,3),1)  
            +':' + right(next_run_time,2) as char (8))
      WHEN 4 THEN cast('00:' 
            + Left(right(next_run_time,4),2)  
            +':' + right(next_run_time,2) as char (8))
      WHEN 5 THEN cast('0' + Left(right(next_run_time,5),1) 
            +':' + Left(right(next_run_time,4),2)  
            +':' + right(next_run_time,2) as char (8))
      WHEN 6 THEN cast(Left(right(next_run_time,6),2) 
            +':' + Left(right(next_run_time,4),2)  
            +':' + right(next_run_time,2) as char (8))
   END,
--   next_run_time as 'Start Time',
   CASE len(run_duration)
      WHEN 1 THEN cast('00:00:0'
            + cast(run_duration as char) as char (8))
      WHEN 2 THEN cast('00:00:'
            + cast(run_duration as char) as char (8))
      WHEN 3 THEN cast('00:0' 
            + Left(right(run_duration,3),1)  
            +':' + right(run_duration,2) as char (8))
      WHEN 4 THEN cast('00:' 
            + Left(right(run_duration,4),2)  
            +':' + right(run_duration,2) as char (8))
      WHEN 5 THEN cast('0' 
            + Left(right(run_duration,5),1) 
            +':' + Left(right(run_duration,4),2)  
            +':' + right(run_duration,2) as char (8))
      WHEN 6 THEN cast(Left(right(run_duration,6),2) 
            +':' + Left(right(run_duration,4),2)  
            +':' + right(run_duration,2) as char (8))
   END as 'Max Duration',
    CASE(dbo.sysschedules.freq_subday_interval)
      WHEN 0 THEN 'Once'
      ELSE cast('Every ' 
            + right(dbo.sysschedules.freq_subday_interval,2) 
            + ' '
            +     CASE(dbo.sysschedules.freq_subday_type)
                     WHEN 1 THEN 'Once'
                     WHEN 4 THEN 'Minutes'
                     WHEN 8 THEN 'Hours'
                  END as char(16))
    END as 'Subday Frequency'
FROM dbo.sysjobs 
LEFT OUTER JOIN dbo.sysjobschedules ON dbo.sysjobs.job_id = dbo.sysjobschedules.job_id
INNER JOIN dbo.sysschedules ON dbo.sysjobschedules.schedule_id = dbo.sysschedules.schedule_id 
LEFT OUTER JOIN (SELECT job_id, max(run_duration) AS run_duration
      FROM dbo.sysjobhistory
      GROUP BY job_id) Q1
ON dbo.sysjobs.job_id = Q1.job_id
WHERE next_run_time <> 0
ORDER BY [Next Date],[Next Time]

