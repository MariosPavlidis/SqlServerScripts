declare @table_name varchar(200) =''
select sc.name, o.name,max(row_count) rows,min(create_date) create_Date, sum(reserved_page_count)*8.0/1024.0 MB,count(*) indexes
from sys.dm_db_partition_stats s join sys.objects o on o.object_id=s.object_id 
JOIN SYS.INDEXES I ON I.index_id=S.index_id AND I.object_id=O.object_id
JOIN sys.schemas sc on sc.schema_id=o.schema_id
and is_ms_shipped!=1
AND o.type_desc='USER_TABLE'
and o.name=@table_name
group by  sc.name, o.name
order by 3 desc