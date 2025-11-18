-- Run in a user database (not master)
SET NOCOUNT ON;

;WITH DbUsers AS
(
    SELECT  dp.principal_id,
            dp.name       AS UserName,
            dp.type_desc  AS LoginTypeDesc
    FROM    sys.database_principals dp
    WHERE   dp.type IN ('S','U','G','E','X','C')   -- SQL, contained, AAD, groups
    AND     dp.sid IS NOT NULL
    AND     dp.name NOT LIKE '##%'
),
DbRolesAgg AS
(
    SELECT  drm.member_principal_id,
            STUFF((
                SELECT  ',' + r.name
                FROM    sys.database_role_members drm2
                JOIN    sys.database_principals r
                        ON r.principal_id = drm2.role_principal_id
                WHERE   drm2.member_principal_id = drm.member_principal_id
                FOR XML PATH(''), TYPE).value('.','NVARCHAR(MAX)')
            ,1,1,'') AS DbRoles
    FROM    sys.database_role_members drm
    GROUP BY drm.member_principal_id
),
DbPermsAgg AS
(
    -- explicit perms granted directly to users (exclude role principals)
    SELECT  dp.grantee_principal_id,
            STUFF((
                SELECT  '; ' +
                        dp2.state_desc + ' ' + dp2.permission_name +
                        ' ON ' + dp2.class_desc +
                        ISNULL('::' +
                            CASE dp2.class_desc
                                WHEN 'DATABASE' THEN DB_NAME()
                                WHEN 'SCHEMA'   THEN SCHEMA_NAME(dp2.major_id)
                                WHEN 'OBJECT_OR_COLUMN' THEN
                                    QUOTENAME(OBJECT_SCHEMA_NAME(dp2.major_id)) + '.' +
                                    QUOTENAME(OBJECT_NAME(dp2.major_id))
                                ELSE CONVERT(NVARCHAR(50), dp2.major_id)
                            END
                        ,'')
                FROM    sys.database_permissions dp2
                WHERE   dp2.grantee_principal_id = dp.grantee_principal_id
                FOR XML PATH(''), TYPE).value('.','NVARCHAR(MAX)')
            ,1,2,'') AS DbExplicitPerms
    FROM    sys.database_permissions dp
    JOIN    sys.database_principals gp
            ON gp.principal_id = dp.grantee_principal_id
    WHERE   gp.type <> 'R'   -- drop perms granted to roles
    GROUP BY dp.grantee_principal_id
)
SELECT  du.UserName       AS LoginName,      -- connection identity in this DB
        du.LoginTypeDesc,
        DB_NAME()         AS DatabaseName,
        du.UserName       AS UserName,
        ISNULL(dra.DbRoles,         '') AS DbRoles,
        ISNULL(dpa.DbExplicitPerms, '') AS DbExplicitPerms
FROM    DbUsers du
LEFT JOIN DbRolesAgg dra
        ON dra.member_principal_id = du.principal_id
LEFT JOIN DbPermsAgg dpa
        ON dpa.grantee_principal_id = du.principal_id
ORDER BY du.UserName;
