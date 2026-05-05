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