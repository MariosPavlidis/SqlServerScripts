SELECT db.name,db.recovery_model_desc,d.[Database Backup Start],d.[Database Backup End], datediff(mi,d.[Database Backup Start],d.[Database Backup End]) as [Minutes Duration],
cast (datediff(hh,d.[Database Backup End],SYSDATETIME()) as nvarchar)+':'+ right ('000'+cast (datediff(mi,d.[Database Backup End],SYSDATETIME()) % 60 as nvarchar),2) [Since Last Backup],i.[Database Backup Start],i.[Database Backup End], datediff(mi,i.[Database Backup Start],i.[Database Backup End]) as [Minutes Duration],
cast (datediff(hh,i.[Database Backup End],SYSDATETIME()) as nvarchar)+':'+ right ('000'+cast (datediff(mi,i.[Database Backup End],SYSDATETIME()) % 60 as nvarchar),2) [Since Last Backup],
l.[Log Backup Start],l.[Log Backup End] , datediff(ss,l.[Log Backup Start],l.[Log Backup End]) as seconds,
case when db.recovery_model_desc='SIMPLE' then 'SIMPLE RM' else cast (datediff(mi,L.[Log Backup End],SYSDATETIME()) as nvarchar) end [RPO]
from
(select name,recovery_model_desc from sys.databases where name<>'tempdb') db left outer join
(
SELECT sdb.Name AS DatabaseName, max(backup_start_date) as [Database Backup Start],MAX(bus.backup_finish_date) as [Database Backup End]
FROM sys.sysdatabases sdb
LEFT OUTER JOIN msdb.dbo.backupset bus ON bus.database_name = sdb.name
where type='D'
and sdb.dbid<>2
GROUP BY sdb.Name,type) d on d.DatabaseName=db.name
left outer join
(SELECT sdb.Name AS DatabaseName, max(backup_start_date) as [Database Backup Start],MAX(bus.backup_finish_date) as [Database Backup End]
FROM sys.sysdatabases sdb
LEFT OUTER JOIN msdb.dbo.backupset bus ON bus.database_name = sdb.name
where type='I'
and sdb.dbid<>2
GROUP BY sdb.Name,type) I
on d.databaseNAme=i.DatabaseName
left outer join
(SELECT sdb.Name AS DatabaseName, max(backup_start_date) as [Log Backup Start],MAX(bus.backup_finish_date) as [Log Backup End]
FROM sys.sysdatabases sdb
LEFT OUTER JOIN msdb.dbo.backupset bus ON bus.database_name = sdb.name
where type='L'
and sdb.dbid<>2
GROUP BY sdb.Name,type) L
on d.databaseName=l.DatabaseName
GO


