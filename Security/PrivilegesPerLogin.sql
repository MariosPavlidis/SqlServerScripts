USE master;
SET NOCOUNT ON;

------------------------------------------------------------
-- 1. Base: server logins
------------------------------------------------------------
IF OBJECT_ID('tempdb..#LoginBase') IS NOT NULL DROP TABLE #LoginBase;
CREATE TABLE #LoginBase
(
    principal_id   INT        PRIMARY KEY,
    LoginName      SYSNAME,
    LoginTypeDesc  NVARCHAR(60),
    sid            VARBINARY(85)
);

INSERT #LoginBase (principal_id, LoginName, LoginTypeDesc, sid)
SELECT  sp.principal_id,
        sp.name,
        sp.type_desc,
        sp.sid
FROM    sys.server_principals sp
WHERE   sp.type IN ('S','U','G','E','X','C','K')   -- SQL, Windows, cert, etc.
AND     sp.name NOT LIKE '##%';                   -- exclude internal logins


------------------------------------------------------------
-- 2. Aggregated server roles per login
------------------------------------------------------------
IF OBJECT_ID('tempdb..#ServerRoles') IS NOT NULL DROP TABLE #ServerRoles;
CREATE TABLE #ServerRoles
(
    principal_id INT        PRIMARY KEY,
    ServerRoles  NVARCHAR(MAX)
);

INSERT #ServerRoles (principal_id, ServerRoles)
SELECT  lb.principal_id,
        STUFF((
            SELECT  ',' + r.name
            FROM    sys.server_role_members srm
            JOIN    sys.server_principals r
                    ON r.principal_id = srm.role_principal_id
            WHERE   srm.member_principal_id = lb.principal_id
            FOR XML PATH(''), TYPE).value('.','NVARCHAR(MAX)')
        ,1,1,'') AS ServerRoles
FROM    #LoginBase lb
WHERE   EXISTS (SELECT 1
                FROM sys.server_role_members srm
                WHERE srm.member_principal_id = lb.principal_id);


------------------------------------------------------------
-- 3. Aggregated explicit server permissions per login
--    (direct grants only, not via roles)
------------------------------------------------------------
IF OBJECT_ID('tempdb..#ServerPerms') IS NOT NULL DROP TABLE #ServerPerms;
CREATE TABLE #ServerPerms
(
    principal_id        INT        PRIMARY KEY,
    ServerExplicitPerms NVARCHAR(MAX)
);

INSERT #ServerPerms (principal_id, ServerExplicitPerms)
SELECT  lb.principal_id,
        STUFF((
            SELECT  '; ' +
                    spm.state_desc + ' ' + spm.permission_name +
                    ' ON ' + spm.class_desc +
                    ISNULL('::' +
                        CASE spm.class_desc
                            WHEN 'ENDPOINT' THEN QUOTENAME(ep.name)
                            ELSE CONVERT(NVARCHAR(50), spm.major_id)
                        END
                    ,'')
            FROM    sys.server_permissions spm
            LEFT JOIN sys.endpoints ep
                   ON spm.class_desc = 'ENDPOINT'
                  AND spm.major_id   = ep.endpoint_id
            WHERE   spm.grantee_principal_id = lb.principal_id
            FOR XML PATH(''), TYPE).value('.','NVARCHAR(MAX)')
        ,1,2,'') AS ServerExplicitPerms
FROM    #LoginBase lb
WHERE   EXISTS (SELECT 1
                FROM sys.server_permissions spm
                WHERE spm.grantee_principal_id = lb.principal_id);


------------------------------------------------------------
-- 4. Per-database data
------------------------------------------------------------
IF OBJECT_ID('tempdb..#DbReport') IS NOT NULL DROP TABLE #DbReport;
CREATE TABLE #DbReport
(
    LoginName        SYSNAME,
    DatabaseName     SYSNAME,
    UserName         SYSNAME,
    DbRoles          NVARCHAR(MAX),
    DbExplicitPerms  NVARCHAR(MAX)
);

DECLARE @db  SYSNAME,
        @sql NVARCHAR(MAX);

DECLARE dbcur CURSOR FAST_FORWARD FOR
SELECT name
FROM sys.databases
WHERE state = 0          -- online only
  AND database_id > 4;   -- skip system DBs; drop this filter if you want them too

OPEN dbcur;
FETCH NEXT FROM dbcur INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
USE ' + QUOTENAME(@db) + N';

;WITH DbUsers AS
(
    SELECT  dp.principal_id,
            dp.name       AS UserName,
            dp.sid
    FROM    sys.database_principals dp
    WHERE   dp.type IN (''S'',''U'',''G'',''E'',''X'',''C'')
    AND     dp.sid IS NOT NULL
),
DbRolesAgg AS
(
    SELECT  drm.member_principal_id,
            STUFF((
                SELECT  '','' + r.name
                FROM    sys.database_role_members drm2
                JOIN    sys.database_principals r
                        ON r.principal_id = drm2.role_principal_id
                WHERE   drm2.member_principal_id = drm.member_principal_id
                FOR XML PATH(''''), TYPE).value(''.'',''NVARCHAR(MAX)'')
            ,1,1,'''') AS DbRoles
    FROM    sys.database_role_members drm
    GROUP BY drm.member_principal_id
),
DbPermsAgg AS
(
    -- explicit perms granted directly to users (exclude role principals)
    SELECT  dp.grantee_principal_id,
            STUFF((
                SELECT  ''; '' +
                        dp2.state_desc + '' '' + dp2.permission_name +
                        '' ON '' + dp2.class_desc +
                        ISNULL(''::'' +
                            CASE dp2.class_desc
                                WHEN ''DATABASE'' THEN DB_NAME()
                                WHEN ''SCHEMA'' THEN SCHEMA_NAME(dp2.major_id)
                                WHEN ''OBJECT_OR_COLUMN'' THEN
                                    QUOTENAME(OBJECT_SCHEMA_NAME(dp2.major_id)) + ''.'' +
                                    QUOTENAME(OBJECT_NAME(dp2.major_id))
                                ELSE CONVERT(NVARCHAR(50), dp2.major_id)
                            END
                        ,'''')
                FROM    sys.database_permissions dp2
                WHERE   dp2.grantee_principal_id = dp.grantee_principal_id
                FOR XML PATH(''''), TYPE).value(''.'',''NVARCHAR(MAX)'')
            ,1,2,'''') AS DbExplicitPerms
    FROM    sys.database_permissions dp
    JOIN    sys.database_principals gp
            ON gp.principal_id = dp.grantee_principal_id
    WHERE   gp.type <> ''R''
    GROUP BY dp.grantee_principal_id
)
INSERT #DbReport (LoginName, DatabaseName, UserName, DbRoles, DbExplicitPerms)
SELECT  lb.LoginName,
        DB_NAME()               AS DatabaseName,
        du.UserName,
        ISNULL(dra.DbRoles, '''')         AS DbRoles,
        ISNULL(dpa.DbExplicitPerms, '''') AS DbExplicitPerms
FROM    DbUsers du
JOIN    #LoginBase lb
        ON du.sid = lb.sid
LEFT JOIN DbRolesAgg dra
        ON dra.member_principal_id = du.principal_id
LEFT JOIN DbPermsAgg dpa
        ON dpa.grantee_principal_id = du.principal_id;
';

    BEGIN TRY
        EXEC (@sql);
    END TRY
    BEGIN CATCH
        PRINT 'Error processing database ' + QUOTENAME(@db) + ': ' + ERROR_MESSAGE();
    END CATCH;

    FETCH NEXT FROM dbcur INTO @db;
END

CLOSE dbcur;
DEALLOCATE dbcur;


------------------------------------------------------------
-- 5. Final consolidated result
------------------------------------------------------------
SELECT  lb.LoginName,
        lb.LoginTypeDesc,
        dr.DatabaseName,
        dr.UserName,
        ISNULL(sr.ServerRoles,        '') AS ServerRoles,
        ISNULL(dr.DbRoles,            '') AS DbRoles,
        ISNULL(sp.ServerExplicitPerms,'') AS ServerExplicitPerms,
        ISNULL(dr.DbExplicitPerms,    '') AS DbExplicitPerms
FROM    #DbReport dr
JOIN    #LoginBase     lb ON lb.LoginName    = dr.LoginName
LEFT JOIN #ServerRoles sr ON sr.principal_id = lb.principal_id
LEFT JOIN #ServerPerms sp ON sp.principal_id = lb.principal_id
ORDER BY lb.LoginName, dr.DatabaseName, dr.UserName;
