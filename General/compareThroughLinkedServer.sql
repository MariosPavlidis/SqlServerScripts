/* 
/*Create a Linked server from new server to old named [OLD] */


EXEC master.dbo.sp_addlinkedserver
    @server     = N'OLD',
    @srvproduct = N'',
    @provider   = N'MSOLEDBSQL',
    @datasrc    = N'mssqlsectools\mssqlsectools';



 EXEC master.dbo.sp_serveroption @server = N'OLD', @optname = N'rpc',     @optvalue = N'true';
EXEC master.dbo.sp_serveroption @server = N'OLD', @optname = N'rpc out', @optvalue = N'true';
*/

/* LOGINS: detect missing/extra and drift (SID, type, default DB, disabled, password hash) */

WITH old_logins AS
(
    SELECT 
        sp.name,
        sp.type_desc,
        sp.sid,
        sp.default_database_name,
        sp.is_disabled,
        sl.password_hash
    FROM [OLD].master.sys.server_principals AS sp
    LEFT JOIN [OLD].master.sys.sql_logins AS sl
        ON sl.principal_id = sp.principal_id
    WHERE sp.type IN ('S','U','G')          -- SQL login, Windows login, Windows group
      AND sp.name NOT LIKE '##%##'          -- ignore system-generated cert/proxy logins
      AND sp.name NOT IN ('sa')             -- optional: handle separately if you want
),
new_logins AS
(
    SELECT
        sp.name,
        sp.type_desc,
        sp.sid,
        sp.default_database_name,
        sp.is_disabled,
        sl.password_hash
    FROM master.sys.server_principals AS sp
    LEFT JOIN master.sys.sql_logins AS sl
        ON sl.principal_id = sp.principal_id
    WHERE sp.type IN ('S','U','G')
      AND sp.name NOT LIKE '##%##'
      AND sp.name NOT IN ('sa')
)
-- Missing on NEW
SELECT 'LOGINS:MISSING_ON_NEW' AS finding, o.*
FROM old_logins o
LEFT JOIN new_logins n ON n.name = o.name
WHERE n.name IS NULL

UNION ALL

-- Extra on NEW
SELECT 'LOGINS:EXTRA_ON_NEW' AS finding, n.*
FROM new_logins n
LEFT JOIN old_logins o ON o.name = n.name
WHERE o.name IS NULL

UNION ALL

-- Drift
SELECT 'LOGINS:DIFFERENT' AS finding, n.*
FROM new_logins n
JOIN old_logins o ON o.name = n.name
WHERE ISNULL(n.type_desc,'') <> ISNULL(o.type_desc,'')
   OR ISNULL(n.sid,0x) <> ISNULL(o.sid,0x)
   OR ISNULL(n.default_database_name,'') <> ISNULL(o.default_database_name,'')
   OR ISNULL(n.is_disabled,0) <> ISNULL(o.is_disabled,0)
   OR ISNULL(n.password_hash,0x) <> ISNULL(o.password_hash,0x)
ORDER BY finding, name;
/* SERVER ROLE MEMBERSHIPS */
WITH old_rm AS
(
    SELECT r.name AS role_name, m.name AS member_name
    FROM [OLD].master.sys.server_role_members srm
    JOIN [OLD].master.sys.server_principals r ON r.principal_id = srm.role_principal_id
    JOIN [OLD].master.sys.server_principals m ON m.principal_id = srm.member_principal_id
),
new_rm AS
(
    SELECT r.name AS role_name, m.name AS member_name
    FROM master.sys.server_role_members srm
    JOIN master.sys.server_principals r ON r.principal_id = srm.role_principal_id
    JOIN master.sys.server_principals m ON m.principal_id = srm.member_principal_id
)
SELECT 'SERVER ROLE MEMBERSHIPS: MISSING_ON_NEW' AS finding, * FROM old_rm
EXCEPT
SELECT 'SERVER ROLE MEMBERSHIPS: MISSING_ON_NEW', * FROM new_rm
UNION ALL
SELECT 'SERVER ROLE MEMBERSHIPS: EXTRA_ON_NEW', * FROM new_rm
EXCEPT
SELECT 'SERVER ROLE MEMBERSHIPS: EXTRA_ON_NEW', * FROM old_rm
ORDER BY finding, role_name, member_name;

/* SERVER PERMISSIONS */
WITH old_perm AS
(
    SELECT
        grantee.name AS grantee_name,
        perm.permission_name,
        perm.state_desc,
        COALESCE(obj.name, 'SERVER') AS securable
    FROM [OLD].master.sys.server_permissions perm
    JOIN [OLD].master.sys.server_principals grantee
      ON grantee.principal_id = perm.grantee_principal_id
    LEFT JOIN [OLD].master.sys.endpoints obj
      ON obj.endpoint_id = perm.major_id  -- for endpoint permissions; otherwise SERVER-level
),
new_perm AS
(
    SELECT
        grantee.name AS grantee_name,
        perm.permission_name,
        perm.state_desc,
        COALESCE(obj.name, 'SERVER') AS securable
    FROM master.sys.server_permissions perm
    JOIN master.sys.server_principals grantee
      ON grantee.principal_id = perm.grantee_principal_id
    LEFT JOIN master.sys.endpoints obj
      ON obj.endpoint_id = perm.major_id
)
SELECT 'SERVER PERMISSIONS: MISSING_ON_NEW' AS finding, * FROM old_perm
EXCEPT
SELECT 'SERVER PERMISSIONS: MISSING_ON_NEW', * FROM new_perm
UNION ALL
SELECT 'SERVER PERMISSIONS: EXTRA_ON_NEW', * FROM new_perm
EXCEPT
SELECT 'SERVER PERMISSIONS: EXTRA_ON_NEW', * FROM old_perm
ORDER BY finding, grantee_name, permission_name, securable;


/* JOBS: missing/extra + drift using a canonical SHA2_256 hash over job definition */

WITH old_job_def AS
(
    SELECT
        j.name AS job_name,
        HASHBYTES('SHA2_256', CONVERT(varbinary(max),
            CONCAT(
              'enabled=', j.enabled, ';',
              'owner_sid=', master.sys.fn_varbintohexstr(j.owner_sid), ';',
              'desc=', ISNULL(j.description,''), ';',
              'steps=',
              ISNULL((
                SELECT STRING_AGG(CONCAT(s.step_id,':',s.step_name,':',s.subsystem,':',ISNULL(s.database_name,''),':',ISNULL(s.command,'')), '|')
                       WITHIN GROUP (ORDER BY s.step_id)
                FROM [OLD].msdb.dbo.sysjobsteps s
                WHERE s.job_id = j.job_id
              ), ''),
              ';schedules=',
              ISNULL((
                SELECT STRING_AGG(CONCAT(sc.name,':',sc.freq_type,':',sc.freq_interval,':',sc.freq_subday_type,':',sc.freq_subday_interval,':',sc.active_start_time,':',sc.active_start_date), '|')
                       WITHIN GROUP (ORDER BY sc.schedule_id)
                FROM [OLD].msdb.dbo.sysjobschedules js
                JOIN [OLD].msdb.dbo.sysschedules sc ON sc.schedule_id = js.schedule_id
                WHERE js.job_id = j.job_id
              ), '')
            )
        )) AS job_hash
    FROM [OLD].msdb.dbo.sysjobs j
),
new_job_def AS
(
    SELECT
        j.name AS job_name,
        HASHBYTES('SHA2_256', CONVERT(varbinary(max),
            CONCAT(
              'enabled=', j.enabled, ';',
              'owner_sid=', master.sys.fn_varbintohexstr(j.owner_sid), ';',
              'desc=', ISNULL(j.description,''), ';',
              'steps=',
              ISNULL((
                SELECT STRING_AGG(CONCAT(s.step_id,':',s.step_name,':',s.subsystem,':',ISNULL(s.database_name,''),':',ISNULL(s.command,'')), '|')
                       WITHIN GROUP (ORDER BY s.step_id)
                FROM msdb.dbo.sysjobsteps s
                WHERE s.job_id = j.job_id
              ), ''),
              ';schedules=',
              ISNULL((
                SELECT STRING_AGG(CONCAT(sc.name,':',sc.freq_type,':',sc.freq_interval,':',sc.freq_subday_type,':',sc.freq_subday_interval,':',sc.active_start_time,':',sc.active_start_date), '|')
                       WITHIN GROUP (ORDER BY sc.schedule_id)
                FROM msdb.dbo.sysjobschedules js
                JOIN msdb.dbo.sysschedules sc ON sc.schedule_id = js.schedule_id
                WHERE js.job_id = j.job_id
              ), '')
            )
        )) AS job_hash
    FROM msdb.dbo.sysjobs j
)
SELECT 'JOBS: MISSING_ON_NEW' AS finding, o.job_name
FROM old_job_def o
LEFT JOIN new_job_def n ON n.job_name = o.job_name
WHERE n.job_name IS NULL

UNION ALL
SELECT 'JOBS: EXTRA_ON_NEW', n.job_name
FROM new_job_def n
LEFT JOIN old_job_def o ON o.job_name = n.job_name
WHERE o.job_name IS NULL

UNION ALL
SELECT 'JOBS: DIFFERENT', n.job_name
FROM new_job_def n
JOIN old_job_def o ON o.job_name = n.job_name
WHERE n.job_hash <> o.job_hash
ORDER BY finding, job_name;


/* OPERATORS */
SELECT 'OPERATORS: MISSING_ON_NEW' AS finding, o.name
FROM [OLD].msdb.dbo.sysoperators o
LEFT JOIN msdb.dbo.sysoperators n ON n.name = o.name
WHERE n.name IS NULL
UNION ALL
SELECT 'OPERATORS: EXTRA_ON_NEW', n.name
FROM msdb.dbo.sysoperators n
LEFT JOIN [OLD].msdb.dbo.sysoperators o ON o.name = n.name
WHERE o.name IS NULL
ORDER BY finding, name;

/* ALERTS */
SELECT 'ALERTS : MISSING_ON_NEW' AS finding, o.name
FROM [OLD].msdb.dbo.sysalerts o
LEFT JOIN msdb.dbo.sysalerts n ON n.name = o.name
WHERE n.name IS NULL
UNION ALL
SELECT 'ALERTS : EXTRA_ON_NEW', n.name
FROM msdb.dbo.sysalerts n
LEFT JOIN [OLD].msdb.dbo.sysalerts o ON o.name = n.name
WHERE o.name IS NULL
ORDER BY finding, name;

/* CREDENTIALS */
SELECT 'CREDENTIALS: MISSING_ON_NEW' AS finding, o.name
FROM [OLD].master.sys.credentials o
LEFT JOIN master.sys.credentials n ON n.name = o.name
WHERE n.name IS NULL
UNION ALL
SELECT 'CREDENTIALS: EXTRA_ON_NEW', n.name
FROM master.sys.credentials n
LEFT JOIN [OLD].master.sys.credentials o ON o.name = n.name
WHERE o.name IS NULL
ORDER BY finding, name;

/* AGENT PROXIES */
SELECT 'AGENT PROXIES: MISSING_ON_NEW' AS finding, o.name
FROM [OLD].msdb.dbo.sysproxies o
LEFT JOIN msdb.dbo.sysproxies n ON n.name = o.name
WHERE n.name IS NULL
UNION ALL
SELECT 'AGENT PROXIES: EXTRA_ON_NEW', n.name
FROM msdb.dbo.sysproxies n
LEFT JOIN [OLD].msdb.dbo.sysproxies o ON o.name = n.name
WHERE o.name IS NULL
ORDER BY finding, name;

SELECT 'AGENT PROXIES: MISSING_ON_NEW' AS finding, o.name, o.product, o.provider, o.data_source
FROM [OLD].master.sys.servers o
LEFT JOIN master.sys.servers n ON n.name = o.name
WHERE o.is_linked = 1
  AND n.name IS NULL

UNION ALL
SELECT 'AGENT PROXIES: EXTRA_ON_NEW', n.name, n.product, n.provider, n.data_source
FROM master.sys.servers n
LEFT JOIN [OLD].master.sys.servers o ON o.name = n.name
WHERE n.is_linked = 1
  AND o.name IS NULL
ORDER BY finding, name;



/* DATABASE MAIL: accounts, profiles, and mappings OLD vs NEW (no RPC required) */

-----------------------------------------------------------------------
-- 1) Accounts (name + key settings)
-----------------------------------------------------------------------
WITH old_acct AS
(
    SELECT
        a.name                                AS account_name,
        a.email_address,
        a.display_name,
        a.replyto_address,
        a.description,
        s.servername,
        s.port,
        s.enable_ssl,
        s.username
    FROM [OLD].msdb.dbo.sysmail_account a
    JOIN [OLD].msdb.dbo.sysmail_server  s
      ON s.account_id = a.account_id
),
new_acct AS
(
    SELECT
        a.name                                AS account_name,
        a.email_address,
        a.display_name,
        a.replyto_address,
        a.description,
        s.servername,
        s.port,
        s.enable_ssl,
        s.username
    FROM msdb.dbo.sysmail_account a
    JOIN msdb.dbo.sysmail_server  s
      ON s.account_id = a.account_id
)
SELECT 'DATABASE MAIL: MISSING_ON_NEW' AS finding, o.*
FROM old_acct o
LEFT JOIN new_acct n ON n.account_name = o.account_name
WHERE n.account_name IS NULL

UNION ALL

SELECT 'DATABASE MAIL: EXTRA_ON_NEW', n.*
FROM new_acct n
LEFT JOIN old_acct o ON o.account_name = n.account_name
WHERE o.account_name IS NULL

UNION ALL

SELECT 'DATABASE MAIL: DIFFERENT', n.*
FROM new_acct n
JOIN old_acct o ON o.account_name = n.account_name
WHERE ISNULL(n.email_address,'') <> ISNULL(o.email_address,'')
   OR ISNULL(n.display_name,'')  <> ISNULL(o.display_name,'')
   OR ISNULL(n.replyto_address,'')<> ISNULL(o.replyto_address,'')
   OR ISNULL(n.description,'')   <> ISNULL(o.description,'')
   OR ISNULL(n.servername,'')    <> ISNULL(o.servername,'')
   OR ISNULL(n.port,0)           <> ISNULL(o.port,0)
   OR ISNULL(n.enable_ssl,0)     <> ISNULL(o.enable_ssl,0)
   OR ISNULL(n.username,'')      <> ISNULL(o.username,'')
ORDER BY finding, account_name;

-----------------------------------------------------------------------
-- 2) Profiles (name + description)
-----------------------------------------------------------------------
WITH old_prof AS
(
    SELECT name AS profile_name, description
    FROM [OLD].msdb.dbo.sysmail_profile
),
new_prof AS
(
    SELECT name AS profile_name, description
    FROM msdb.dbo.sysmail_profile
)
SELECT 'DATABASE MAIL PROFILES: MISSING_ON_NEW' AS finding, o.*
FROM old_prof o
LEFT JOIN new_prof n ON n.profile_name = o.profile_name
WHERE n.profile_name IS NULL

UNION ALL

SELECT 'DATABASE MAIL PROFILES: EXTRA_ON_NEW', n.*
FROM new_prof n
LEFT JOIN old_prof o ON o.profile_name = n.profile_name
WHERE o.profile_name IS NULL

UNION ALL

SELECT 'DATABASE MAIL PROFILES: DIFFERENT', n.*
FROM new_prof n
JOIN old_prof o ON o.profile_name = n.profile_name
WHERE ISNULL(n.description,'') <> ISNULL(o.description,'')
ORDER BY finding, profile_name;

-----------------------------------------------------------------------
-- 3) Profile <-> Account mappings (order matters via sequence_number)
-----------------------------------------------------------------------
WITH old_map AS
(
    SELECT
        p.name AS profile_name,
        a.name AS account_name,
        pa.sequence_number
    FROM [OLD].msdb.dbo.sysmail_profileaccount pa
    JOIN [OLD].msdb.dbo.sysmail_profile p ON p.profile_id = pa.profile_id
    JOIN [OLD].msdb.dbo.sysmail_account a ON a.account_id = pa.account_id
),
new_map AS
(
    SELECT
        p.name AS profile_name,
        a.name AS account_name,
        pa.sequence_number
    FROM msdb.dbo.sysmail_profileaccount pa
    JOIN msdb.dbo.sysmail_profile p ON p.profile_id = pa.profile_id
    JOIN msdb.dbo.sysmail_account a ON a.account_id = pa.account_id
)
SELECT 'DATABASE MAIL PROFILES - ACCOUNTS: MISSING_ON_NEW' AS finding, * FROM old_map
EXCEPT
SELECT 'DATABASE MAIL PROFILES - ACCOUNTS: MISSING_ON_NEW', * FROM new_map

UNION ALL

SELECT 'DATABASE MAIL PROFILES - ACCOUNTS: EXTRA_ON_NEW', * FROM new_map
EXCEPT
SELECT 'DATABASE MAIL PROFILES - ACCOUNTS: EXTRA_ON_NEW', * FROM old_map
ORDER BY finding, profile_name, sequence_number, account_name;

-----------------------------------------------------------------------
-- 4) Profile principals (public/default/private access)
-----------------------------------------------------------------------
WITH old_pp AS
(
    SELECT
        p.name AS profile_name,
        pr.name AS principal_name,
        pp.is_default
    FROM [OLD].msdb.dbo.sysmail_principalprofile pp
    JOIN [OLD].msdb.dbo.sysmail_profile p
      ON p.profile_id = pp.profile_id
    JOIN [OLD].master.sys.database_principals pr   -- principals live in msdb, but names resolve via msdb principals
      ON pr.sid = pp.principal_sid
),
new_pp AS
(
    SELECT
        p.name AS profile_name,
        pr.name AS principal_name,
        pp.is_default
    FROM msdb.dbo.sysmail_principalprofile pp
    JOIN msdb.dbo.sysmail_profile p
      ON p.profile_id = pp.profile_id
    JOIN master.sys.database_principals pr
      ON pr.sid = pp.principal_sid
)
SELECT 'Profile principals: MISSING_ON_NEW' AS finding, * FROM old_pp
EXCEPT
SELECT 'Profile principals: MISSING_ON_NEW', * FROM new_pp

UNION ALL

SELECT 'Profile principals: EXTRA_ON_NEW', * FROM new_pp
EXCEPT
SELECT 'Profile principals: EXTRA_ON_NEW', * FROM old_pp
ORDER BY finding, profile_name, principal_name;

/* CERTIFICATES (master) */
WITH old_c AS (
  SELECT name, thumbprint, subject, issuer_name, start_date, expiry_date,
         pvt_key_encryption_type_desc, key_length
  FROM [OLD].master.sys.certificates
),
new_c AS (
  SELECT name, thumbprint, subject, issuer_name, start_date, expiry_date,
         pvt_key_encryption_type_desc, key_length
  FROM master.sys.certificates
)
SELECT 'CERTIFICATES (master): MISSING_ON_NEW' AS finding, o.* FROM old_c o
LEFT JOIN new_c n ON n.name = o.name
WHERE n.name IS NULL
UNION ALL
SELECT 'CERTIFICATES (master): EXTRA_ON_NEW', n.* FROM new_c n
LEFT JOIN old_c o ON o.name = n.name
WHERE o.name IS NULL
UNION ALL
SELECT 'CERTIFICATES (master): DIFFERENT', n.* FROM new_c n
JOIN old_c o ON o.name = n.name
WHERE ISNULL(n.thumbprint,0x) <> ISNULL(o.thumbprint,0x)
   OR ISNULL(n.subject,'')    <> ISNULL(o.subject,'')
   OR ISNULL(n.issuer_name,'')<> ISNULL(o.issuer_name,'')
   OR ISNULL(n.start_date,'19000101') <> ISNULL(o.start_date,'19000101')
   OR ISNULL(n.expiry_date,'19000101')<> ISNULL(o.expiry_date,'19000101')
   OR ISNULL(n.pvt_key_encryption_type_desc,'') <> ISNULL(o.pvt_key_encryption_type_desc,'')
   OR ISNULL(n.key_length,0) <> ISNULL(o.key_length,0)
ORDER BY finding, name;



/* ASYMMETRIC KEYS (master) */
WITH old_a AS (
  SELECT name, thumbprint, algorithm_desc, key_length
  FROM [OLD].master.sys.asymmetric_keys
),
new_a AS (
  SELECT name, thumbprint, algorithm_desc, key_length
  FROM master.sys.asymmetric_keys
)
SELECT 'ASYMMETRIC KEYS (master): MISSING_ON_NEW' AS finding, * FROM old_a
EXCEPT SELECT 'ASYMMETRIC KEYS (master): MISSING_ON_NEW', * FROM new_a
UNION ALL
SELECT 'ASYMMETRIC KEYS (master): EXTRA_ON_NEW', * FROM new_a
EXCEPT SELECT 'ASYMMETRIC KEYS (master): EXTRA_ON_NEW', * FROM old_a
ORDER BY finding, name;

/* SYMMETRIC KEYS (master) */
WITH old_s AS (
  SELECT name, key_length, algorithm_desc, create_date
  FROM [OLD].master.sys.symmetric_keys
),
new_s AS (
  SELECT name, key_length, algorithm_desc, create_date
  FROM master.sys.symmetric_keys
)
SELECT 'SYMMETRIC KEYS (master): MISSING_ON_NEW' AS finding, * FROM old_s
EXCEPT SELECT 'SYMMETRIC KEYS (master): MISSING_ON_NEW', * FROM new_s
UNION ALL
SELECT 'SYMMETRIC KEYS (master): EXTRA_ON_NEW', * FROM new_s
EXCEPT SELECT 'SYMMETRIC KEYS (master): EXTRA_ON_NEW', * FROM old_s
ORDER BY finding, name;



/* ENDPOINTS */
WITH old_e AS (
  SELECT e.name, e.type_desc, e.protocol_desc, e.state_desc, e.is_admin_endpoint
  FROM [OLD].master.sys.endpoints e
),
new_e AS (
  SELECT e.name, e.type_desc, e.protocol_desc, e.state_desc, e.is_admin_endpoint
  FROM master.sys.endpoints e
)
SELECT 'ENDPOINTS: MISSING_ON_NEW' AS finding, * FROM old_e
EXCEPT SELECT 'ENDPOINTS: MISSING_ON_NEW', * FROM new_e
UNION ALL
SELECT 'ENDPOINTS: EXTRA_ON_NEW', * FROM new_e
EXCEPT SELECT 'ENDPOINTS: EXTRA_ON_NEW', * FROM old_e
ORDER BY finding, name;

/* TCP ENDPOINT DETAILS */
WITH old_t AS (
  SELECT e.name AS endpoint_name, t.port, t.ip_address
  FROM [OLD].master.sys.endpoints e
  JOIN [OLD].master.sys.tcp_endpoints t ON t.endpoint_id = e.endpoint_id
),
new_t AS (
  SELECT e.name AS endpoint_name, t.port, t.ip_address
  FROM master.sys.endpoints e
  JOIN master.sys.tcp_endpoints t ON t.endpoint_id = e.endpoint_id
)
SELECT 'TCP ENDPOINT DETAILS: MISSING_ON_NEW' AS finding, * FROM old_t
EXCEPT SELECT 'TCP ENDPOINT DETAILS: MISSING_ON_NEW', * FROM new_t
UNION ALL
SELECT 'TCP ENDPOINT DETAILS: EXTRA_ON_NEW', * FROM new_t
EXCEPT SELECT 'TCP ENDPOINT DETAILS: EXTRA_ON_NEW', * FROM old_t
ORDER BY finding, endpoint_name;


/* SERVER CONFIGURATION */
WITH old_cfg AS (
  SELECT name, value, value_in_use, is_dynamic, is_advanced
  FROM [OLD].master.sys.configurations
),
new_cfg AS (
  SELECT name, value, value_in_use, is_dynamic, is_advanced
  FROM master.sys.configurations
)
SELECT 'SERVER CONFIGURATION: DIFFERENT' AS finding, n.*
FROM new_cfg n
JOIN old_cfg o ON o.name = n.name
WHERE ISNULL(n.value,-1) <> ISNULL(o.value,-1)
   OR ISNULL(n.value_in_use,-1) <> ISNULL(o.value_in_use,-1)
   OR ISNULL(n.is_dynamic,-1) <> ISNULL(o.is_dynamic,-1)
   OR ISNULL(n.is_advanced,-1) <> ISNULL(o.is_advanced,-1)
ORDER BY n.name;


/* SERVER AUDITS */
WITH old_a AS (
  SELECT name, type_desc, is_state_enabled, audit_guid, queue_delay, on_failure_desc
  FROM [OLD].master.sys.server_audits
),
new_a AS (
  SELECT name, type_desc, is_state_enabled, audit_guid, queue_delay, on_failure_desc
  FROM master.sys.server_audits
)
SELECT 'SERVER AUDITS: MISSING_ON_NEW' AS finding, * FROM old_a
EXCEPT SELECT 'SERVER AUDITS: MISSING_ON_NEW', * FROM new_a
UNION ALL
SELECT 'SERVER AUDITS: EXTRA_ON_NEW', * FROM new_a
EXCEPT SELECT 'SERVER AUDITS: EXTRA_ON_NEW', * FROM old_a
ORDER BY finding, name;

/* SERVER AUDIT SPECS */
WITH old_s AS (
  SELECT ss.name, ss.is_state_enabled
  FROM [OLD].master.sys.server_audit_specifications ss
),
new_s AS (
  SELECT ss.name, ss.is_state_enabled
  FROM master.sys.server_audit_specifications ss
)
SELECT 'SERVER AUDIT SPECS: MISSING_ON_NEW' AS finding, * FROM old_s
EXCEPT SELECT 'SERVER AUDIT SPECS: MISSING_ON_NEW', * FROM new_s
UNION ALL
SELECT 'SERVER AUDIT SPECS: EXTRA_ON_NEW', * FROM new_s
EXCEPT SELECT 'SERVER AUDIT SPECS: EXTRA_ON_NEW', * FROM old_s
ORDER BY finding, name;

/* XE SESSIONS */
WITH old_xe AS (
  SELECT name, startup_state
  FROM [OLD].master.sys.server_event_sessions
),
new_xe AS (
  SELECT name, startup_state
  FROM master.sys.server_event_sessions
)
SELECT 'XE SESSIONS: MISSING_ON_NEW' AS finding, * FROM old_xe
EXCEPT SELECT 'XE SESSIONS: MISSING_ON_NEW', * FROM new_xe
UNION ALL
SELECT 'XE SESSIONS: EXTRA_ON_NEW', * FROM new_xe
EXCEPT SELECT 'XE SESSIONS: EXTRA_ON_NEW', * FROM old_xe
ORDER BY finding, name;



/*
Compare objects across all user databases between OLD (linked server) and LOCAL (NEW).

Covers:
- Tables, views, procs, functions, triggers, synonyms, sequences
- Columns & data types (table/view columns)
- Indexes (basic inventory)
- Programmable object definition checksum via sys.sql_modules (where applicable)

You can narrow to specific DBs by filtering in the @dbs table.


SET NOCOUNT ON;

IF OBJECT_ID('tempdb..#inv_new') IS NOT NULL DROP TABLE #inv_new;
IF OBJECT_ID('tempdb..#inv_old') IS NOT NULL DROP TABLE #inv_old;

CREATE TABLE #inv_new
(
    server_name   sysname,
    db_name       sysname,
    schema_name   sysname,
    object_name   sysname,
    object_type   nvarchar(60),
    sub_type      nvarchar(60) NULL,       -- e.g. COLUMN / INDEX
    sub_name      sysname NULL,            -- column name / index name
    detail        nvarchar(4000) NULL,     -- datatype, index cols summary, etc.
    def_hash      varbinary(32) NULL       -- SHA2_256 hash of definition (for procs/views/fns/triggers)
);

CREATE TABLE #inv_old
(
    server_name   sysname,
    db_name       sysname,
    schema_name   sysname,
    object_name   sysname,
    object_type   nvarchar(60),
    sub_type      nvarchar(60) NULL,
    sub_name      sysname NULL,
    detail        nvarchar(4000) NULL,
    def_hash      varbinary(32) NULL
);

DECLARE @dbs TABLE(db sysname);
INSERT @dbs(db)
SELECT name
FROM sys.databases
WHERE database_id > 4
  AND state_desc = 'ONLINE';

DECLARE @db sysname;
DECLARE dbcur CURSOR LOCAL FAST_FORWARD FOR SELECT db FROM @dbs;
OPEN dbcur;
FETCH NEXT FROM dbcur INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE @sql_new nvarchar(max) = N'
USE ' + QUOTENAME(@db) + N';

;WITH base AS
(
    SELECT
        DB_NAME() AS db_name,
        s.name    AS schema_name,
        o.name    AS object_name,
        o.type    AS object_type_code,
        o.type_desc AS object_type_desc,
        o.object_id
    FROM sys.objects o
    JOIN sys.schemas s ON s.schema_id = o.schema_id
    WHERE o.is_ms_shipped = 0
      AND o.type IN (''U'',''V'',''P'',''FN'',''IF'',''TF'',''TR'',''SN'')  -- table, view, proc, funcs, trigger, synonym
),
mods AS
(
    SELECT
        object_id,
        HASHBYTES(''SHA2_256'', CONVERT(varbinary(max), definition)) AS def_hash
    FROM sys.sql_modules
)
INSERT INTO #inv_new(server_name, db_name, schema_name, object_name, object_type, sub_type, sub_name, detail, def_hash)
SELECT
    @@SERVERNAME,
    b.db_name,
    b.schema_name,
    b.object_name,
    b.object_type_desc,
    NULL, NULL, NULL,
    m.def_hash
FROM base b
LEFT JOIN mods m ON m.object_id = b.object_id;

-- Columns (tables + views)
INSERT INTO #inv_new(server_name, db_name, schema_name, object_name, object_type, sub_type, sub_name, detail, def_hash)
SELECT
    @@SERVERNAME,
    DB_NAME(),
    s.name,
    o.name,
    o.type_desc,
    ''COLUMN'',
    c.name,
    CONCAT(
        t.name,
        CASE
            WHEN t.name IN (''varchar'',''char'',''varbinary'',''binary'') THEN CONCAT(''('', IIF(c.max_length=-1, ''max'', CONVERT(varchar(10), c.max_length)), '')'')
            WHEN t.name IN (''nvarchar'',''nchar'') THEN CONCAT(''('', IIF(c.max_length=-1, ''max'', CONVERT(varchar(10), c.max_length/2)), '')'')
            WHEN t.name IN (''decimal'',''numeric'') THEN CONCAT(''('', c.precision, '','', c.scale, '')'')
            WHEN t.name IN (''datetime2'',''datetimeoffset'',''time'') THEN CONCAT(''('', c.scale, '')'')
            ELSE ''''
        END,
        '' | null='', c.is_nullable,
        '' | identity='', c.is_identity
    ),
    NULL
FROM sys.objects o
JOIN sys.schemas s ON s.schema_id = o.schema_id
JOIN sys.columns c ON c.object_id = o.object_id
JOIN sys.types t ON t.user_type_id = c.user_type_id
WHERE o.is_ms_shipped = 0
  AND o.type IN (''U'',''V'');

-- Index inventory (tables only)
INSERT INTO #inv_new(server_name, db_name, schema_name, object_name, object_type, sub_type, sub_name, detail, def_hash)
SELECT
    @@SERVERNAME,
    DB_NAME(),
    s.name,
    o.name,
    o.type_desc,
    ''INDEX'',
    i.name,
    CONCAT(
        ''type='', i.type_desc,
        '' | unique='', i.is_unique,
        '' | pk='', i.is_primary_key,
        '' | filter='', COALESCE(i.filter_definition, ''(none)'')
    ),
    NULL
FROM sys.objects o
JOIN sys.schemas s ON s.schema_id = o.schema_id
JOIN sys.indexes i ON i.object_id = o.object_id
WHERE o.is_ms_shipped = 0
  AND o.type = ''U''
  AND i.index_id > 0;';

    EXEC sys.sp_executesql @sql_new;

    DECLARE @sql_old nvarchar(max) = N'
USE ' + QUOTENAME(@db) + N';

;WITH base AS
(
    SELECT
        DB_NAME() AS db_name,
        s.name    AS schema_name,
        o.name    AS object_name,
        o.type    AS object_type_code,
        o.type_desc AS object_type_desc,
        o.object_id
    FROM sys.objects o
    JOIN sys.schemas s ON s.schema_id = o.schema_id
    WHERE o.is_ms_shipped = 0
      AND o.type IN (''U'',''V'',''P'',''FN'',''IF'',''TF'',''TR'',''SN'')
),
mods AS
(
    SELECT
        object_id,
        HASHBYTES(''SHA2_256'', CONVERT(varbinary(max), definition)) AS def_hash
    FROM sys.sql_modules
)
INSERT INTO #inv_old(server_name, db_name, schema_name, object_name, object_type, sub_type, sub_name, detail, def_hash)
SELECT
    ''OLD'',
    b.db_name,
    b.schema_name,
    b.object_name,
    b.object_type_desc,
    NULL, NULL, NULL,
    m.def_hash
FROM base b
LEFT JOIN mods m ON m.object_id = b.object_id;

INSERT INTO #inv_old(server_name, db_name, schema_name, object_name, object_type, sub_type, sub_name, detail, def_hash)
SELECT
    ''OLD'',
    DB_NAME(),
    s.name,
    o.name,
    o.type_desc,
    ''COLUMN'',
    c.name,
    CONCAT(
        t.name,
        CASE
            WHEN t.name IN (''varchar'',''char'',''varbinary'',''binary'') THEN CONCAT(''('', IIF(c.max_length=-1, ''max'', CONVERT(varchar(10), c.max_length)), '')'')
            WHEN t.name IN (''nvarchar'',''nchar'') THEN CONCAT(''('', IIF(c.max_length=-1, ''max'', CONVERT(varchar(10), c.max_length/2)), '')'')
            WHEN t.name IN (''decimal'',''numeric'') THEN CONCAT(''('', c.precision, '','', c.scale, '')'')
            WHEN t.name IN (''datetime2'',''datetimeoffset'',''time'') THEN CONCAT(''('', c.scale, '')'')
            ELSE ''''
        END,
        '' | null='', c.is_nullable,
        '' | identity='', c.is_identity
    ),
    NULL
FROM sys.objects o
JOIN sys.schemas s ON s.schema_id = o.schema_id
JOIN sys.columns c ON c.object_id = o.object_id
JOIN sys.types t ON t.user_type_id = c.user_type_id
WHERE o.is_ms_shipped = 0
  AND o.type IN (''U'',''V'');

INSERT INTO #inv_old(server_name, db_name, schema_name, object_name, object_type, sub_type, sub_name, detail, def_hash)
SELECT
    ''OLD'',
    DB_NAME(),
    s.name,
    o.name,
    o.type_desc,
    ''INDEX'',
    i.name,
    CONCAT(
        ''type='', i.type_desc,
        '' | unique='', i.is_unique,
        '' | pk='', i.is_primary_key,
        '' | filter='', COALESCE(i.filter_definition, ''(none)'')
    ),
    NULL
FROM sys.objects o
JOIN sys.schemas s ON s.schema_id = o.schema_id
JOIN sys.indexes i ON i.object_id = o.object_id
WHERE o.is_ms_shipped = 0
  AND o.type = ''U''
  AND i.index_id > 0;';

  EXEC (@sql_old) AT [OLD];

    FETCH NEXT FROM dbcur INTO @db;
END

CLOSE dbcur;
DEALLOCATE dbcur;

--------------------------------------------------------------------------------
-- RESULTS
--------------------------------------------------------------------------------

-- 1) Missing on NEW (exists on OLD, not on NEW)
SELECT
    o.db_name,
    o.schema_name,
    o.object_name,
    o.object_type,
    o.sub_type,
    o.sub_name,
    o.detail
FROM #inv_old o
LEFT JOIN #inv_new n
    ON  n.db_name      = o.db_name
    AND n.schema_name  = o.schema_name
    AND n.object_name  = o.object_name
    AND n.object_type  = o.object_type
    AND ISNULL(n.sub_type,'') = ISNULL(o.sub_type,'')
    AND ISNULL(n.sub_name,'') = ISNULL(o.sub_name,'')
    AND ISNULL(n.detail,'')   = ISNULL(o.detail,'')
WHERE n.db_name IS NULL
ORDER BY o.db_name, o.object_type, o.schema_name, o.object_name, o.sub_type, o.sub_name;

-- 2) Extra on NEW (exists on NEW, not on OLD)
SELECT
    n.db_name,
    n.schema_name,
    n.object_name,
    n.object_type,
    n.sub_type,
    n.sub_name,
    n.detail
FROM #inv_new n
LEFT JOIN #inv_old o
    ON  o.db_name      = n.db_name
    AND o.schema_name  = n.schema_name
    AND o.object_name  = n.object_name
    AND o.object_type  = n.object_type
    AND ISNULL(o.sub_type,'') = ISNULL(n.sub_type,'')
    AND ISNULL(o.sub_name,'') = ISNULL(n.sub_name,'')
    AND ISNULL(o.detail,'')   = ISNULL(n.detail,'')
WHERE o.db_name IS NULL
ORDER BY n.db_name, n.object_type, n.schema_name, n.object_name, n.sub_type, n.sub_name;

-- 3) Definition mismatch (programmable objects)
SELECT
    n.db_name,
    n.schema_name,
    n.object_name,
    n.object_type,
    o.def_hash AS old_def_hash,
    n.def_hash AS new_def_hash
FROM #inv_old o
JOIN #inv_new n
    ON  n.db_name     = o.db_name
    AND n.schema_name = o.schema_name
    AND n.object_name = o.object_name
    AND n.object_type = o.object_type
    AND o.sub_type IS NULL
    AND n.sub_type IS NULL
WHERE o.def_hash IS NOT NULL
  AND n.def_hash IS NOT NULL
  AND o.def_hash <> n.def_hash
ORDER BY n.db_name, n.object_type, n.schema_name, n.object_name;

*/



/* RUN LOCALLY ON EACH INSTANCE 
DBCC TRACESTATUS(-1) WITH NO_INFOMSGS;
*/