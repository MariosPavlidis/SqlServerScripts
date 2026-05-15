-- ============================================================
-- SQL Server → Oracle Migration: Table Export Inventory
-- ============================================================
-- Run on the SOURCE database
-- ============================================================

WITH

-- Step 1: Pre-aggregate size and row counts per table
table_sizes AS
(
    SELECT
        t.object_id,
        SUM(p.rows)          AS estimated_rows,
        SUM(a.total_pages)   AS total_pages,
        SUM(a.used_pages)    AS used_pages
    FROM sys.tables           t
    JOIN sys.indexes          i  ON i.object_id = t.object_id
                                AND i.index_id IN (0, 1)
    JOIN sys.partitions       p  ON p.object_id = t.object_id
                                AND p.index_id  = i.index_id
    JOIN sys.allocation_units a  ON a.container_id =
                                    CASE
                                        WHEN p.partition_id IS NOT NULL
                                        THEN p.partition_id
                                        ELSE p.hobt_id
                                    END
    GROUP BY t.object_id
),

-- Step 2: Non-compliant columns summary per table
noncompliant AS
(
    SELECT
        c.TABLE_SCHEMA,
        c.TABLE_NAME,
        COUNT(*)                                             AS noncompliant_col_count,
        STRING_AGG(
            c.COLUMN_NAME + ' [' + c.DATA_TYPE +
            CASE
                WHEN c.CHARACTER_MAXIMUM_LENGTH = -1
                    THEN '(MAX)'
                WHEN c.CHARACTER_MAXIMUM_LENGTH IS NOT NULL
                    THEN '(' + CAST(c.CHARACTER_MAXIMUM_LENGTH AS VARCHAR) + ')'
                ELSE ''
            END + ']',
            ', '
        ) WITHIN GROUP (ORDER BY c.COLUMN_NAME)             AS noncompliant_columns,
        MAX(CASE WHEN c.DATA_TYPE IN (
                'sql_variant','hierarchyid','geography','geometry')
            THEN 1 ELSE 0 END)                              AS has_critical,
        MAX(CASE WHEN c.DATA_TYPE IN (
                'varbinary','binary','image','timestamp','xml','datetimeoffset')
            THEN 1 ELSE 0 END)                              AS has_high,
        MAX(CASE WHEN c.DATA_TYPE IN (
                'ntext','text','uniqueidentifier',
                'datetime','datetime2','money','smallmoney')
            THEN 1 ELSE 0 END)                              AS has_medium
    FROM INFORMATION_SCHEMA.COLUMNS c
    JOIN INFORMATION_SCHEMA.TABLES  t
        ON  t.TABLE_SCHEMA = c.TABLE_SCHEMA
        AND t.TABLE_NAME   = c.TABLE_NAME
        AND t.TABLE_TYPE   = 'BASE TABLE'
    WHERE c.DATA_TYPE IN (
        'varbinary','binary','image','timestamp',
        'nvarchar','nchar','ntext','text',
        'xml','uniqueidentifier','sql_variant','hierarchyid',
        'geography','geometry',
        'datetime','datetime2','datetimeoffset','smalldatetime','time',
        'money','smallmoney','tinyint','bit','real','float'
    )
    GROUP BY c.TABLE_SCHEMA, c.TABLE_NAME
),

-- Step 3: Column counts per table
col_counts AS
(
    SELECT
        TABLE_SCHEMA,
        TABLE_NAME,
        COUNT(*) AS total_columns
    FROM INFORMATION_SCHEMA.COLUMNS
    GROUP BY TABLE_SCHEMA, TABLE_NAME
)

-- ============================================================
-- Final output
-- ============================================================
SELECT
    ROW_NUMBER() OVER (
        ORDER BY
            ISNULL(nc.has_critical, 0) ASC,
            ISNULL(nc.has_high,     0) ASC,
            ISNULL(nc.has_medium,   0) ASC,
            ts.estimated_rows          ASC
    )                                                        AS export_order,

    s.name                                                   AS schema_name,
    t.name                                                   AS table_name,
    s.name + '.' + t.name                                   AS full_name,

    -- Size
    ts.estimated_rows                                        AS estimated_rows,
    CAST((ts.total_pages * 8.0) / 1024 AS DECIMAL(12,2))    AS total_size_mb,
    CAST((ts.used_pages  * 8.0) / 1024 AS DECIMAL(12,2))    AS used_size_mb,

    -- Columns
    ISNULL(cc.total_columns,          0)                     AS total_columns,
    ISNULL(nc.noncompliant_col_count, 0)                     AS noncompliant_columns,
    ISNULL(nc.noncompliant_columns, 'none')                  AS noncompliant_column_detail,

    -- Structure flags
    CASE WHEN EXISTS (
        SELECT 1 FROM sys.identity_columns ic
        WHERE ic.object_id = t.object_id
    ) THEN 'YES' ELSE 'NO' END                               AS has_identity,

    CASE WHEN EXISTS (
        SELECT 1 FROM sys.indexes ix
        WHERE ix.object_id      = t.object_id
          AND ix.is_primary_key = 1
    ) THEN 'YES' ELSE 'NO' END                               AS has_primary_key,

    CASE WHEN EXISTS (
        SELECT 1 FROM sys.foreign_keys fk
        WHERE fk.parent_object_id = t.object_id
    ) THEN 'YES' ELSE 'NO' END                               AS has_outgoing_fk,

    CASE WHEN EXISTS (
        SELECT 1 FROM sys.foreign_keys fk
        WHERE fk.referenced_object_id = t.object_id
    ) THEN 'YES' ELSE 'NO' END                               AS is_referenced_by_fk,

    -- Severity numeric
    CASE
        WHEN ISNULL(nc.has_critical, 0) = 1               THEN 1
        WHEN ISNULL(nc.has_high,     0) = 1               THEN 2
        WHEN ISNULL(nc.has_medium,   0) = 1               THEN 3
        WHEN ISNULL(nc.noncompliant_col_count, 0) > 0     THEN 4
        ELSE                                                    0
    END                                                      AS severity_level,

    -- Severity label
    CASE
        WHEN ISNULL(nc.has_critical, 0) = 1               THEN '1 - CRITICAL'
        WHEN ISNULL(nc.has_high,     0) = 1               THEN '2 - HIGH'
        WHEN ISNULL(nc.has_medium,   0) = 1               THEN '3 - MEDIUM'
        WHEN ISNULL(nc.noncompliant_col_count, 0) > 0     THEN '4 - LOW'
        ELSE                                                    '0 - CLEAN'
    END                                                      AS migration_status,

    -- Action required
    CASE
        WHEN ISNULL(nc.has_critical, 0) = 1
            THEN 'Manual redesign — do not export yet'
        WHEN ISNULL(nc.has_high, 0) = 1
         AND nc.noncompliant_columns LIKE '%varbinary%'
            THEN 'Transform binary columns — separate LOB export pass'
        WHEN ISNULL(nc.has_high,   0) = 1
            THEN 'Convert types before export'
        WHEN ISNULL(nc.has_medium, 0) = 1
            THEN 'Minor conversion — review date and money columns'
        ELSE
            'No transformation needed'
    END                                                      AS action_required,

    -- Suggested export method
    CASE
        WHEN ISNULL(nc.has_critical, 0) = 1  THEN 'On hold — redesign first'
        WHEN ts.estimated_rows > 5000000      THEN 'BCP native — batch export'
        WHEN ts.estimated_rows > 500000       THEN 'BCP character format'
        ELSE                                       'SSMS Export Wizard or INSERT script'
    END                                                      AS suggested_export_method

FROM sys.tables     t
JOIN sys.schemas    s   ON s.schema_id  = t.schema_id
JOIN table_sizes    ts  ON ts.object_id = t.object_id
LEFT JOIN noncompliant nc ON nc.TABLE_SCHEMA = s.name
                          AND nc.TABLE_NAME  = t.name
LEFT JOIN col_counts   cc ON cc.TABLE_SCHEMA = s.name
                          AND cc.TABLE_NAME  = t.name
WHERE
    t.is_ms_shipped = 0
    AND t.type      = 'U'
    -- Exclude migration tracking tables
    AND t.name NOT IN (
        'MIGRATION_LOG',
        'MIGRATION_EXPORT_LIST',
        'MIGRATION_ERRORS'
    )

ORDER BY export_order;