-- ============================================================
-- SQL Server → Oracle Migration: Oracle DDL Generator
-- ============================================================
-- Run on the SOURCE SQL Server database
-- Output: Oracle-compatible CREATE TABLE statements
-- Copy the ddl_statement column results and run on Oracle
-- ============================================================

WITH

-- Step 1: Map every column to its Oracle equivalent
col_map AS
(
    SELECT
        s.name                                              AS schema_name,
        t.name                                              AS table_name,
        c.name                                              AS column_name,
        c.column_id                                         AS col_position,
        c.is_nullable                                       AS is_nullable,

        -- Resolve Oracle data type
        CASE tp.name
            -- Exact matches / trivial
            WHEN 'int'              THEN 'NUMBER(10)'
            WHEN 'bigint'           THEN 'NUMBER(19)'
            WHEN 'smallint'         THEN 'NUMBER(5)'
            WHEN 'tinyint'          THEN 'NUMBER(3)'
            WHEN 'bit'              THEN 'NUMBER(1)'
            WHEN 'decimal'          THEN 'NUMBER('
                                       + CAST(c.precision AS VARCHAR)
                                       + ',' + CAST(c.scale AS VARCHAR) + ')'
            WHEN 'numeric'          THEN 'NUMBER('
                                       + CAST(c.precision AS VARCHAR)
                                       + ',' + CAST(c.scale AS VARCHAR) + ')'
            WHEN 'money'            THEN 'NUMBER(19,4)'
            WHEN 'smallmoney'       THEN 'NUMBER(10,4)'
            WHEN 'float'            THEN 'BINARY_DOUBLE'
            WHEN 'real'             THEN 'BINARY_FLOAT'

            -- Character
           -- Character
WHEN 'char' THEN
    'CHAR(' + CAST(c.max_length AS VARCHAR(10)) + ' CHAR)'

WHEN 'varchar' THEN
    CASE
        WHEN c.max_length = -1 THEN 'CLOB'
        WHEN c.max_length <= 4000 THEN
            'VARCHAR2(' + CAST(c.max_length AS VARCHAR(10)) + ' CHAR)'
        ELSE
            'CLOB'
    END

WHEN 'nchar' THEN
    'NCHAR(' + CAST(c.max_length / 2 AS VARCHAR(10)) + ')'

WHEN 'nvarchar' THEN
    CASE
        WHEN c.max_length = -1 THEN 'NCLOB'
        WHEN c.max_length / 2 <= 4000 THEN
            'NVARCHAR2(' + CAST(c.max_length / 2 AS VARCHAR(10)) + ')'
        ELSE
            'NCLOB'
    END
            WHEN 'text'             THEN 'CLOB'
            WHEN 'ntext'            THEN 'NCLOB'

            -- Date / Time
            WHEN 'date'             THEN 'DATE'
            WHEN 'datetime'         THEN 'DATE'
                                       -- comment added below
            WHEN 'smalldatetime'    THEN 'DATE'
            WHEN 'datetime2'        THEN 'TIMESTAMP('
                                       + CAST(c.scale AS VARCHAR) + ')'
            WHEN 'datetimeoffset'   THEN 'TIMESTAMP('
                                       + CAST(c.scale AS VARCHAR)
                                       + ') WITH TIME ZONE'
            WHEN 'time'             THEN 'INTERVAL DAY(0) TO SECOND('
                                       + CAST(c.scale AS VARCHAR) + ')'

            -- Binary
            WHEN 'binary'           THEN 'RAW('
                                       + CAST(c.max_length AS VARCHAR) + ')'
            WHEN 'varbinary'        THEN
                CASE WHEN c.max_length = -1
                     THEN 'BLOB'
                     ELSE 'RAW(' + CAST(c.max_length AS VARCHAR) + ')'
                END
            WHEN 'image'            THEN 'BLOB'
            WHEN 'timestamp'        THEN 'RAW(8)'
                                       -- SS rowversion, not a datetime

            -- Other
            WHEN 'uniqueidentifier' THEN 'RAW(16)'
            WHEN 'xml'              THEN 'XMLTYPE'
            WHEN 'sql_variant'      THEN '/* UNSUPPORTED: sql_variant */'
            WHEN 'hierarchyid'      THEN '/* UNSUPPORTED: hierarchyid */'
            WHEN 'geography'        THEN '/* UNSUPPORTED: geography — needs SDO_GEOMETRY */'
            WHEN 'geometry'         THEN '/* UNSUPPORTED: geometry — needs SDO_GEOMETRY */'
            ELSE                         '/* UNKNOWN: ' + tp.name + ' */'
        END                                                 AS oracle_type,

        -- Add comment for lossy conversions
        CASE tp.name
            WHEN 'datetime'         THEN ' /* datetime → DATE: sub-second precision lost */'
            WHEN 'smalldatetime'    THEN ' /* smalldatetime → DATE: seconds lost */'
            WHEN 'bit'              THEN ' /* bit → NUMBER(1): 0/1 only */'
            WHEN 'timestamp'        THEN ' /* SS rowversion → RAW(8): not a datetime */'
            WHEN 'uniqueidentifier' THEN ' /* GUID → RAW(16): use HEXTORAW() on load */'
            WHEN 'float'            THEN ' /* float → BINARY_DOUBLE: precision may differ */'
            WHEN 'real'             THEN ' /* real → BINARY_FLOAT: precision may differ */'
            ELSE                         ''
        END                                                 AS conversion_note,

        -- Is this an identity column?
        CASE WHEN ic.object_id IS NOT NULL
             THEN 1 ELSE 0
        END                                                 AS is_identity,
        ISNULL(ic.seed_value,      1)                       AS identity_seed,
        ISNULL(ic.increment_value, 1)                       AS identity_increment,

        -- Default value (simplified — complex defaults need manual review)
        dc.definition                                        AS ss_default

    FROM sys.tables             t
    JOIN sys.schemas            s   ON s.schema_id   = t.schema_id
    JOIN sys.columns            c   ON c.object_id   = t.object_id
    JOIN sys.types              tp  ON tp.user_type_id = c.user_type_id
    LEFT JOIN sys.identity_columns ic
                                    ON ic.object_id  = c.object_id
                                   AND ic.column_id  = c.column_id
    LEFT JOIN sys.default_constraints dc
                                    ON dc.parent_object_id = c.object_id
                                   AND dc.parent_column_id = c.column_id
    WHERE
        t.is_ms_shipped = 0
        AND t.type      = 'U'
        AND t.name NOT IN (
            'MIGRATION_LOG',
            'MIGRATION_EXPORT_LIST',
            'MIGRATION_ERRORS'
        )
),

-- Step 2: Primary key columns per table
pk_cols AS
(
    SELECT
        s.name                                              AS schema_name,
        t.name                                              AS table_name,
        STRING_AGG(c.name, ', ')
            WITHIN GROUP (ORDER BY ic.key_ordinal)          AS pk_columns
    FROM sys.tables             t
    JOIN sys.schemas            s   ON s.schema_id    = t.schema_id
    JOIN sys.indexes            ix  ON ix.object_id   = t.object_id
                                   AND ix.is_primary_key = 1
    JOIN sys.index_columns      ic  ON ic.object_id   = ix.object_id
                                   AND ic.index_id    = ix.index_id
    JOIN sys.columns            c   ON c.object_id    = ic.object_id
                                   AND c.column_id    = ic.column_id
    GROUP BY s.name, t.name
),

-- Step 3: Build column definition lines per table
col_lines AS
(
    SELECT
        schema_name,
        table_name,
        col_position,
        -- Assemble the full column line
        '    '
        + UPPER(column_name)
        + ' '
        + oracle_type
        + CASE WHEN is_identity = 1
               THEN ' GENERATED BY DEFAULT AS IDENTITY (START WITH '
                    + CAST(identity_seed AS VARCHAR)
                    + ' INCREMENT BY '
                    + CAST(identity_increment AS VARCHAR) + ')'
               ELSE ''
          END
        + CASE WHEN is_nullable = 0 THEN ' NOT NULL' ELSE '' END
        + conversion_note                                    AS col_def
    FROM col_map
),

-- Step 4: Aggregate column lines into one block per table
col_blocks AS
(
    SELECT
        schema_name,
        table_name,
        STRING_AGG(col_def, ',' + CHAR(10))
            WITHIN GROUP (ORDER BY col_position)            AS columns_block
    FROM col_lines
    GROUP BY schema_name, table_name
)

-- ============================================================
-- Final: Emit CREATE TABLE statements
-- ============================================================
SELECT
    cb.schema_name,
    cb.table_name,

    -- Full Oracle CREATE TABLE statement
    '-- ----------------------------------------' + CHAR(10)
    + '-- Source: ' + cb.schema_name + '.' + cb.table_name + CHAR(10)
    + '-- ----------------------------------------' + CHAR(10)
    + 'CREATE TABLE '  + UPPER(cb.table_name) + CHAR(10)
    + '(' + CHAR(10)
    + cb.columns_block

    -- Append PRIMARY KEY constraint if one exists
    + CASE WHEN pk.pk_columns IS NOT NULL
           THEN ',' + CHAR(10)
                + '    CONSTRAINT PK_' + UPPER(cb.table_name)
                + ' PRIMARY KEY (' + UPPER(pk.pk_columns) + ')'
           ELSE ''
      END

    + CHAR(10) + ');' + CHAR(10)                            AS ddl_statement

FROM col_blocks         cb
LEFT JOIN pk_cols       pk  ON pk.schema_name = cb.schema_name
                            AND pk.table_name = cb.table_name

ORDER BY cb.schema_name, cb.table_name;