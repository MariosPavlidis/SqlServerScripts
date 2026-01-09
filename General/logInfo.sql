declare @dbname nvarchar(100),@sql nvarchar (1000);
declare dbs cursor for
select name from sys.databases where state_desc='ONLINE';
IF OBJECT_ID('tempdb..#logUse') IS NOT NULL
    DROP TABLE #logUse
create table   #logUse ([Database Name] varchar(100),[Log File] VARCHAR(200),[Recovery Model] varchar(10), [Log Reuse Wait] VARCHAR(50),[Disk Total GB] INT, [Disk Available GB] INT, [Log Total MB] int,[Log Used MB] int,[Log Used %] smallint,
[Log MB since las backup] int,[Last Log Backup Start] datetime,[Last Log BackupEnd] datetime, [Last Log Backup MB] int);
OPEN dbs;
FETCH NEXT FROM dbs into @dbname;

WHILE @@FETCH_STATUS=0
BEGIN
set @sql=N'insert into #logUse
select top 1 db_name(SP.database_id),F.physical_name,D.recovery_model_desc,D.log_reuse_wait_desc,OS.total_bytes/1024/1024/1024,OS.available_bytes/1024/1024/1024,total_log_size_in_bytes/1024/1024 ,
used_log_space_in_bytes/1024/1024 ,ROUND(used_log_space_in_percent,2)  ,
log_space_in_bytes_since_last_backup/1024/1024,backup_start_date,backup_finish_date,round(backup_size/1024/1024,0)  from ['+@dbname+'].sys.dm_db_log_space_usage sp JOIN SYS.DATABASES D ON D.database_id=SP.database_id
JOIN sys.master_files f ON  F.database_id=SP.database_id AND F.type_desc=''LOG'' left join msdb.dbo.backupset bs on bs.database_name=d.name and bs.type=''L'' CROSS   APPLY sys.dm_os_volume_stats(f.database_id, f.file_id) OS
order by bs.backup_finish_date desc'

--print @sql
exec sp_executesql @sql
FETCH NEXT FROM dbs into @dbname;  
END;
close dbs;
deallocate dbs;

select l.*, vlf.[VLF Count],vlf.[Active VLF],vlf.[Active VLF Size (MB)],vlf.[In-active VLF],vlf.[In-active VLF Size (MB)],case  when vlf.[VLF Count]>100 then 'Perhaps you should Shrink and recreate Log File' else 'VLF count is not dangerously high' end as 'VLF Status'
from #loguse l join (SELECT [name], 
COUNT(l.database_id) AS 'VLF Count',
SUM(CAST(vlf_active AS INT)) AS 'Active VLF',
SUM(vlf_active*vlf_size_mb) AS 'Active VLF Size (MB)',
COUNT(l.database_id)-SUM(CAST(vlf_active AS INT)) AS 'In-active VLF',
SUM(vlf_size_mb)-SUM(vlf_active*vlf_size_mb) AS 'In-active VLF Size (MB)'
FROM sys.databases s
CROSS APPLY sys.dm_db_log_info(s.database_id) l
GROUP BY [name], s.database_id
) vlf on vlf.name=l.[Database Name]
drop table #loguse