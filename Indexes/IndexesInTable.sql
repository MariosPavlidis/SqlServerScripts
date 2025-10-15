declare @tableName varchar(100)='';
   with IDX as (
    SELECT schema_name(o.schema_id) as [SCHEMA],
    O.NAME AS [TABLE],
    AC.NAME AS [COLUMN],
    I.name AS [INDEX],
    I.type_desc AS [TYPE],  
    IC.is_included_column AS [INCLUDED],
    isnull(I.filter_definition,'N/A') AS [FILTER],
    is_unique as [UNIQUE]
   FROM SYS.all_columns AC JOIN SYS.objects O ON AC.object_id=O.object_id  
   JOIN SYS.index_columns IC ON IC.object_id=O.object_id AND AC.column_id=IC.column_id  
   JOIN SYS.indexes I ON I.index_id=IC.index_id AND I.object_id=O.object_id   
   WHERE O.NAME like @tableName)  
   select 
   [SCHEMA],
   [TABLE],
   [INDEX],
   [TYPE],
   [UNIQUE], 
   stuff((select ','+[COLUMN] from IDX ii 
        where ii.[TABLE]=i.[TABLE] and ii.[INDEX]=i.[INDEX] 
        and ii.INCLUDED=0  
        for xml path ('')),1,1,'') as [COLUMNS],  
        isnull(stuff((select ','+[COLUMN] from IDX ii 
                    where ii.[TABLE]=i.[TABLE] 
                    and ii.[INDEX]=i.[INDEX] 
                    and ii.INCLUDED=1  fo
                    r xml path ('')),1,1,''),'N/A') as [INCLUDED],
        [FILTER]  from idx i  
        group by [SCHEMA],[TABLE],[INDEX],[TYPE],[FILTER],[UNIQUE]

