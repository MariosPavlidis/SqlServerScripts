SELECT 'Create Index IX_'+ A.Table_Name  + '_'+ Column_Name + ' ON cmp.' + TAble_name +'('+Column_Name+');',
* from ( 
SELECT
   Object_Name(a.parent_object_id) AS Table_Name
   ,b.NAME AS Column_Name
FROM 
   sys.foreign_key_columns a
   ,sys.all_columns b
   ,sys.objects c
WHERE 
   a.parent_column_id = b.column_id
   AND a.parent_object_id = b.object_id
   AND b.object_id = c.object_id
   AND c.is_ms_shipped = 0
EXCEPT
SELECT 
   Object_name(a.Object_id)
   ,b.NAME
FROM 
   sys.index_columns a
   ,sys.all_columns b
   ,sys.objects c
WHERE 
   a.object_id = b.object_id
   AND a.key_ordinal = 1
   AND a.column_id = b.column_id
   AND a.object_id = c.object_id
   AND c.is_ms_shipped = 0
   ) A
GO   