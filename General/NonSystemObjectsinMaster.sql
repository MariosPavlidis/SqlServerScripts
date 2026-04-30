USE master;

SELECT
    s.name                          AS schema_name,
    o.name                          AS object_name,
    o.type_desc                     AS object_type,
    o.create_date,
    o.modify_date,
    OBJECT_DEFINITION(o.object_id)  AS definition   -- for procs/functions/views
FROM sys.objects o
JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.is_ms_shipped = 0
  AND o.type NOT IN ('S', 'IT', 'SQ')  -- exclude system tables, internal tables, service queues
  AND s.name NOT IN ('sys', 'INFORMATION_SCHEMA')
ORDER BY s.name, o.type_desc, o.name;