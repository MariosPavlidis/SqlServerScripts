declare @tablename varchar(100)='';
   with idx as (
    select schema_name(o.schema_id) as [schema],
    o.name as [table],
    ac.name as [column],
    i.name as [index],
    i.type_desc as [type],  
    ic.is_included_column as [included],
    isnull(i.filter_definition,'n/a') as [filter],
    is_unique as [unique], is_primary_key [PK]
   from sys.all_columns ac join sys.objects o on ac.object_id=o.object_id   and o.is_ms_shipped=0
   join sys.index_columns ic on ic.object_id=o.object_id and ac.column_id=ic.column_id  
   join sys.indexes i on i.index_id=ic.index_id and i.object_id=o.object_id   
   --where o.name like @tablename
   )  
   select 
   [schema],
   [table],
   [index],
   [type],
   [unique], [PK],
   stuff((select ','+[column] from idx ii 
        where ii.[table]=i.[table] and ii.[index]=i.[index] 
        and ii.included=0  
        for xml path ('')),1,1,'') as [columns],  
        isnull(stuff((select ','+[column] from idx ii 
                    where ii.[table]=i.[table] 
                    and ii.[index]=i.[index] 
                    and ii.included=1  for xml path ('')),1,1,''),'n/a') as [included],
        [filter]  from idx i  
        group by [schema],[table],[index],[type],[filter],[unique],[PK]

