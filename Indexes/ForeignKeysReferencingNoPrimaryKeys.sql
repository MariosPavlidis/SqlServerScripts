SELECT 
    f.name AS ForeignKeyName,
    OBJECT_SCHEMA_NAME(f.parent_object_id) AS FK_Schema,
    OBJECT_NAME(f.parent_object_id) AS FK_Table,
    OBJECT_SCHEMA_NAME(f.referenced_object_id) AS Referenced_Schema,
    OBJECT_NAME(f.referenced_object_id) AS Referenced_Table,
    pk.name AS ReferencedConstraintName,
    pk.type_desc AS ReferencedConstraintType
FROM sys.foreign_keys AS f
JOIN sys.objects AS pk
    ON f.referenced_object_id = pk.parent_object_id
   AND f.key_index_id = (
        SELECT i.index_id 
        FROM sys.indexes i 
        WHERE i.object_id = pk.parent_object_id 
          AND i.is_unique = 1 
          AND i.index_id = f.key_index_id
     )
WHERE pk.type_desc <> 'PRIMARY_KEY_CONSTRAINT'
ORDER BY FK_Schema, FK_Table, f.name;
