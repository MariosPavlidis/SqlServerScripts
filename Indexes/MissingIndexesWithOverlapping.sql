/* Run in the user database context */

;WITH MissingIndexes AS
(
    SELECT
        DB_NAME(id.database_id)                          AS DatabaseName,
        id.database_id,
        id.object_id,
        OBJECT_SCHEMA_NAME(id.object_id, id.database_id) AS SchemaName,
        OBJECT_NAME(id.object_id, id.database_id)        AS TableName,
        id.[statement]                                   AS FullyQualifiedObjectName,
        id.equality_columns,
        id.inequality_columns,
        id.included_columns,
        gs.user_seeks,
        gs.user_scans,
        gs.last_user_seek,
        gs.last_user_scan,
        gs.avg_total_user_cost,
        gs.avg_user_impact,
        IndexAdvantage =
            gs.user_seeks * gs.avg_total_user_cost * (gs.avg_user_impact * 0.01),
        ProposedIndex =
            'CREATE INDEX [IX_MI_' +
                OBJECT_NAME(id.object_id, id.database_id) + '_' +
                REPLACE(REPLACE(REPLACE(ISNULL(id.equality_columns, ''), ', ', '_'), '[', ''), ']', '') +
                CASE
                    WHEN id.equality_columns IS NOT NULL
                         AND id.inequality_columns IS NOT NULL THEN '_'
                    ELSE ''
                END +
                REPLACE(REPLACE(REPLACE(ISNULL(id.inequality_columns, ''), ', ', '_'), '[', ''), ']', '') +
                '_' + LEFT(CONVERT(varchar(36), NEWID()), 5) + ']' +
            ' ON ' + id.[statement] +
            ' (' + ISNULL(id.equality_columns, '') +
            CASE
                WHEN id.equality_columns IS NOT NULL
                     AND id.inequality_columns IS NOT NULL THEN ','
                ELSE ''
            END +
            ISNULL(id.inequality_columns, '') + ')' +
            CASE
                WHEN id.included_columns IS NOT NULL
                    THEN ' INCLUDE (' + id.included_columns + ')'
                ELSE ''
            END,
        -- Normalize requested key columns (no brackets, no spaces)
        RequestedKeyColsNormalized =
            REPLACE(
                REPLACE(
                    REPLACE(
                        ISNULL(id.equality_columns, '') +
                        CASE
                            WHEN id.equality_columns IS NOT NULL
                                 AND id.inequality_columns IS NOT NULL THEN ','
                            ELSE ''
                        END +
                        ISNULL(id.inequality_columns, '')
                    ,'[','')
                ,']','')
            ,' ','')
    FROM sys.dm_db_missing_index_group_stats    AS gs
    INNER JOIN sys.dm_db_missing_index_groups   AS ig
        ON gs.group_handle = ig.index_group_handle
    INNER JOIN sys.dm_db_missing_index_details  AS id
        ON ig.index_handle = id.index_handle
    WHERE id.database_id = DB_ID()      -- per-database; change if needed
),
Indexes AS
(
    SELECT
        i.object_id,
        i.index_id,
        i.name           AS IndexName,
        i.type_desc,
        i.is_unique,
        i.is_primary_key,
        KeyColumns =
            STUFF((
                    SELECT ',' + c.name
                    FROM sys.index_columns ic2
                    JOIN sys.columns c
                        ON c.object_id = ic2.object_id
                       AND c.column_id = ic2.column_id
                    WHERE ic2.object_id = i.object_id
                      AND ic2.index_id  = i.index_id
                      AND ic2.is_included_column = 0
                    ORDER BY ic2.key_ordinal
                    FOR XML PATH(''), TYPE
                  ).value('.', 'nvarchar(max)'), 1, 1, ''),
        IncludedColumns =
            ISNULL(
                STUFF((
                        SELECT ',' + c2.name
                        FROM sys.index_columns ic3
                        JOIN sys.columns c2
                            ON c2.object_id = ic3.object_id
                           AND c2.column_id = ic3.column_id
                        WHERE ic3.object_id = i.object_id
                          AND ic3.index_id  = i.index_id
                          AND ic3.is_included_column = 1
                        ORDER BY c2.column_id
                        FOR XML PATH(''), TYPE
                      ).value('.', 'nvarchar(max)'), 1, 1, '')
            ,''),
        -- First key column name
        FirstKeyColumn =
        (
            SELECT TOP (1) c.name
            FROM sys.index_columns ic
            JOIN sys.columns c
              ON c.object_id = ic.object_id
             AND c.column_id = ic.column_id
            WHERE ic.object_id = i.object_id
              AND ic.index_id  = i.index_id
              AND ic.is_included_column = 0
            ORDER BY ic.key_ordinal
        ),
        -- Normalized first key column (no spaces)
        FirstKeyColumnNormalized =
        REPLACE(
            (
                SELECT TOP (1) c.name
                FROM sys.index_columns ic
                JOIN sys.columns c
                  ON c.object_id = ic.object_id
                 AND c.column_id = ic.column_id
                WHERE ic.object_id = i.object_id
                  AND ic.index_id  = i.index_id
                  AND ic.is_included_column = 0
                ORDER BY ic.key_ordinal
            )
        ,' ','')
    FROM sys.indexes i
    WHERE i.is_hypothetical = 0
      AND i.index_id > 0
),
Overlaps AS
(
    -- Existing indexes overlap only if their FIRST key column
    -- exists somewhere in the requested key cols of the missing index.
    SELECT
        mi.database_id,
        mi.object_id,
        idx.IndexName,
        idx.type_desc,
        idx.is_unique,
        idx.is_primary_key,
        idx.KeyColumns,
        idx.IncludedColumns
    FROM MissingIndexes mi
    JOIN Indexes idx
      ON mi.object_id = idx.object_id
    WHERE idx.FirstKeyColumnNormalized IS NOT NULL
      AND (
            (',' + mi.RequestedKeyColsNormalized + ',') COLLATE DATABASE_DEFAULT
            LIKE ('%,' + idx.FirstKeyColumnNormalized + ',%') COLLATE DATABASE_DEFAULT
          )
)
SELECT
    CAST(SERVERPROPERTY('ServerName') AS sysname) AS SQLServer,
    mi.DatabaseName,
    mi.SchemaName,
    mi.TableName,
    mi.FullyQualifiedObjectName,
    mi.equality_columns      AS EqualityColumns,
    mi.inequality_columns    AS InEqualityColumns,
    mi.included_columns      AS IncludedColumns,
    mi.user_seeks            AS UserSeeks,
    mi.user_scans            AS UserScans,
    mi.last_user_seek        AS LastUserSeekTime,
    mi.last_user_scan        AS LastUserScanTime,
    mi.avg_total_user_cost   AS AvgTotalUserCost,
    mi.avg_user_impact       AS AvgUserImpact,
    mi.IndexAdvantage,
    mi.ProposedIndex,
    ExistingOverlappingIndexes =
        ISNULL(
            STUFF((
                SELECT ' | ' +
                       o.IndexName +
                       ' [' + o.type_desc +
                           CASE WHEN o.is_unique = 1      THEN ', UQ' ELSE '' END +
                           CASE WHEN o.is_primary_key = 1 THEN ', PK' ELSE '' END +
                       ']' +
                       ' (' + ISNULL(o.KeyColumns, '') + ')' +
                       CASE
                           WHEN ISNULL(o.IncludedColumns, '') <> ''
                                THEN ' INCLUDE (' + o.IncludedColumns + ')'
                           ELSE ''
                       END
                FROM Overlaps o
                WHERE o.database_id = mi.database_id
                  AND o.object_id   = mi.object_id
                FOR XML PATH(''), TYPE
            ).value('.', 'nvarchar(max)'), 1, 3, '')
        ,'[no overlapping index]')
FROM MissingIndexes mi
ORDER BY mi.IndexAdvantage DESC
OPTION (RECOMPILE);
GO
