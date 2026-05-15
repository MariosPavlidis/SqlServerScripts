-- ============================================================
-- SQL Server → Oracle Migration: Non-Compliant Column Audit
-- ============================================================
SELECT
    t.TABLE_SCHEMA                          AS schema_name,
    t.TABLE_NAME                            AS table_name,
    c.COLUMN_NAME                           AS column_name,
    c.DATA_TYPE                             AS ss_data_type,
    c.CHARACTER_MAXIMUM_LENGTH              AS max_length,
    c.NUMERIC_PRECISION                     AS num_precision,
    c.NUMERIC_SCALE                         AS num_scale,
    c.IS_NULLABLE                           AS is_nullable,
    c.COLUMN_DEFAULT                        AS column_default,
    c.ORDINAL_POSITION                      AS col_position,

    -- Categorize the incompatibility
    CASE c.DATA_TYPE
        -- Binary / LOB types (biggest problem for manual export)
        WHEN 'varbinary'        THEN 'BINARY_LOB    → Oracle BLOB / RAW(n)'
        WHEN 'binary'           THEN 'BINARY_FIXED   → Oracle RAW(n)'
        WHEN 'image'            THEN 'BINARY_LEGACY  → Oracle BLOB (deprecated in SS too)'
        WHEN 'timestamp'        THEN 'ROWVERSION     → Oracle RAW(8) — NOT a datetime!'

        -- Unicode text
        WHEN 'nvarchar'         THEN 'UNICODE_VAR    → Oracle NVARCHAR2(n) or VARCHAR2(n) if AL32UTF8'
        WHEN 'nchar'            THEN 'UNICODE_FIXED  → Oracle NCHAR(n)'
        WHEN 'ntext'            THEN 'UNICODE_LEGACY → Oracle NCLOB (deprecated in SS)'
        WHEN 'text'             THEN 'TEXT_LEGACY    → Oracle CLOB (deprecated in SS)'

        -- Numeric edge cases
        WHEN 'tinyint'          THEN 'TINYINT        → Oracle NUMBER(3) [0–255 in SS]'
        WHEN 'smallmoney'       THEN 'SMALLMONEY     → Oracle NUMBER(10,4)'
        WHEN 'money'            THEN 'MONEY          → Oracle NUMBER(19,4)'
        WHEN 'real'             THEN 'REAL           → Oracle BINARY_FLOAT'
        WHEN 'float'            THEN 'FLOAT          → Oracle BINARY_DOUBLE or NUMBER'

        -- Date / Time (major source of errors)
        WHEN 'datetime'         THEN 'DATETIME       → Oracle DATE (loses sub-second)'
        WHEN 'datetime2'        THEN 'DATETIME2      → Oracle TIMESTAMP(n)'
        WHEN 'smalldatetime'    THEN 'SMALLDATETIME  → Oracle DATE'
        WHEN 'datetimeoffset'   THEN 'DATETIMEOFFSET → Oracle TIMESTAMP WITH TIME ZONE'
        WHEN 'time'             THEN 'TIME           → Oracle INTERVAL or NUMBER'

        -- Identity / GUIDs
        WHEN 'uniqueidentifier' THEN 'GUID           → Oracle RAW(16) or CHAR(36)'

        -- XML
        WHEN 'xml'              THEN 'XML            → Oracle XMLTYPE'

        -- SQL Server-only types
        WHEN 'sql_variant'      THEN 'SQL_VARIANT    → NO DIRECT EQUIVALENT — redesign required'
        WHEN 'hierarchyid'      THEN 'HIERARCHYID    → NO DIRECT EQUIVALENT — redesign required'
        WHEN 'geography'        THEN 'GEOGRAPHY      → Oracle SDO_GEOMETRY (complex)'
        WHEN 'geometry'         THEN 'GEOMETRY       → Oracle SDO_GEOMETRY (complex)'

        -- Compliant types (no action needed)
        WHEN 'int'              THEN NULL
        WHEN 'bigint'           THEN NULL
        WHEN 'smallint'         THEN NULL
        WHEN 'bit'              THEN NULL  -- Oracle: NUMBER(1) — minor
        WHEN 'decimal'          THEN NULL
        WHEN 'numeric'          THEN NULL
        WHEN 'varchar'          THEN NULL
        WHEN 'char'             THEN NULL
        WHEN 'date'             THEN NULL
        ELSE                         'UNKNOWN        → manual review required'
    END                                     AS migration_issue,

    -- Severity rating
    CASE c.DATA_TYPE
        WHEN 'sql_variant'      THEN '1.CRITICAL'
        WHEN 'hierarchyid'      THEN '1.CRITICAL'
        WHEN 'geography'        THEN '1.CRITICAL'
        WHEN 'geometry'         THEN '1.CRITICAL'
        WHEN 'varbinary'        THEN '2.HIGH'
        WHEN 'image'            THEN '2.HIGH'
        WHEN 'timestamp'        THEN '2.HIGH'
        WHEN 'datetimeoffset'   THEN '2.HIGH'
        WHEN 'xml'              THEN '2.HIGH'
        WHEN 'ntext'            THEN '3.MEDIUM'
        WHEN 'text'             THEN '3.MEDIUM'
        WHEN 'uniqueidentifier' THEN '3.MEDIUM'
        WHEN 'datetime'         THEN '3.MEDIUM'
        WHEN 'datetime2'        THEN '3.MEDIUM'
        WHEN 'money'            THEN '3.MEDIUM'
        WHEN 'smallmoney'       THEN '3.MEDIUM'
        WHEN 'nvarchar'         THEN '4.LOW'
        WHEN 'nchar'            THEN '4.LOW'
        WHEN 'real'             THEN '4.LOW'
        WHEN 'float'            THEN '4.LOW'
        WHEN 'tinyint'          THEN '4.LOW'
        WHEN 'bit'              THEN '4.LOW'
        ELSE                         '5.REVIEW'
    END                                     AS severity,

    -- Suggested Oracle DDL type
    CASE c.DATA_TYPE
        WHEN 'varbinary'        THEN
            CASE WHEN c.CHARACTER_MAXIMUM_LENGTH = -1 OR c.CHARACTER_MAXIMUM_LENGTH > 2000
                 THEN 'BLOB'
                 ELSE 'RAW(' + CAST(c.CHARACTER_MAXIMUM_LENGTH AS VARCHAR(10)) + ')'
            END
        WHEN 'binary'           THEN 'RAW(' + CAST(ISNULL(c.CHARACTER_MAXIMUM_LENGTH, 1) AS VARCHAR(10)) + ')'
        WHEN 'image'            THEN 'BLOB'
        WHEN 'timestamp'        THEN 'RAW(8)'
        WHEN 'nvarchar'         THEN
            CASE WHEN c.CHARACTER_MAXIMUM_LENGTH = -1
                 THEN 'NCLOB'
                 ELSE 'NVARCHAR2(' + CAST(c.CHARACTER_MAXIMUM_LENGTH AS VARCHAR(10)) + ')'
            END
        WHEN 'nchar'            THEN 'NCHAR(' + CAST(ISNULL(c.CHARACTER_MAXIMUM_LENGTH, 1) AS VARCHAR(10)) + ')'
        WHEN 'ntext'            THEN 'NCLOB'
        WHEN 'text'             THEN 'CLOB'
        WHEN 'xml'              THEN 'XMLTYPE'
        WHEN 'uniqueidentifier' THEN 'RAW(16)  /* or CHAR(36) with hyphens */'
        WHEN 'datetime'         THEN 'DATE  /* sub-second precision lost */'
        WHEN 'datetime2'        THEN 'TIMESTAMP(' + CAST(ISNULL(c.DATETIME_PRECISION, 7) AS VARCHAR(2)) + ')'
        WHEN 'datetimeoffset'   THEN 'TIMESTAMP(' + CAST(ISNULL(c.DATETIME_PRECISION, 7) AS VARCHAR(2)) + ') WITH TIME ZONE'
        WHEN 'smalldatetime'    THEN 'DATE'
        WHEN 'time'             THEN 'INTERVAL DAY(0) TO SECOND(' + CAST(ISNULL(c.DATETIME_PRECISION, 7) AS VARCHAR(2)) + ')'
        WHEN 'money'            THEN 'NUMBER(19,4)'
        WHEN 'smallmoney'       THEN 'NUMBER(10,4)'
        WHEN 'tinyint'          THEN 'NUMBER(3)'
        WHEN 'bit'              THEN 'NUMBER(1)  /* 0 or 1 */'
        WHEN 'real'             THEN 'BINARY_FLOAT'
        WHEN 'float'            THEN 'BINARY_DOUBLE'
        WHEN 'sql_variant'      THEN '/* REDESIGN REQUIRED */'
        WHEN 'hierarchyid'      THEN '/* REDESIGN REQUIRED */'
        ELSE                         NULL
    END                                     AS suggested_oracle_type

FROM INFORMATION_SCHEMA.TABLES   t
JOIN INFORMATION_SCHEMA.COLUMNS  c
    ON  c.TABLE_SCHEMA = t.TABLE_SCHEMA
    AND c.TABLE_NAME   = t.TABLE_NAME
WHERE
    t.TABLE_TYPE = 'BASE TABLE'

    -- Comment this filter out to see ALL columns including compliant ones
    AND c.DATA_TYPE IN (
        'varbinary', 'binary', 'image', 'timestamp',
        'nvarchar', 'nchar', 'ntext', 'text',
        'xml', 'uniqueidentifier', 'sql_variant', 'hierarchyid',
        'geography', 'geometry',
        'datetime', 'datetime2', 'datetimeoffset', 'smalldatetime', 'time',
        'money', 'smallmoney', 'tinyint', 'bit', 'real', 'float'
    )

ORDER BY
    CASE c.DATA_TYPE
        WHEN 'sql_variant'  THEN 1
        WHEN 'hierarchyid'  THEN 1
        WHEN 'geography'    THEN 1
        WHEN 'geometry'     THEN 1
        WHEN 'varbinary'    THEN 2
        WHEN 'image'        THEN 2
        WHEN 'timestamp'    THEN 2
        WHEN 'xml'          THEN 2
        WHEN 'datetimeoffset' THEN 2
        ELSE                     3
    END,severity ,
    t.TABLE_SCHEMA,
    t.TABLE_NAME,
    c.ORDINAL_POSITION
	;