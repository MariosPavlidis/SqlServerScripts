declare @datapath varchar(300), @logpath varchar (300) ;
select @datapath=cast (SERVERPROPERTY('InstanceDefaultDataPath') as varchar),
@logpath=cast (SERVERPROPERTY('InstanceDefaultLogPath') as varchar);
SELECT db_name(database_id), name,
physical_name,
'ALTER DATABASE '+db_name(database_id)+
' MODIFY FILE (NAME = '+name+',  FILENAME = '''+case when type=1 then @logpath when type=0 then @datapath end +'\'+reverse(substring(reverse(physical_name),1,charindex('\',reverse(physical_name),1)-1))+''');',
'move "'+physical_name+'" "'+case when type=1 then @logpath when type=0 then @datapath end +'\'+reverse(substring(reverse(physical_name),1,charindex('\',reverse(physical_name),1)-1))
FROM sys.master_files  