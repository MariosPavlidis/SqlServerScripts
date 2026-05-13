EXEC xp_readerrorlog 0, 1, N'Login failed', NULL, '20260401','20260506'', N'desc';


-- Members of sysadmin and other elevated server roles
SELECT
    r.name          AS ServerRole,
    m.name          AS MemberName,
    m.type_desc     AS LoginType,
    m.is_disabled   AS IsDisabled,
    m.create_date,
    m.modify_date
FROM sys.server_role_members srm
JOIN sys.server_principals r ON r.principal_id = srm.role_principal_id
JOIN sys.server_principals m ON m.principal_id = srm.member_principal_id
WHERE r.name IN ('sysadmin','securityadmin','serveradmin','setupadmin',
                 'processadmin','diskadmin','dbcreator','bulkadmin')
ORDER BY r.name, m.name;

-- SA login status (should be disabled and renamed in production)
SELECT name, is_disabled, type_desc, default_database_name
FROM sys.server_principals
WHERE name = 'sa' OR principal_id = 1;

-- Orphaned users across all databases
EXEC sp_MSforeachdb '
USE [?];
SELECT DB_NAME() AS DatabaseName, name AS OrphanedUser
FROM sys.database_principals
WHERE type IN (''S'',''U'',''G'')
  AND authentication_type_desc = ''INSTANCE''
  AND sid NOT IN (SELECT sid FROM sys.server_principals)
  AND name NOT IN (''dbo'',''guest'',''information_schema'',''sys'');