DECLARE @fill_factor int = 90;
DECLARE @schema_name sysname = N'dbo';
DECLARE @table_name  sysname = N'YourTable';

DECLARE @IndexColumns TABLE
(
    column_name sysname,
    is_included bit
);

-- === INDEX DEFINITION (AUTHORITATIVE) ===
INSERT INTO @IndexColumns (column_name, is_included)
VALUES
    (N'OrderDate', 0),   -- key column
    (N'CustomerID', 0), -- key column
    (N'Status', 1);     -- INCLUDE column

WITH col_sizes AS
(
    SELECT
        c.object_id,
        SUM(
            CASE
                WHEN ty.name IN ('varchar','char')       THEN c.max_length
                WHEN ty.name IN ('nvarchar','nchar')     THEN c.max_length * 2
                WHEN ty.name = 'int'                      THEN 4
                WHEN ty.name = 'bigint'                   THEN 8
                WHEN ty.name = 'smallint'                 THEN 2
                WHEN ty.name = 'tinyint'                  THEN 1
                WHEN ty.name IN ('datetime','smalldatetime') THEN 8
                WHEN ty.name = 'datetime2'                THEN 8
                WHEN ty.name = 'uniqueidentifier'         THEN 16
                ELSE c.max_length
            END
        ) AS row_bytes
    FROM sys.columns c
    JOIN sys.types ty
        ON c.user_type_id = ty.user_type_id
    JOIN @IndexColumns ic
        ON ic.column_name = c.name
    WHERE c.object_id = OBJECT_ID(QUOTENAME(@schema_name) + '.' + QUOTENAME(@table_name))
    group by c.object_id
)
SELECT
    row_bytes + 7 AS estimated_index_row_bytes   -- + row overhead
FROM col_sizes;

SELECT
    t.name                                  AS table_name,
    SUM(p.rows)                             AS row_count,
    (cs.row_bytes + 7)                      AS row_size_bytes,
    CEILING(
        (cs.row_bytes + 7) * SUM(p.rows)
        / (@fill_factor / 100.0)
    ) / 1024.0 / 1024.0                     AS estimated_index_size_MB
FROM sys.tables t
JOIN sys.partitions p
    ON p.object_id = t.object_id
CROSS APPLY
(
    SELECT SUM(row_bytes) AS row_bytes
    FROM
    (
        SELECT
            CASE
                WHEN ty.name IN ('varchar','char')       THEN c.max_length
                WHEN ty.name IN ('nvarchar','nchar')     THEN c.max_length * 2
                WHEN ty.name = 'int'                      THEN 4
                WHEN ty.name = 'bigint'                   THEN 8
                WHEN ty.name = 'smallint'                 THEN 2
                WHEN ty.name = 'tinyint'                  THEN 1
                WHEN ty.name IN ('datetime','smalldatetime') THEN 8
                WHEN ty.name = 'datetime2'                THEN 8
                WHEN ty.name = 'uniqueidentifier'         THEN 16
                ELSE c.max_length
            END AS row_bytes
        FROM sys.columns c
        JOIN sys.types ty
            ON c.user_type_id = ty.user_type_id
        JOIN @IndexColumns ic
            ON ic.column_name = c.name
        WHERE c.object_id = t.object_id
    ) d
) cs
WHERE t.name = @table_name
GROUP BY t.name, cs.row_bytes;
