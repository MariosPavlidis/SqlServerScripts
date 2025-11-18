DECLARE @db        sysname      = N'YourDB';      -- database
DECLARE @targetMB  int          = 1024;           -- shrink target
DECLARE @path      nvarchar(260)= N'';            -- backup folder. leave empty for NUL

SET NOCOUNT ON;

/* Validate DB */
IF DB_ID(@db) IS NULL
    RAISERROR('Database not found',16,1);

IF @db IN (N'master',N'model',N'msdb',N'tempdb')
    RAISERROR('System DB not supported',16,1);

/* Resolve recovery model */
DECLARE @rm sysname =
(SELECT recovery_model_desc FROM sys.databases WHERE name=@db);

/* Resolve backup target */
DECLARE @isNullPath bit = CASE WHEN ISNULL(LTRIM(RTRIM(@path)),N'') = N'' THEN 1 ELSE 0 END;
DECLARE @ts varchar(30) = CONVERT(varchar(30),SYSDATETIME(),112) 
                           + '_' + REPLACE(CONVERT(varchar(8),SYSDATETIME(),108),':','');

DECLARE @file1 nvarchar(4000), @file2 nvarchar(4000);

IF @isNullPath = 1
BEGIN
    SET @file1 = N'NUL';
    SET @file2 = N'NUL';
END
ELSE
BEGIN
    IF RIGHT(@path,1) NOT IN ('\','/')
        SET @path = @path + N'\';

    SET @file1 = @path + @db + N'_log_' + @ts + N'_1.trn';
    SET @file2 = @path + @db + N'_log_' + @ts + N'_2.trn';
END;

/* Log backups if FULL/BULK_LOGGED */
IF @rm IN (N'FULL',N'BULK_LOGGED')
BEGIN
    DECLARE @b1 nvarchar(max)=N'BACKUP LOG ' + QUOTENAME(@db) 
        + N' TO DISK=''' + @file1 + N''' WITH INIT,STATS=1;';
    DECLARE @b2 nvarchar(max)=N'BACKUP LOG ' + QUOTENAME(@db) 
        + N' TO DISK=''' + @file2 + N''' WITH INIT,STATS=1;';

    PRINT 'Backup 1 -> ' + @file1;
    EXEC(@b1);

    PRINT 'Backup 2 -> ' + @file2;
    EXEC(@b2);
END
ELSE
    PRINT 'Database not in FULL/BULK_LOGGED. Skipping log backups.';

/* Shrink log */
DECLARE @file sysname, @cmd nvarchar(max);

DECLARE c CURSOR LOCAL FAST_FORWARD FOR
SELECT mf.name
FROM sys.master_files mf
WHERE mf.database_id=DB_ID(@db) AND mf.type_desc='LOG';

OPEN c; FETCH NEXT FROM c INTO @file;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @cmd = N'USE ' + QUOTENAME(@db) + N';
               DBCC SHRINKFILE(' + QUOTENAME(@file) + N',' + CAST(@targetMB AS nvarchar(12)) + N') WITH NO_INFOMSGS;';
    PRINT 'Shrinking ' + @file + ' to ' + CAST(@targetMB AS varchar(12)) + ' MB';
    EXEC(@cmd);

    FETCH NEXT FROM c INTO @file;
END

CLOSE c; DEALLOCATE c;

/* Report */
SELECT mf.name AS LogicalFile,
       mf.size*8/1024 AS SizeMB
FROM sys.master_files mf
WHERE mf.database_id=DB_ID(@db) AND mf.type_desc='LOG';
