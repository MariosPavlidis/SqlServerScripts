 SELECT DB_NAME() AS Database_Name
, sc.name AS Schema_Name
, o.name AS Table_Name
, pki.name AS Index_Name
, pki.type_desc AS Index_Type
FROM sys.objects o
INNER JOIN sys.indexes pki ON pki.object_id = o.object_id
INNER JOIN sys.indexes cli ON cli.object_id = o.object_id
INNER JOIN sys.schemas sc ON o.schema_id = sc.schema_id
WHERE pki.is_primary_key = 1
AND cli.index_id = 0
AND o.type = 'U'
ORDER BY o.name