SELECT
    c.column_id,
    c.name                          AS column_name,
    t.name                          AS data_type,
    c.max_length,
    c.precision,
    c.scale,
    c.is_nullable,
    c.is_identity,
    c.is_computed,
    c.collation_name
FROM sys.columns c
JOIN sys.types   t ON c.user_type_id = t.user_type_id
--WHERE c.object_id = OBJECT_ID(N'xxxxx')
ORDER BY c.column_id;
