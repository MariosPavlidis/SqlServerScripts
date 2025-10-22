declare @table_name varchar(200) =''
select sc.name, o.name,max(row_count) rows,min(create_date) create_date, sum(reserved_page_count)*8.0/1024.0 mb,count(*) indexes
from sys.dm_db_partition_stats s join sys.objects o on o.object_id=s.object_id 
join sys.indexes i on i.index_id=s.index_id and i.object_id=o.object_id
join sys.schemas sc on sc.schema_id=o.schema_id
and is_ms_shipped!=1
and o.type_desc='USER_TABLE'
--and o.name=@table_name
group by  sc.name, o.name
order by 3 desc