/*==============================================================
  TABLE + DEPENDENT OBJECTS DDL GENERATOR
  SQL Server
  --------------------------------------------------------------
  Outputs:
    1. CREATE TABLE
    2. DEFAULT constraints
    3. CHECK constraints
    4. PRIMARY KEY / UNIQUE constraints
    5. FOREIGN KEY constraints
    6. Nonconstraint indexes
    7. Triggers

  Notes:
    - SQL-only approach, not SMO.
    - Handles collation conflicts with COLLATE DATABASE_DEFAULT.
    - Uses XML PATH for ordered column concatenation.
    - Does not script:
        * partition schemes/functions
        * compression options
        * extended properties
        * permissions
        * fulltext/spatial/XML indexes
        * temporal/system-versioning clauses
        * memory-optimized specific options
==============================================================*/

SET NOCOUNT ON;

----------------------------------------------------------------
-- PARAMETER BLOCK
----------------------------------------------------------------
DECLARE @SchemaName sysname = N'dbo';
DECLARE @TableName  sysname = N'FIXING_TFI_FEED';

----------------------------------------------------------------
-- INTERNAL VARIABLES
----------------------------------------------------------------
DECLARE @ObjectId int = OBJECT_ID(QUOTENAME(@SchemaName) + N'.' + QUOTENAME(@TableName));
DECLARE @CRLF nchar(2) = NCHAR(13) + NCHAR(10);

IF @ObjectId IS NULL
BEGIN
    RAISERROR('Table %s.%s not found in current database.', 16, 1, @SchemaName, @TableName);
    RETURN;
END;

IF OBJECT_ID('tempdb..#DDL') IS NOT NULL
    DROP TABLE #DDL;

CREATE TABLE #DDL
(
    section_order int NOT NULL,
    section_name  nvarchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
    ddl           nvarchar(max) COLLATE DATABASE_DEFAULT NOT NULL
);

----------------------------------------------------------------
-- 1. CREATE TABLE
----------------------------------------------------------------
DECLARE @CreateTable nvarchar(max);

;WITH c AS
(
    SELECT
        c.column_id,
        c.name                           AS column_name,
        t.name                           AS type_name,
        c.max_length,
        c.precision,
        c.scale,
        c.is_nullable,
        c.is_rowguidcol,
        c.is_computed,
        c.collation_name,
        cc.definition                    AS computed_definition,
        cc.is_persisted,
        ic.seed_value,
        ic.increment_value,
        dc.definition                    AS default_definition,
        c.is_identity,
        c.system_type_id,
        c.user_type_id
    FROM sys.columns c
    JOIN sys.types t
      ON c.user_type_id = t.user_type_id
    LEFT JOIN sys.computed_columns cc
      ON c.object_id = cc.object_id
     AND c.column_id = cc.column_id
    LEFT JOIN sys.identity_columns ic
      ON c.object_id = ic.object_id
     AND c.column_id = ic.column_id
    LEFT JOIN sys.default_constraints dc
      ON c.default_object_id = dc.object_id
    WHERE c.object_id = @ObjectId
)
SELECT
    @CreateTable =
        N'CREATE TABLE ' + QUOTENAME(@SchemaName) + N'.' + QUOTENAME(@TableName) + N'(' + @CRLF +
        STUFF
        (
            (
                SELECT
                    N',' + @CRLF +
                    N'    ' + QUOTENAME(c.column_name) + N' ' +
                    CASE
                        WHEN c.is_computed = 1 THEN
                            N'AS ' + c.computed_definition +
                            CASE WHEN c.is_persisted = 1 THEN N' PERSISTED' ELSE N'' END

                        WHEN c.type_name IN (N'varchar',N'char',N'varbinary',N'binary') THEN
                            c.type_name + N'(' +
                            CASE WHEN c.max_length = -1 THEN N'MAX'
                                 ELSE CONVERT(varchar(10), c.max_length) END + N')'

                        WHEN c.type_name IN (N'nvarchar',N'nchar') THEN
                            c.type_name + N'(' +
                            CASE WHEN c.max_length = -1 THEN N'MAX'
                                 ELSE CONVERT(varchar(10), c.max_length / 2) END + N')'

                        WHEN c.type_name IN (N'decimal',N'numeric') THEN
                            c.type_name + N'(' +
                            CONVERT(varchar(10), c.precision) + N',' +
                            CONVERT(varchar(10), c.scale) + N')'

                        WHEN c.type_name IN (N'datetime2',N'datetimeoffset',N'time') THEN
                            c.type_name + N'(' + CONVERT(varchar(10), c.scale) + N')'

                        WHEN c.type_name = N'float' THEN
                            c.type_name +
                            CASE WHEN c.precision <> 53
                                 THEN N'(' + CONVERT(varchar(10), c.precision) + N')'
                                 ELSE N'' END

                        ELSE
                            c.type_name
                    END +
                    CASE
                        WHEN c.is_computed = 1 THEN N''
                        WHEN c.collation_name IS NOT NULL
                             AND c.type_name IN (N'varchar',N'char',N'text',N'nvarchar',N'nchar',N'ntext')
                            THEN N' COLLATE ' + c.collation_name
                        ELSE N''
                    END +
                    CASE
                        WHEN c.is_computed = 1 THEN N''
                        WHEN c.is_identity = 1 THEN
                            N' IDENTITY(' +
                            CONVERT(varchar(30), CONVERT(bigint, c.seed_value)) + N',' +
                            CONVERT(varchar(30), CONVERT(bigint, c.increment_value)) + N')'
                        ELSE N''
                    END +
                    CASE
                        WHEN c.is_computed = 1 THEN N''
                        WHEN c.is_rowguidcol = 1 THEN N' ROWGUIDCOL'
                        ELSE N''
                    END +
                    CASE
                        WHEN c.is_computed = 1 THEN N''
                        WHEN c.is_nullable = 1 THEN N' NULL'
                        ELSE N' NOT NULL'
                    END
                FROM c
                ORDER BY c.column_id
                FOR XML PATH(''), TYPE
            ).value('.', 'nvarchar(max)')
        ,1,2,N'') + @CRLF + N');';

INSERT INTO #DDL(section_order, section_name, ddl)
VALUES (10, N'CREATE TABLE', @CreateTable);

----------------------------------------------------------------
-- 2. DEFAULT CONSTRAINTS
----------------------------------------------------------------
INSERT INTO #DDL(section_order, section_name, ddl)
SELECT
    20,
    N'DEFAULT CONSTRAINT',
    N'ALTER TABLE ' + QUOTENAME(OBJECT_SCHEMA_NAME(dc.parent_object_id)) + N'.' + QUOTENAME(OBJECT_NAME(dc.parent_object_id)) +
    N' ADD CONSTRAINT ' + QUOTENAME(dc.name) +
    N' DEFAULT ' + dc.definition +
    N' FOR ' + QUOTENAME(c.name) + N';'
FROM sys.default_constraints dc
JOIN sys.columns c
  ON dc.parent_object_id = c.object_id
 AND dc.parent_column_id = c.column_id
WHERE dc.parent_object_id = @ObjectId;

----------------------------------------------------------------
-- 3. CHECK CONSTRAINTS
----------------------------------------------------------------
INSERT INTO #DDL(section_order, section_name, ddl)
SELECT
    30,
    N'CHECK CONSTRAINT',
    N'ALTER TABLE ' + QUOTENAME(OBJECT_SCHEMA_NAME(cc.parent_object_id)) + N'.' + QUOTENAME(OBJECT_NAME(cc.parent_object_id)) +
    N' ADD CONSTRAINT ' + QUOTENAME(cc.name) +
    N' CHECK ' +
    CASE WHEN cc.is_not_for_replication = 1 THEN N'NOT FOR REPLICATION ' ELSE N'' END +
    cc.definition + N';'
FROM sys.check_constraints cc
WHERE cc.parent_object_id = @ObjectId;

----------------------------------------------------------------
-- 4. PRIMARY KEY / UNIQUE CONSTRAINTS
----------------------------------------------------------------
INSERT INTO #DDL(section_order, section_name, ddl)
SELECT
    40,
    CASE kc.type WHEN 'PK' THEN N'PRIMARY KEY' ELSE N'UNIQUE CONSTRAINT' END,
    N'ALTER TABLE ' + QUOTENAME(s.name) + N'.' + QUOTENAME(t.name) +
    N' ADD CONSTRAINT ' + QUOTENAME(kc.name) + N' ' +
    CASE kc.type WHEN 'PK' THEN N'PRIMARY KEY ' ELSE N'UNIQUE ' END +
    i.type_desc + N' (' +
    STUFF
    (
        (
            SELECT
                N', ' + QUOTENAME(c.name) +
                CASE WHEN ic.is_descending_key = 1 THEN N' DESC' ELSE N' ASC' END
            FROM sys.index_columns ic
            JOIN sys.columns c
              ON ic.object_id = c.object_id
             AND ic.column_id = c.column_id
            WHERE ic.object_id = i.object_id
              AND ic.index_id = i.index_id
              AND ic.key_ordinal > 0
            ORDER BY ic.key_ordinal
            FOR XML PATH(''), TYPE
        ).value('.', 'nvarchar(max)')
    ,1,2,N'') +
    N');'
FROM sys.key_constraints kc
JOIN sys.tables t
  ON kc.parent_object_id = t.object_id
JOIN sys.schemas s
  ON t.schema_id = s.schema_id
JOIN sys.indexes i
  ON kc.parent_object_id = i.object_id
 AND kc.unique_index_id = i.index_id
WHERE kc.parent_object_id = @ObjectId;

----------------------------------------------------------------
-- 5. FOREIGN KEYS
----------------------------------------------------------------
INSERT INTO #DDL(section_order, section_name, ddl)
SELECT
    50,
    N'FOREIGN KEY',
    N'ALTER TABLE ' + QUOTENAME(ps.name) + N'.' + QUOTENAME(pt.name) +
    N' ADD CONSTRAINT ' + QUOTENAME(fk.name) + N' FOREIGN KEY (' +
    STUFF
    (
        (
            SELECT N', ' + QUOTENAME(pc.name)
            FROM sys.foreign_key_columns fkc2
            JOIN sys.columns pc
              ON fkc2.parent_object_id = pc.object_id
             AND fkc2.parent_column_id = pc.column_id
            WHERE fkc2.constraint_object_id = fk.object_id
            ORDER BY fkc2.constraint_column_id
            FOR XML PATH(''), TYPE
        ).value('.', 'nvarchar(max)')
    ,1,2,N'') +
    N') REFERENCES ' + QUOTENAME(rs.name) + N'.' + QUOTENAME(rt.name) + N' (' +
    STUFF
    (
        (
            SELECT N', ' + QUOTENAME(rc.name)
            FROM sys.foreign_key_columns fkc2
            JOIN sys.columns rc
              ON fkc2.referenced_object_id = rc.object_id
             AND fkc2.referenced_column_id = rc.column_id
            WHERE fkc2.constraint_object_id = fk.object_id
            ORDER BY fkc2.constraint_column_id
            FOR XML PATH(''), TYPE
        ).value('.', 'nvarchar(max)')
    ,1,2,N'') +
    N')' +
    CASE fk.delete_referential_action
         WHEN 1 THEN N' ON DELETE CASCADE'
         WHEN 2 THEN N' ON DELETE SET NULL'
         WHEN 3 THEN N' ON DELETE SET DEFAULT'
         ELSE N''
    END +
    CASE fk.update_referential_action
         WHEN 1 THEN N' ON UPDATE CASCADE'
         WHEN 2 THEN N' ON UPDATE SET NULL'
         WHEN 3 THEN N' ON UPDATE SET DEFAULT'
         ELSE N''
    END +
    CASE WHEN fk.is_not_for_replication = 1 THEN N' NOT FOR REPLICATION' ELSE N'' END +
    N';'
FROM sys.foreign_keys fk
JOIN sys.tables pt
  ON fk.parent_object_id = pt.object_id
JOIN sys.schemas ps
  ON pt.schema_id = ps.schema_id
JOIN sys.tables rt
  ON fk.referenced_object_id = rt.object_id
JOIN sys.schemas rs
  ON rt.schema_id = rs.schema_id
WHERE fk.parent_object_id = @ObjectId;

----------------------------------------------------------------
-- 6. NONCONSTRAINT INDEXES
----------------------------------------------------------------
INSERT INTO #DDL(section_order, section_name, ddl)
SELECT
    60,
    N'INDEX',
    N'CREATE ' +
    CASE WHEN i.is_unique = 1 THEN N'UNIQUE ' ELSE N'' END +
    CASE WHEN i.type = 1 THEN N'CLUSTERED '
         WHEN i.type = 2 THEN N'NONCLUSTERED '
         ELSE i.type_desc + N' '
    END +
    N'INDEX ' + QUOTENAME(i.name) +
    N' ON ' + QUOTENAME(s.name) + N'.' + QUOTENAME(t.name) +
    N' (' +
    STUFF
    (
        (
            SELECT
                N', ' + QUOTENAME(c.name) +
                CASE WHEN ic.is_descending_key = 1 THEN N' DESC' ELSE N' ASC' END
            FROM sys.index_columns ic
            JOIN sys.columns c
              ON ic.object_id = c.object_id
             AND ic.column_id = c.column_id
            WHERE ic.object_id = i.object_id
              AND ic.index_id = i.index_id
              AND ic.key_ordinal > 0
            ORDER BY ic.key_ordinal
            FOR XML PATH(''), TYPE
        ).value('.', 'nvarchar(max)')
    ,1,2,N'') + N')' +
    CASE
        WHEN EXISTS
        (
            SELECT 1
            FROM sys.index_columns ic
            WHERE ic.object_id = i.object_id
              AND ic.index_id = i.index_id
              AND ic.is_included_column = 1
        )
        THEN N' INCLUDE (' +
             STUFF
             (
                (
                    SELECT N', ' + QUOTENAME(c.name)
                    FROM sys.index_columns ic
                    JOIN sys.columns c
                      ON ic.object_id = c.object_id
                     AND ic.column_id = c.column_id
                    WHERE ic.object_id = i.object_id
                      AND ic.index_id = i.index_id
                      AND ic.is_included_column = 1
                    ORDER BY c.column_id
                    FOR XML PATH(''), TYPE
                ).value('.', 'nvarchar(max)')
             ,1,2,N'') + N')'
        ELSE N''
    END +
    CASE WHEN i.has_filter = 1 THEN N' WHERE ' + i.filter_definition ELSE N'' END +
    N';'
FROM sys.indexes i
JOIN sys.tables t
  ON i.object_id = t.object_id
JOIN sys.schemas s
  ON t.schema_id = s.schema_id
WHERE i.object_id = @ObjectId
  AND i.name IS NOT NULL
  AND i.is_hypothetical = 0
  AND i.is_primary_key = 0
  AND i.is_unique_constraint = 0
  AND i.type IN (1,2);

----------------------------------------------------------------
-- 7. TRIGGERS
----------------------------------------------------------------
INSERT INTO #DDL(section_order, section_name, ddl)
SELECT
    70,
    N'TRIGGER',
    OBJECT_DEFINITION(tr.object_id) + N';'
FROM sys.triggers tr
WHERE tr.parent_id = @ObjectId
  AND OBJECT_DEFINITION(tr.object_id) IS NOT NULL;

----------------------------------------------------------------
-- OUTPUT 1: ordered result set
----------------------------------------------------------------
SELECT
    section_order,
    section_name,
    ddl
FROM #DDL
ORDER BY section_order, section_name, ddl;

----------------------------------------------------------------
-- OUTPUT 2: single combined script
----------------------------------------------------------------
SELECT
    STUFF
    (
        (
            SELECT
                @CRLF + N'-- ==================================================' +
                @CRLF + N'-- ' + d.section_name +
                @CRLF + N'-- ==================================================' +
                @CRLF + d.ddl + @CRLF
            FROM #DDL d
            ORDER BY d.section_order, d.section_name, d.ddl
            FOR XML PATH(''), TYPE
        ).value('.', 'nvarchar(max)')
    ,1,2,N'') AS full_ddl;