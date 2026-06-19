-- ============================================================
-- Script 1+2a: Profile columns AND persist to permanent table
-- Run this ONCE - replaces running Script 1 separately
-- ============================================================

DECLARE @schema_name NVARCHAR(128) = 'dbo'
DECLARE @table_name  NVARCHAR(128) = NULL    -- NULL = all tables

-- ------------------------------------------------------------
-- Create permanent profile table if not exists
-- ------------------------------------------------------------
IF OBJECT_ID('dbo.MIGRATION_COL_PROFILE', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MIGRATION_COL_PROFILE
    (
        profile_id           INT IDENTITY(1,1) NOT NULL,
        schema_name          NVARCHAR(128)     NOT NULL,
        table_name           NVARCHAR(128)     NOT NULL,
        column_name          NVARCHAR(128)     NOT NULL,
        ss_type              NVARCHAR(128)     NOT NULL,
        declared_max_length  INT               NULL,
        declared_precision   INT               NULL,
        declared_scale       INT               NULL,
        declared_dt_prec     INT               NULL,
        is_nullable          NVARCHAR(3)       NULL,
        col_position         INT               NULL,
        total_rows           BIGINT            NULL,
        null_count           BIGINT            NULL,
        null_pct             DECIMAL(5,2)      NULL,
        actual_max_length    INT               NULL,
        actual_avg_length    INT               NULL,
        has_unicode          BIT               NULL,
        actual_max_val       NVARCHAR(50)      NULL,
        actual_min_val       NVARCHAR(50)      NULL,
        actual_max_scale     INT               NULL,
        all_values_integer   BIT               NULL,
        fits_in_int          BIT               NULL,
        fits_in_smallint     BIT               NULL,
        has_milliseconds     BIT               NULL,
        has_time_component   BIT               NULL,
        has_tz_offset        BIT               NULL,
        min_date             NVARCHAR(30)      NULL,
        max_date             NVARCHAR(30)      NULL,
        actual_max_bytes     INT               NULL,
        recommended_type     NVARCHAR(200)     NULL,
        recommendation_note  NVARCHAR(500)     NULL,
        profiled_at          DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_MIGRATION_COL_PROFILE
            PRIMARY KEY CLUSTERED (profile_id),
        CONSTRAINT UQ_MIGRATION_COL_PROFILE
            UNIQUE (schema_name, table_name, column_name)
    );
    PRINT 'Created dbo.MIGRATION_COL_PROFILE';
END
ELSE
    PRINT 'dbo.MIGRATION_COL_PROFILE already exists';

-- ------------------------------------------------------------
-- Candidate columns
-- ------------------------------------------------------------
DROP TABLE IF EXISTS #candidate_cols;

SELECT
    t.TABLE_SCHEMA                          AS schema_name,
    t.TABLE_NAME                            AS table_name,
    c.COLUMN_NAME                           AS column_name,
    c.DATA_TYPE                             AS ss_type,
    c.CHARACTER_MAXIMUM_LENGTH              AS declared_max_length,
    c.NUMERIC_PRECISION                     AS declared_precision,
    c.NUMERIC_SCALE                         AS declared_scale,
    c.DATETIME_PRECISION                    AS declared_dt_precision,
    c.IS_NULLABLE                           AS is_nullable,
    c.ORDINAL_POSITION                      AS col_position
INTO #candidate_cols
FROM INFORMATION_SCHEMA.TABLES   t
JOIN INFORMATION_SCHEMA.COLUMNS  c
    ON  c.TABLE_SCHEMA = t.TABLE_SCHEMA
    AND c.TABLE_NAME   = t.TABLE_NAME
WHERE
    t.TABLE_TYPE   = 'BASE TABLE'
    AND t.TABLE_SCHEMA = @schema_name
    AND (@table_name IS NULL OR t.TABLE_NAME = @table_name)
    AND c.DATA_TYPE IN (
        'datetime','datetime2','smalldatetime','datetimeoffset',
        'date','time',
        'nvarchar','nchar','ntext',
        'varchar','char','text',
        'decimal','numeric','float','real','money','smallmoney',
        'int','bigint','smallint','tinyint','bit',
        'uniqueidentifier','varbinary','binary','image',
        'timestamp','xml'
    )
    AND t.TABLE_NAME NOT IN (
        'MIGRATION_LOG','MIGRATION_EXPORT_LIST',
        'MIGRATION_ERRORS','MIGRATION_COL_PROFILE'
    )
    -- Skip already profiled columns so reruns are incremental
    AND NOT EXISTS (
        SELECT 1
        FROM dbo.MIGRATION_COL_PROFILE p
        WHERE p.schema_name = t.TABLE_SCHEMA COLLATE DATABASE_DEFAULT
          AND p.table_name  = t.TABLE_NAME   COLLATE DATABASE_DEFAULT
          AND p.column_name = c.COLUMN_NAME  COLLATE DATABASE_DEFAULT
    );

PRINT CAST(@@ROWCOUNT AS VARCHAR) + ' columns to profile';

-- ------------------------------------------------------------
-- Profiling temp table
-- ------------------------------------------------------------
DROP TABLE IF EXISTS #col_profile;

CREATE TABLE #col_profile
(
    schema_name          NVARCHAR(128),
    table_name           NVARCHAR(128),
    column_name          NVARCHAR(128),
    ss_type              NVARCHAR(128),
    declared_max_length  INT,
    declared_precision   INT,
    declared_scale       INT,
    declared_dt_prec     INT,
    is_nullable          NVARCHAR(3),
    col_position         INT,
    total_rows           BIGINT,
    null_count           BIGINT,
    null_pct             DECIMAL(5,2),
    actual_max_length    INT,
    actual_avg_length    INT,
    has_unicode          BIT,
    actual_max_val       NVARCHAR(50),
    actual_min_val       NVARCHAR(50),
    actual_max_scale     INT,
    all_values_integer   BIT,
    fits_in_int          BIT,
    fits_in_smallint     BIT,
    has_milliseconds     BIT,
    has_time_component   BIT,
    has_tz_offset        BIT,
    min_date             NVARCHAR(30),
    max_date             NVARCHAR(30),
    actual_max_bytes     INT,
    recommended_type     NVARCHAR(200),
    recommendation_note  NVARCHAR(500)
);

-- ------------------------------------------------------------
-- Cursor loop - profile each column
-- ------------------------------------------------------------
DECLARE
    @schema      NVARCHAR(128),
    @table       NVARCHAR(128),
    @column      NVARCHAR(128),
    @type        NVARCHAR(128),
    @decl_len    INT,
    @decl_prec   INT,
    @decl_scale  INT,
    @decl_dtprec INT,
    @nullable    NVARCHAR(3),
    @col_pos     INT,
    @sql         NVARCHAR(MAX),
    @hdr         NVARCHAR(MAX),
    @fullcol     NVARCHAR(256),
    @profiled    INT = 0,
    @errors      INT = 0;

DECLARE col_cursor CURSOR FAST_FORWARD FOR
    SELECT schema_name, table_name, column_name, ss_type,
           declared_max_length, declared_precision, declared_scale,
           declared_dt_precision, is_nullable, col_position
    FROM #candidate_cols
    ORDER BY schema_name, table_name, col_position;

OPEN col_cursor;
FETCH NEXT FROM col_cursor INTO
    @schema, @table, @column, @type,
    @decl_len, @decl_prec, @decl_scale, @decl_dtprec,
    @nullable, @col_pos;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @fullcol = QUOTENAME(@schema) + '.' +
                   QUOTENAME(@table)  + '.' +
                   QUOTENAME(@column)

    PRINT 'Profiling: ' + @fullcol + ' (' + @type + ')'

    SET @hdr =
        'INSERT INTO #col_profile ' +
        '(schema_name, table_name, column_name, ss_type, ' +
        ' declared_max_length, declared_precision, declared_scale, declared_dt_prec, ' +
        ' is_nullable, col_position, ' +
        ' total_rows, null_count, null_pct, ' +
        ' actual_max_length, actual_avg_length, has_unicode, ' +
        ' actual_max_val, actual_min_val, actual_max_scale, ' +
        ' all_values_integer, fits_in_int, fits_in_smallint, ' +
        ' has_milliseconds, has_time_component, has_tz_offset, ' +
        ' min_date, max_date, actual_max_bytes) ' +
        'SELECT ' +
        '''' + REPLACE(@schema, '''', '''''') + ''',' +
        '''' + REPLACE(@table,  '''', '''''') + ''',' +
        '''' + REPLACE(@column, '''', '''''') + ''',' +
        '''' + @type + ''',' +
        CAST(ISNULL(@decl_len,   0) AS VARCHAR) + ',' +
        CAST(ISNULL(@decl_prec,  0) AS VARCHAR) + ',' +
        CAST(ISNULL(@decl_scale, 0) AS VARCHAR) + ',' +
        CAST(ISNULL(@decl_dtprec,0) AS VARCHAR) + ',' +
        '''' + @nullable + ''',' +
        CAST(@col_pos AS VARCHAR) + ','

    -- DATE / TIME
    IF @type IN ('datetime','datetime2','smalldatetime',
                 'datetimeoffset','date','time')
    BEGIN
        SET @sql = @hdr +
        'COUNT(*),' +
        'SUM(CASE WHEN ' + QUOTENAME(@column) + ' IS NULL THEN 1 ELSE 0 END),' +
        'CAST(100.0*SUM(CASE WHEN ' + QUOTENAME(@column) +
            ' IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,2)),' +
        'NULL,NULL,NULL,' +
        'NULL,NULL,NULL,NULL,NULL,NULL,' +
        'MAX(CASE WHEN DATEPART(MILLISECOND,' + QUOTENAME(@column) + ')<>0 ' +
            'OR DATEPART(MICROSECOND,' + QUOTENAME(@column) + ')<>0 ' +
            'THEN 1 ELSE 0 END),' +
        'MAX(CASE WHEN CONVERT(TIME,' + QUOTENAME(@column) +
            ')<>''00:00:00'' THEN 1 ELSE 0 END),' +
        CASE WHEN @type = 'datetimeoffset'
             THEN 'MAX(CASE WHEN DATEPART(TZOFFSET,' + QUOTENAME(@column) +
                  ')<>0 THEN 1 ELSE 0 END),'
             ELSE 'CAST(0 AS BIT),'
        END +
        'CAST(MIN(' + QUOTENAME(@column) + ') AS NVARCHAR(30)),' +
        'CAST(MAX(' + QUOTENAME(@column) + ') AS NVARCHAR(30)),' +
        'NULL ' +
        'FROM ' + QUOTENAME(@schema) + '.' + QUOTENAME(@table)
        -- Uncomment for large tables:
        -- + ' TABLESAMPLE (10 PERCENT) REPEATABLE(42)'
    END

    -- STRING
    ELSE IF @type IN ('nvarchar','nchar','varchar','char','ntext','text')
    BEGIN
        SET @sql = @hdr +
        'COUNT(*),' +
        'SUM(CASE WHEN ' + QUOTENAME(@column) + ' IS NULL THEN 1 ELSE 0 END),' +
        'CAST(100.0*SUM(CASE WHEN ' + QUOTENAME(@column) +
            ' IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,2)),' +
        'MAX(LEN(' + QUOTENAME(@column) + ')),' +
        'CAST(AVG(LEN(' + QUOTENAME(@column) + ')) AS INT),' +
        'MAX(CASE WHEN CAST(' + QUOTENAME(@column) + ' AS NVARCHAR(MAX)) <> ' +
            'CAST(CAST(' + QUOTENAME(@column) +
            ' AS VARCHAR(MAX)) AS NVARCHAR(MAX)) THEN 1 ELSE 0 END),' +
        'NULL,NULL,NULL,NULL,NULL,NULL,' +
        'NULL,NULL,NULL,' +
        'NULL,NULL,' +
        'NULL ' +
        'FROM ' + QUOTENAME(@schema) + '.' + QUOTENAME(@table)
    END

    -- DECIMAL / FLOAT / MONEY
    ELSE IF @type IN ('decimal','numeric','float','real','money','smallmoney')
    BEGIN
        SET @sql = @hdr +
        'COUNT(*),' +
        'SUM(CASE WHEN ' + QUOTENAME(@column) + ' IS NULL THEN 1 ELSE 0 END),' +
        'CAST(100.0*SUM(CASE WHEN ' + QUOTENAME(@column) +
            ' IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,2)),' +
        'NULL,NULL,NULL,' +
        'CAST(MAX(ABS(' + QUOTENAME(@column) + ')) AS NVARCHAR(50)),' +
        'CAST(MIN(' + QUOTENAME(@column) + ') AS NVARCHAR(50)),' +
        'MAX(LEN(CAST(ABS(' + QUOTENAME(@column) + ')-' +
            'FLOOR(ABS(' + QUOTENAME(@column) + ')) AS NVARCHAR(50)))-2),' +
        'CAST(MAX(CASE WHEN ' + QUOTENAME(@column) + '<>' +
            'FLOOR(' + QUOTENAME(@column) + ') THEN 1 ELSE 0 END) AS BIT),' +
        'CAST(MAX(CASE WHEN ABS(' + QUOTENAME(@column) +
            ')>2147483647 THEN 1 ELSE 0 END) AS BIT),' +
        'CAST(MAX(CASE WHEN ABS(' + QUOTENAME(@column) +
            ')>32767 THEN 1 ELSE 0 END) AS BIT),' +
        'NULL,NULL,NULL,' +
        'NULL,NULL,' +
        'NULL ' +
        'FROM ' + QUOTENAME(@schema) + '.' + QUOTENAME(@table)
    END

    -- INTEGER
    ELSE IF @type IN ('int','bigint','smallint','tinyint','bit')
    BEGIN
        SET @sql = @hdr +
        'COUNT(*),' +
        'SUM(CASE WHEN ' + QUOTENAME(@column) + ' IS NULL THEN 1 ELSE 0 END),' +
        'CAST(100.0*SUM(CASE WHEN ' + QUOTENAME(@column) +
            ' IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,2)),' +
        'NULL,NULL,NULL,' +
        'CAST(MAX(' + QUOTENAME(@column) + ') AS NVARCHAR(50)),' +
        'CAST(MIN(' + QUOTENAME(@column) + ') AS NVARCHAR(50)),' +
        '0,CAST(1 AS BIT),' +
        'CAST(MAX(CASE WHEN ABS(CAST(' + QUOTENAME(@column) +
            ' AS BIGINT))>2147483647 THEN 1 ELSE 0 END) AS BIT),' +
        'CAST(MAX(CASE WHEN ABS(CAST(' + QUOTENAME(@column) +
            ' AS BIGINT))>32767 THEN 1 ELSE 0 END) AS BIT),' +
        'NULL,NULL,NULL,' +
        'NULL,NULL,' +
        'NULL ' +
        'FROM ' + QUOTENAME(@schema) + '.' + QUOTENAME(@table)
    END

    -- BINARY
    ELSE IF @type IN ('varbinary','binary','image','timestamp')
    BEGIN
        SET @sql = @hdr +
        'COUNT(*),' +
        'SUM(CASE WHEN ' + QUOTENAME(@column) + ' IS NULL THEN 1 ELSE 0 END),' +
        'CAST(100.0*SUM(CASE WHEN ' + QUOTENAME(@column) +
            ' IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,2)),' +
        'NULL,NULL,NULL,' +
        'NULL,NULL,NULL,NULL,NULL,NULL,' +
        'NULL,NULL,NULL,' +
        'NULL,NULL,' +
        'MAX(DATALENGTH(' + QUOTENAME(@column) + ')) ' +
        'FROM ' + QUOTENAME(@schema) + '.' + QUOTENAME(@table)
    END

    -- OTHER (xml, uniqueidentifier)
    ELSE
    BEGIN
        SET @sql = @hdr +
        'COUNT(*),' +
        'SUM(CASE WHEN ' + QUOTENAME(@column) + ' IS NULL THEN 1 ELSE 0 END),' +
        'CAST(100.0*SUM(CASE WHEN ' + QUOTENAME(@column) +
            ' IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,2)),' +
        'NULL,NULL,NULL,' +
        'NULL,NULL,NULL,NULL,NULL,NULL,' +
        'NULL,NULL,NULL,' +
        'NULL,NULL,' +
        'NULL ' +
        'FROM ' + QUOTENAME(@schema) + '.' + QUOTENAME(@table)
    END

    BEGIN TRY
        EXEC sp_executesql @sql
        SET @profiled += 1
    END TRY
    BEGIN CATCH
        PRINT 'ERROR: ' + @fullcol + ' - ' + ERROR_MESSAGE()
        PRINT 'SQL : ' + ISNULL(@sql,'NULL')
        SET @errors += 1
    END CATCH

    FETCH NEXT FROM col_cursor INTO
        @schema, @table, @column, @type,
        @decl_len, @decl_prec, @decl_scale, @decl_dtprec,
        @nullable, @col_pos;
END

CLOSE col_cursor;
DEALLOCATE col_cursor;

PRINT 'Profiled: ' + CAST(@profiled AS VARCHAR) +
      ' columns, Errors: ' + CAST(@errors AS VARCHAR);

-- ------------------------------------------------------------
-- Derive recommended Oracle types
-- ------------------------------------------------------------
UPDATE #col_profile
SET recommended_type = CASE
    WHEN ss_type = 'date'          THEN 'DATE'
    WHEN ss_type = 'smalldatetime' THEN 'DATE'
    WHEN ss_type IN ('datetime','datetime2')
        THEN CASE
            WHEN has_milliseconds = 1   THEN 'TIMESTAMP(3)'
            WHEN has_time_component = 1 THEN 'DATE'
            ELSE                             'DATE'
        END
    WHEN ss_type = 'datetimeoffset'
        THEN CASE
            WHEN has_milliseconds = 1 THEN 'TIMESTAMP(3) WITH TIME ZONE'
            ELSE                           'TIMESTAMP(0) WITH TIME ZONE'
        END
    WHEN ss_type = 'time'
        THEN 'INTERVAL DAY(0) TO SECOND(3)'
    WHEN ss_type IN ('nvarchar','nchar')
        THEN CASE
            WHEN actual_max_length IS NULL OR actual_max_length = 0 THEN 'VARCHAR2(1)'
            WHEN declared_max_length = -1 AND has_unicode = 1       THEN 'NCLOB'
            WHEN declared_max_length = -1                           THEN 'CLOB'
            WHEN has_unicode = 1
                THEN 'NVARCHAR2(' + CAST(actual_max_length + 10 AS VARCHAR) + ')'
            ELSE
                'VARCHAR2(' + CAST(actual_max_length + 10 AS VARCHAR) + ')'
        END
    WHEN ss_type IN ('varchar','char')
        THEN CASE
            WHEN actual_max_length IS NULL OR actual_max_length = 0 THEN 'VARCHAR2(1)'
            WHEN declared_max_length = -1                           THEN 'CLOB'
            ELSE 'VARCHAR2(' + CAST(actual_max_length + 10 AS VARCHAR) + ')'
        END
    WHEN ss_type IN ('ntext','text')
        THEN CASE WHEN has_unicode = 1 THEN 'NCLOB' ELSE 'CLOB' END
    WHEN ss_type IN ('decimal','numeric')
        THEN CASE
            WHEN all_values_integer = 1
                THEN 'NUMBER(' + CAST(declared_precision AS VARCHAR) + ')'
            WHEN actual_max_scale IS NOT NULL
                 AND actual_max_scale < declared_scale
                THEN 'NUMBER(' + CAST(declared_precision AS VARCHAR) +
                     ',' + CAST(actual_max_scale AS VARCHAR) + ')'
            ELSE 'NUMBER(' + CAST(declared_precision AS VARCHAR) +
                 ',' + CAST(declared_scale AS VARCHAR) + ')'
        END
    WHEN ss_type = 'float'
        THEN CASE
            WHEN actual_max_scale IS NOT NULL AND actual_max_scale <= 6
                THEN 'NUMBER(15,' + CAST(actual_max_scale AS VARCHAR) + ')'
            ELSE 'BINARY_DOUBLE'
        END
    WHEN ss_type = 'real'        THEN 'BINARY_FLOAT'
    WHEN ss_type IN ('money','smallmoney')
        THEN CASE
            WHEN all_values_integer = 1
                THEN 'NUMBER(' +
                     CASE WHEN ss_type='money' THEN '19' ELSE '10' END + ')'
            ELSE 'NUMBER(' +
                 CASE WHEN ss_type='money' THEN '19' ELSE '10' END +
                 ',' + CAST(ISNULL(actual_max_scale,4) AS VARCHAR) + ')'
        END
    WHEN ss_type = 'bigint'      THEN 'NUMBER(19)'
    WHEN ss_type = 'int'         THEN 'NUMBER(10)'
    WHEN ss_type = 'smallint'    THEN 'NUMBER(5)'
    WHEN ss_type = 'tinyint'     THEN 'NUMBER(3)'
    WHEN ss_type = 'bit'         THEN 'NUMBER(1)'
    WHEN ss_type = 'timestamp'   THEN 'RAW(8)'
    WHEN ss_type = 'binary'
        THEN 'RAW(' + CAST(declared_max_length AS VARCHAR) + ')'
    WHEN ss_type = 'varbinary'
        THEN CASE
            WHEN declared_max_length = -1   THEN 'BLOB'
            WHEN actual_max_bytes <= 2000
                THEN 'RAW(' + CAST(actual_max_bytes AS VARCHAR) + ')'
            ELSE 'BLOB'
        END
    WHEN ss_type = 'image'            THEN 'BLOB'
    WHEN ss_type = 'uniqueidentifier' THEN 'RAW(16)'
    WHEN ss_type = 'xml'              THEN 'XMLTYPE'
    ELSE '/* REVIEW: ' + ss_type + ' */'
END,
recommendation_note = CASE
    WHEN ss_type IN ('datetime','datetime2') AND has_milliseconds = 1
        THEN 'TIMESTAMP(3): actual ms data found - DATE would lose precision'
    WHEN ss_type IN ('datetime','datetime2') AND has_milliseconds = 0
         AND has_time_component = 1
        THEN 'DATE: no ms found, has time - DATE sufficient'
    WHEN ss_type IN ('datetime','datetime2') AND has_time_component = 0
        THEN 'DATE: date-only values in practice'
    WHEN ss_type IN ('nvarchar','nchar') AND has_unicode = 0
        THEN 'Downgraded to VARCHAR2: no unicode chars in data'
    WHEN ss_type IN ('nvarchar','nchar') AND has_unicode = 1
         AND actual_max_length < declared_max_length
        THEN 'Sized to actual max+10 (declared: ' +
             CAST(declared_max_length AS VARCHAR) + ')'
    WHEN ss_type IN ('decimal','numeric') AND all_values_integer = 1
        THEN 'No decimal values found - scale dropped'
    WHEN ss_type IN ('decimal','numeric')
         AND actual_max_scale IS NOT NULL
         AND actual_max_scale < declared_scale
        THEN 'Scale reduced ' + CAST(declared_scale AS VARCHAR) +
             ' -> ' + CAST(actual_max_scale AS VARCHAR)
    WHEN ss_type = 'varbinary' AND declared_max_length = -1
         AND actual_max_bytes IS NOT NULL AND actual_max_bytes <= 2000
        THEN 'Declared MAX but fits in RAW(' +
             CAST(actual_max_bytes AS VARCHAR) + ')'
    WHEN null_pct = 100
        THEN 'WARNING: 100% NULL - verify if column still needed'
    WHEN null_pct > 90
        THEN 'NOTE: ' + CAST(null_pct AS VARCHAR) + '% NULL'
    ELSE NULL
END;

-- ------------------------------------------------------------
-- Persist to permanent table using MERGE
-- Allows safe reruns - updates existing, inserts new
-- ------------------------------------------------------------
MERGE dbo.MIGRATION_COL_PROFILE AS target
USING #col_profile AS source
    ON  target.schema_name = source.schema_name
    AND target.table_name  = source.table_name
    AND target.column_name = source.column_name

WHEN MATCHED THEN
    UPDATE SET
        recommended_type    = source.recommended_type,
        recommendation_note = source.recommendation_note,
        total_rows          = source.total_rows,
        null_count          = source.null_count,
        null_pct            = source.null_pct,
        actual_max_length   = source.actual_max_length,
        actual_avg_length   = source.actual_avg_length,
        has_unicode         = source.has_unicode,
        actual_max_val      = source.actual_max_val,
        actual_min_val      = source.actual_min_val,
        actual_max_scale    = source.actual_max_scale,
        all_values_integer  = source.all_values_integer,
        has_milliseconds    = source.has_milliseconds,
        has_time_component  = source.has_time_component,
        has_tz_offset       = source.has_tz_offset,
        min_date            = source.min_date,
        max_date            = source.max_date,
        actual_max_bytes    = source.actual_max_bytes,
        profiled_at         = SYSUTCDATETIME()

WHEN NOT MATCHED BY TARGET THEN
    INSERT
    (
        schema_name, table_name, column_name, ss_type,
        declared_max_length, declared_precision, declared_scale, declared_dt_prec,
        is_nullable, col_position, total_rows, null_count, null_pct,
        actual_max_length, actual_avg_length, has_unicode,
        actual_max_val, actual_min_val, actual_max_scale,
        all_values_integer, fits_in_int, fits_in_smallint,
        has_milliseconds, has_time_component, has_tz_offset,
        min_date, max_date, actual_max_bytes,
        recommended_type, recommendation_note
    )
    VALUES
    (
        source.schema_name, source.table_name, source.column_name, source.ss_type,
        source.declared_max_length, source.declared_precision,
        source.declared_scale, source.declared_dt_prec,
        source.is_nullable, source.col_position,
        source.total_rows, source.null_count, source.null_pct,
        source.actual_max_length, source.actual_avg_length, source.has_unicode,
        source.actual_max_val, source.actual_min_val, source.actual_max_scale,
        source.all_values_integer, source.fits_in_int, source.fits_in_smallint,
        source.has_milliseconds, source.has_time_component, source.has_tz_offset,
        source.min_date, source.max_date, source.actual_max_bytes,
        source.recommended_type, source.recommendation_note
    );

PRINT CAST(@@ROWCOUNT AS VARCHAR) +
      ' rows merged into dbo.MIGRATION_COL_PROFILE';

-- ------------------------------------------------------------
-- Verification
-- ------------------------------------------------------------
SELECT
    schema_name,
    table_name,
    COUNT(*)                                             AS total_columns,
    SUM(CASE WHEN recommended_type IS NOT NULL
             THEN 1 ELSE 0 END)                         AS typed_columns,
    SUM(CASE WHEN has_milliseconds = 1
             THEN 1 ELSE 0 END)                         AS ms_cols,
    SUM(CASE WHEN has_unicode = 0
             AND ss_type IN ('nvarchar','nchar')
             THEN 1 ELSE 0 END)                         AS downgrade_to_varchar,
    SUM(CASE WHEN null_pct = 100 THEN 1 ELSE 0 END)     AS all_null_cols,
    SUM(CASE WHEN null_pct > 90
             AND null_pct < 100 THEN 1 ELSE 0 END)      AS high_null_cols
FROM dbo.MIGRATION_COL_PROFILE
GROUP BY schema_name, table_name
ORDER BY schema_name, table_name;

DROP TABLE IF EXISTS #candidate_cols;
DROP TABLE IF EXISTS #col_profile;