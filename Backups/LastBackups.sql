SELECT db.name,db.recovery_model_desc,D.[Database Backup Start],D.[Database Backup End], datediff(mi,D.[Database Backup Start],D.[Database Backup End]) as [Minutes Duration],
cast (datediff(hh,D.[Database Backup End],SYSDATETIME()) as nvarchar)+':'+ right ('000'+cast (datediff(mi,D.[Database Backup End],SYSDATETIME()) % 60 as nvarchar),2) [Since Last Backup],
I.[Database Backup Start],I.[Database Backup End], datediff(mi,I.[Database Backup Start],I.[Database Backup End]) as [Minutes Duration],
cast (datediff(hh,I.[Database Backup End],SYSDATETIME()) as nvarchar)+':'+ right ('000'+cast (datediff(mi,I.[Database Backup End],SYSDATETIME()) % 60 as nvarchar),2) [Since Last Backup],
L.[Log Backup Start],L.[Log Backup End] , datediff(ss,L.[Log Backup Start],L.[Log Backup End]) as seconds,
case when db.recovery_model_desc='SIMPLE' then 'SIMPLE RM' else cast (datediff(mi,L.[Log Backup End],SYSDATETIME()) as nvarchar) end [RPO]
from
(select name,recovery_model_desc from sys.databases where name<>'tempdb') db left outer join
(
SELECT sdb.name AS DatabaseName, max(backup_start_date) as [Database Backup Start],MAX(bus.backup_finish_date) as [Database Backup End]
FROM sys.sysdatabases sdb
LEFT OUTER JOIN msdb.dbo.backupset bus ON bus.database_name = sdb.name
where type='D'
and sdb.dbid<>2
GROUP BY sdb.name,type) D on D.DatabaseName=db.name
left outer join
(SELECT sdb.name AS DatabaseName, max(backup_start_date) as [Database Backup Start],MAX(bus.backup_finish_date) as [Database Backup End]
FROM sys.sysdatabases sdb
LEFT OUTER JOIN msdb.dbo.backupset bus ON bus.database_name = sdb.name
where type='I'
and sdb.dbid<>2
GROUP BY sdb.name,type) I
on D.DatabaseName=I.DatabaseName
left outer join
(SELECT sdb.name AS DatabaseName, max(backup_start_date) as [Log Backup Start],MAX(bus.backup_finish_date) as [Log Backup End]
FROM sys.sysdatabases sdb
LEFT OUTER JOIN msdb.dbo.backupset bus ON bus.database_name = sdb.name
where type='L'
and sdb.dbid<>2
GROUP BY sdb.name,type) L
on D.DatabaseName=L.DatabaseName
GO
