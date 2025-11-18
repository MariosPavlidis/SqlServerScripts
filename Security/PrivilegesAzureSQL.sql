USE master;
SET NOCOUNT ON;

IF OBJECT_ID('tempdb..#MasterUsers') IS NOT NULL DROP TABLE #MasterUsers;
CREATE TABLE #MasterUsers
(
    principal_id   INT        PRIMARY KEY,
    LoginName      SYSNAME,
    LoginTypeDesc  NVARCHAR(60)
);

INSERT #MasterUsers (principal_id, LoginName, LoginTypeDesc)
SELECT  dp.principal_id,
        dp.name,
        dp.type_desc
FROM    sys.database_principals dp
WHERE   dp.type IN ('S','U','G','E','X','C')   -- SQL, Windows group, AAD, etc.
AND     dp.sid IS NOT NULL
AND     dp.name NOT LIKE '##%';

-- Aggregated "server" roles (actually database roles in master)
IF OBJECT_ID('tempdb..#MasterRoles') IS NOT NULL DROP TABLE #MasterRoles;
CREATE TABLE #MasterRoles
(
    principal_id INT        PRIMARY KEY,
    ServerRoles  NVARCHAR(MAX)
);

INSERT #MasterRoles (principal_id, ServerRoles)
SELECT  u.principal_id,
        STUFF((
            SELECT  ',' + r.name
            FROM    sys.database_role_members drm
            JOIN    sys.database_principals r
                    ON r.principal_id = drm.role_principal_id
            WHERE   drm.member_principal_id = u.principal_id
            FOR XML PATH(''), TYPE).value('.','NVARCHAR(MAX)')
        ,1,1,'') AS ServerRoles
FROM    #MasterUsers u
WHERE   EXISTS (SELECT 1
                FROM sys.database_role_members drm
                WHERE drm.member_principal_id = u.principal_id);

-- Explicit permissions in master
IF OBJECT_ID('tempdb..#MasterPerms') IS NOT NULL DROP TABLE #MasterPerms;
CREATE TABLE #MasterPerms
(
    principal_id        INT        PRIMARY KEY,
    ServerExplicitPerms NVARCHAR(MAX)
);

INSERT #MasterPerms (principal_id, ServerExplicitPerms)
SELECT  u.principal_id,
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
            WHERE   dp2.grantee_principal_id = u.principal_id
            FOR XML PATH(''), TYPE).value('.','NVARCHAR(MAX)')
        ,1,2,'') AS ServerExplicitPerms
FROM    #MasterUsers u
WHERE   EXISTS (SELECT 1
                FROM sys.database_permissions dp
                WHERE dp.grantee_principal_id = u.principal_id);

SELECT  u.LoginName,
        u.LoginTypeDesc,
        ISNULL(r.ServerRoles,        '') AS ServerRoles,         -- includes dbmanager/loginmanager
        ISNULL(p.ServerExplicitPerms,'') AS ServerExplicitPerms  -- explicit in master only
FROM    #MasterUsers u
LEFT JOIN #MasterRoles r ON r.principal_id = u.principal_id
LEFT JOIN #MasterPerms p ON p.principal_id = u.principal_id
ORDER BY u.LoginName;
