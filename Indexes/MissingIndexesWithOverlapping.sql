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
        RequestedKeyColsNormalized =
            LOWER(
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
            )
    FROM sys.dm_db_missing_index_group_stats   AS gs
    JOIN sys.dm_db_missing_index_groups        AS ig
      ON gs.group_handle = ig.index_group_handle
    JOIN sys.dm_db_missing_index_details       AS id
      ON ig.index_handle = id.index_handle
    WHERE id.database_id = DB_ID()
),
Indexes AS
(
    SELECT
        i.object_id,
        i.index_id,
        i.name AS IndexName,
        i.type_desc,
        i.is_unique,
        i.is_primary_key,
        KeyColumns =
            STUFF((
                SELECT ',' + c.name
                FROM sys.index_columns ic
                JOIN sys.columns c
                  ON c.object_id = ic.object_id
                 AND c.column_id = ic.column_id
                WHERE ic.object_id = i.object_id
                  AND ic.index_id  = i.index_id
                  AND ic.is_included_column = 0
                ORDER BY ic.key_ordinal
                FOR XML PATH(''), TYPE
            ).value('.', 'nvarchar(max)'), 1, 1, ''),
        IncludedColumns =
            ISNULL(STUFF((
                SELECT ',' + c.name
                FROM sys.index_columns ic
                JOIN sys.columns c
                  ON c.object_id = ic.object_id
                 AND c.column_id = ic.column_id
                WHERE ic.object_id = i.object_id
                  AND ic.index_id  = i.index_id
                  AND ic.is_included_column = 1
                ORDER BY c.column_id
                FOR XML PATH(''), TYPE
            ).value('.', 'nvarchar(max)'), 1, 1, ''), ''),
        KeyColumnsNormalized =
            LOWER(
                REPLACE(
                    REPLACE(
                        REPLACE(
                            STUFF((
                                SELECT ',' + c.name
                                FROM sys.index_columns ic
                                JOIN sys.columns c
                                  ON c.object_id = ic.object_id
                                 AND c.column_id = ic.column_id
                                WHERE ic.object_id = i.object_id
                                  AND ic.index_id  = i.index_id
                                  AND ic.is_included_column = 0
                                ORDER BY ic.key_ordinal
                                FOR XML PATH(''), TYPE
                            ).value('.', 'nvarchar(max)'), 1, 1, '')
                        ,'[','')
                    ,']','')
                ,' ','')
            )
    FROM sys.indexes i
    WHERE i.is_hypothetical = 0
      AND i.index_id > 0
      AND i.type IN (1,2) -- clustered/nonclustered rowstore
),
MissingCols AS
(
    SELECT
        mi.database_id,
        mi.object_id,
        mi.RequestedKeyColsNormalized,
        ROW_NUMBER() OVER
        (
            PARTITION BY mi.database_id, mi.object_id, mi.RequestedKeyColsNormalized
            ORDER BY (SELECT NULL)
        ) AS key_ordinal,
        x.n.value('.', 'sysname') AS colname
    FROM MissingIndexes mi
    CROSS APPLY
    (
        SELECT TRY_CAST(
            '<r><c>' + REPLACE(mi.RequestedKeyColsNormalized, ',', '</c><c>') + '</c></r>' AS xml
        ) AS xmlval
    ) d
    CROSS APPLY d.xmlval.nodes('/r/c') x(n)
    WHERE mi.RequestedKeyColsNormalized <> ''
),
ExistingCols AS
(
    SELECT
        idx.object_id,
        idx.index_id,
        ROW_NUMBER() OVER
        (
            PARTITION BY idx.object_id, idx.index_id
            ORDER BY (SELECT NULL)
        ) AS key_ordinal,
        x.n.value('.', 'sysname') AS colname
    FROM Indexes idx
    CROSS APPLY
    (
        SELECT TRY_CAST(
            '<r><c>' + REPLACE(idx.KeyColumnsNormalized, ',', '</c><c>') + '</c></r>' AS xml
        ) AS xmlval
    ) d
    CROSS APPLY d.xmlval.nodes('/r/c') x(n)
    WHERE idx.KeyColumnsNormalized <> ''
),
MissingKeyCount AS
(
    SELECT
        database_id,
        object_id,
        RequestedKeyColsNormalized,
        COUNT(*) AS MissingKeyCount
    FROM MissingCols
    GROUP BY
        database_id,
        object_id,
        RequestedKeyColsNormalized
),
ExistingKeyCount AS
(
    SELECT
        object_id,
        index_id,
        COUNT(*) AS ExistingKeyCount
    FROM ExistingCols
    GROUP BY
        object_id,
        index_id
),
Comparison AS
(
    SELECT
        mi.database_id,
        mi.object_id,
        mi.RequestedKeyColsNormalized,
        idx.index_id,
        idx.IndexName,
        idx.type_desc,
        idx.is_unique,
        idx.is_primary_key,
        idx.KeyColumns,
        idx.IncludedColumns,
        mkc.MissingKeyCount,
        ekc.ExistingKeyCount,
        PrefixMatchCount =
            ISNULL(
            (
                SELECT MIN(v.key_ordinal) - 1
                FROM
                (
                    SELECT
                        ec.key_ordinal,
                        mc.colname AS missing_col,
                        ec.colname AS existing_col
                    FROM ExistingCols ec
                    JOIN MissingCols mc
                      ON mc.database_id = mi.database_id
                     AND mc.object_id   = mi.object_id
                     AND mc.RequestedKeyColsNormalized = mi.RequestedKeyColsNormalized
                     AND mc.key_ordinal = ec.key_ordinal
                    WHERE ec.object_id = idx.object_id
                      AND ec.index_id  = idx.index_id
                ) v
                WHERE v.missing_col <> v.existing_col
            ),
            CASE
                WHEN ekc.ExistingKeyCount <= mkc.MissingKeyCount THEN ekc.ExistingKeyCount
                ELSE mkc.MissingKeyCount
            END)
    FROM MissingIndexes mi
    JOIN Indexes idx
      ON idx.object_id = mi.object_id
    JOIN MissingKeyCount mkc
      ON mkc.database_id = mi.database_id
     AND mkc.object_id   = mi.object_id
     AND mkc.RequestedKeyColsNormalized = mi.RequestedKeyColsNormalized
    JOIN ExistingKeyCount ekc
      ON ekc.object_id = idx.object_id
     AND ekc.index_id  = idx.index_id
),
Classified AS
(
    SELECT
        c.*,
        MatchType =
            CASE
                WHEN c.PrefixMatchCount = 0 THEN NULL
                WHEN c.PrefixMatchCount = c.MissingKeyCount
                 AND c.PrefixMatchCount = c.ExistingKeyCount
                    THEN 'EXACT_KEY_MATCH'
                WHEN c.PrefixMatchCount = c.ExistingKeyCount
                 AND c.ExistingKeyCount < c.MissingKeyCount
                    THEN 'EXISTING_IS_PREFIX_OF_MISSING'
                WHEN c.PrefixMatchCount = c.MissingKeyCount
                 AND c.MissingKeyCount < c.ExistingKeyCount
                    THEN 'MISSING_IS_PREFIX_OF_EXISTING'
                WHEN c.PrefixMatchCount = 1
                    THEN 'SAME_FIRST_KEY_ONLY'
                ELSE 'PARTIAL_LEADING_MATCH'
            END
    FROM Comparison c
)
SELECT
    CAST(SERVERPROPERTY('ServerName') AS sysname) AS SQLServer,
    mi.DatabaseName,
    mi.SchemaName,
    mi.TableName,
    mi.FullyQualifiedObjectName,
    mi.equality_columns   AS EqualityColumns,
    mi.inequality_columns AS InEqualityColumns,
    mi.included_columns   AS IncludedColumns,
    mi.user_seeks         AS UserSeeks,
    mi.user_scans         AS UserScans,
    mi.last_user_seek     AS LastUserSeekTime,
    mi.last_user_scan     AS LastUserScanTime,
    mi.avg_total_user_cost AS AvgTotalUserCost,
    mi.avg_user_impact     AS AvgUserImpact,
    mi.IndexAdvantage,
    mi.ProposedIndex,
    ExistingIndexAnalysis =
        ISNULL(
            STUFF((
                SELECT
                    ' | ' + c.IndexName +
                    ' [' + c.MatchType +
                    '; ' + c.type_desc +
                    CASE WHEN c.is_unique = 1 THEN ', UQ' ELSE '' END +
                    CASE WHEN c.is_primary_key = 1 THEN ', PK' ELSE '' END +
                    '; prefix=' + CAST(c.PrefixMatchCount AS varchar(10)) +
                    '] (' + ISNULL(c.KeyColumns, '') + ')' +
                    CASE
                        WHEN ISNULL(c.IncludedColumns, '') <> ''
                            THEN ' INCLUDE (' + c.IncludedColumns + ')'
                        ELSE ''
                    END
                FROM Classified c
                WHERE c.database_id = mi.database_id
                  AND c.object_id   = mi.object_id
                  AND c.RequestedKeyColsNormalized = mi.RequestedKeyColsNormalized
                  AND c.MatchType IS NOT NULL
                ORDER BY
                    CASE c.MatchType
                        WHEN 'EXACT_KEY_MATCH' THEN 1
                        WHEN 'MISSING_IS_PREFIX_OF_EXISTING' THEN 2
                        WHEN 'EXISTING_IS_PREFIX_OF_MISSING' THEN 3
                        WHEN 'PARTIAL_LEADING_MATCH' THEN 4
                        WHEN 'SAME_FIRST_KEY_ONLY' THEN 5
                        ELSE 99
                    END,
                    c.PrefixMatchCount DESC,
                    c.IndexName
                FOR XML PATH(''), TYPE
            ).value('.', 'nvarchar(max)'), 1, 3, ''),
            '[no relevant leading-key overlap]'
        )
FROM MissingIndexes mi
ORDER BY mi.IndexAdvantage DESC
OPTION (RECOMPILE);
GO