SET NOCOUNT ON;

;WITH DbUsers AS
(
    -- Target principals: real users (not roles)
    SELECT  dp.principal_id,
            dp.name       AS UserName,
            dp.type_desc  AS UserTypeDesc
    FROM    sys.database_principals dp
    WHERE   dp.type IN ('S','U','G','E','X','C')   -- SQL, contained, AAD, groups, etc.
    AND     dp.sid IS NOT NULL
    AND     dp.name NOT LIKE '##%'                -- ignore internal
),
DbRoles AS
(
    SELECT  dp.principal_id,
            dp.name AS RoleName
    FROM    sys.database_principals dp
    WHERE   dp.type = 'R'                         -- database roles
),
RoleMembers AS
(
    SELECT  drm.member_principal_id AS UserPrincipalId,
            drm.role_principal_id   AS RolePrincipalId
    FROM    sys.database_role_members drm
),
Perms AS
(
    SELECT  dp.class_desc,
            dp.major_id,
            dp.minor_id,
            dp.grantee_principal_id,
            dp.permission_name,
            dp.state_desc
    FROM    sys.database_permissions dp
),
PermsExpanded AS
(
    -- Direct grants to users
    SELECT  u.UserName,
            u.UserTypeDesc,
            'DIRECT'       AS PermissionSource,
            CAST(NULL AS SYSNAME) AS RoleName,
            p.state_desc,
            p.permission_name,
            p.class_desc,
            p.major_id,
            p.minor_id
    FROM    Perms p
    JOIN    DbUsers u
            ON p.grantee_principal_id = u.principal_id

    UNION ALL

    -- Grants via roles (user -> role -> permission)
    SELECT  u.UserName,
            u.UserTypeDesc,
            'ROLE'         AS PermissionSource,
            r.RoleName,
            p.state_desc,
            p.permission_name,
            p.class_desc,
            p.major_id,
            p.minor_id
    FROM    Perms p
    JOIN    RoleMembers rm
            ON p.grantee_principal_id = rm.RolePrincipalId
    JOIN    DbUsers u
            ON rm.UserPrincipalId = u.principal_id
    JOIN    DbRoles r
            ON r.principal_id = rm.RolePrincipalId
)
SELECT
    pe.UserName,
    pe.UserTypeDesc,
    pe.PermissionSource,          -- DIRECT / ROLE
    pe.RoleName,                  -- NULL for DIRECT
    pe.state_desc,
    pe.permission_name,
    pe.class_desc,
    CASE pe.class_desc
         WHEN 'DATABASE' THEN DB_NAME()
         WHEN 'SCHEMA'   THEN SCHEMA_NAME(pe.major_id)
         WHEN 'OBJECT_OR_COLUMN' THEN
             QUOTENAME(OBJECT_SCHEMA_NAME(pe.major_id)) + '.' +
             QUOTENAME(OBJECT_NAME(pe.major_id))
         ELSE NULL
    END               AS SecuredObject,
    CASE
         WHEN pe.class_desc = 'OBJECT_OR_COLUMN'
          AND pe.minor_id > 0 THEN COL_NAME(pe.major_id, pe.minor_id)
         ELSE NULL
    END               AS ColumnName,
    pe.major_id,
    pe.minor_id
FROM    PermsExpanded pe
ORDER BY
    pe.UserName,
    pe.PermissionSource,
    pe.RoleName,
    pe.class_desc,
    pe.permission_name,
    pe.state_desc;
