---Last Backups
SELECT db.name,db.recovery_model_desc,
D.[Database Backup End], datediff(mi,D.[Database Backup Start],D.[Database Backup End]) as [Minutes Duration],
I.[Database Backup End], datediff(ss,I.[Database Backup Start],I.[Database Backup End]) as [Seconds Duration],
L.[Log Backup End] , datediff(ss,L.[Log Backup Start],L.[Log Backup End]) as [Seconds Duration]
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


-- Last CHECKDB completion per database
CREATE TABLE #DBCCResults (
    ParentObject    VARCHAR(255),
    [Object]        VARCHAR(255),
    Field           VARCHAR(255),
    [Value]         VARCHAR(255)
);
 
DECLARE @db SYSNAME;
DECLARE @summary TABLE (DatabaseName SYSNAME, LastCleanDBCC DATETIME);
 
DECLARE c CURSOR FOR
    SELECT name FROM sys.databases WHERE state_desc = 'ONLINE' AND database_id > 4;
OPEN c; FETCH NEXT FROM c INTO @db;
WHILE @@FETCH_STATUS = 0 BEGIN
    TRUNCATE TABLE #DBCCResults;
    INSERT INTO #DBCCResults
        EXEC('DBCC DBINFO([' + @db + ']) WITH TABLERESULTS, NO_INFOMSGS');
    INSERT INTO @summary
        SELECT @db, CAST([Value] AS DATETIME)
        FROM #DBCCResults WHERE Field = 'dbi_dbccLastKnownGood';
    FETCH NEXT FROM c INTO @db;
END
CLOSE c; DEALLOCATE c;
DROP TABLE #DBCCResults;
 
SELECT *, DATEDIFF(DAY, LastCleanDBCC, GETDATE()) AS DaysSinceDBCC
FROM @summary ORDER BY LastCleanDBCC ASC;

