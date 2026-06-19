param(
    [string]$ServerInstance = ".\ION",
    [string]$OutputRoot = "C:\SQL_SystemDB_Rebuild_Export"
)

$ErrorActionPreference = "Stop"

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$OutDir = Join-Path $OutputRoot $timestamp

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$folders = @(
    "01_Logins",
    "02_ServerRoles",
    "03_LinkedServers",
    "04_Credentials",
    "05_SQLAgent_Jobs",
    "06_SQLAgent_Operators",
    "07_SQLAgent_Alerts",
    "08_SQLAgent_Proxies",
    "09_DatabaseMail",
    "10_SSIS_msdb",
    "11_Endpoints",
    "12_Certificates_Keys",
    "99_Inventory"
)

foreach ($f in $folders) {
    New-Item -ItemType Directory -Path (Join-Path $OutDir $f) -Force | Out-Null
}

Write-Host "Output folder: $OutDir"

# Load SMO
try {
    Add-Type -AssemblyName "Microsoft.SqlServer.Smo" -ErrorAction Stop
    Add-Type -AssemblyName "Microsoft.SqlServer.SmoExtended" -ErrorAction Stop
    Add-Type -AssemblyName "Microsoft.SqlServer.SqlEnum" -ErrorAction Stop
    Add-Type -AssemblyName "Microsoft.SqlServer.ConnectionInfo" -ErrorAction Stop
}
catch {
    Import-Module SqlServer -ErrorAction Stop
}

$srv = New-Object Microsoft.SqlServer.Management.Smo.Server $ServerInstance

$scripter = New-Object Microsoft.SqlServer.Management.Smo.Scripter $srv
$scripter.Options.ScriptDrops = $false
$scripter.Options.IncludeIfNotExists = $true
$scripter.Options.SchemaQualify = $true
$scripter.Options.NoCollation = $false
$scripter.Options.DriAll = $true
$scripter.Options.Indexes = $true
$scripter.Options.Triggers = $true
$scripter.Options.Permissions = $true
$scripter.Options.ToFileOnly = $false
$scripter.Options.AppendToFile = $false
$scripter.Options.Encoding = [System.Text.Encoding]::UTF8

function Safe-FileName {
    param([string]$Name)
    return ($Name -replace '[\\/:*?"<>|]', '_')
}

function Write-ScriptFile {
    param(
        [string]$Path,
        [string[]]$Lines
    )

    $content = @()
    $content += "/*"
    $content += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $content += "Server: $ServerInstance"
    $content += "*/"
    $content += ""
    $content += $Lines

    [System.IO.File]::WriteAllLines($Path, $content, [System.Text.Encoding]::UTF8)
}

function Invoke-Query {
    param([string]$Query)

    $conn = New-Object System.Data.SqlClient.SqlConnection
    $conn.ConnectionString = "Server=$ServerInstance;Database=master;Integrated Security=SSPI;TrustServerCertificate=True"
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $Query
    $cmd.CommandTimeout = 0
    $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
    $dt = New-Object System.Data.DataTable
    $conn.Open()
    [void]$adapter.Fill($dt)
    $conn.Close()
    return $dt
}

function Invoke-ScalarText {
    param([string]$Query)

    $conn = New-Object System.Data.SqlClient.SqlConnection
    $conn.ConnectionString = "Server=$ServerInstance;Database=master;Integrated Security=SSPI;TrustServerCertificate=True"
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $Query
    $cmd.CommandTimeout = 0
    $conn.Open()
    $result = $cmd.ExecuteScalar()
    $conn.Close()
    return [string]$result
}

# ---------------------------------------------------------------------
# 99 Inventory
# ---------------------------------------------------------------------

$inventorySql = @"
SELECT @@SERVERNAME AS server_name,
       SERVERPROPERTY('MachineName') AS machine_name,
       SERVERPROPERTY('InstanceName') AS instance_name,
       SERVERPROPERTY('Edition') AS edition,
       SERVERPROPERTY('ProductVersion') AS product_version,
       SERVERPROPERTY('ProductLevel') AS product_level,
       SERVERPROPERTY('ProductUpdateLevel') AS product_update_level,
       SERVERPROPERTY('Collation') AS server_collation;
"@

Invoke-Query $inventorySql | Export-Csv (Join-Path $OutDir "99_Inventory\server_properties.csv") -NoTypeInformation -Encoding UTF8

Invoke-Query "
SELECT name, database_id, state_desc, collation_name, recovery_model_desc
FROM sys.databases
ORDER BY database_id;
" | Export-Csv (Join-Path $OutDir "99_Inventory\databases.csv") -NoTypeInformation -Encoding UTF8

# ---------------------------------------------------------------------
# 01 Logins
# SQL login password hashes are scripted.
# Windows login/group passwords do not exist in SQL Server.
# ---------------------------------------------------------------------

$loginScript = Invoke-ScalarText @"
DECLARE @crlf nchar(2) = NCHAR(13) + NCHAR(10);
DECLARE @sql nvarchar(max) = N'';

SELECT @sql +=
CASE 
    WHEN sp.type = 'S' THEN
        N'IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N''' + REPLACE(sp.name,'''','''''') + N''')' + @crlf +
        N'    CREATE LOGIN ' + QUOTENAME(sp.name) +
        N' WITH PASSWORD = ' + CONVERT(nvarchar(max), sl.password_hash, 1) + N' HASHED, ' +
        N'SID = ' + CONVERT(nvarchar(max), sp.sid, 1) + N', ' +
        N'DEFAULT_DATABASE = ' + QUOTENAME(COALESCE(sp.default_database_name, N'master')) + N', ' +
        N'DEFAULT_LANGUAGE = ' + QUOTENAME(COALESCE(sp.default_language_name, N'us_english')) + N', ' +
        N'CHECK_POLICY = ' + CASE WHEN sl.is_policy_checked = 1 THEN N'ON' ELSE N'OFF' END + N', ' +
        N'CHECK_EXPIRATION = ' + CASE WHEN sl.is_expiration_checked = 1 THEN N'ON' ELSE N'OFF' END + N';' + @crlf +
        CASE WHEN sp.is_disabled = 1 THEN N'ALTER LOGIN ' + QUOTENAME(sp.name) + N' DISABLE;' + @crlf ELSE N'' END
    WHEN sp.type IN ('U','G') THEN
        N'IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N''' + REPLACE(sp.name,'''','''''') + N''')' + @crlf +
        N'    CREATE LOGIN ' + QUOTENAME(sp.name) + N' FROM WINDOWS WITH DEFAULT_DATABASE = ' +
        QUOTENAME(COALESCE(sp.default_database_name, N'master')) + N';' + @crlf +
        CASE WHEN sp.is_disabled = 1 THEN N'ALTER LOGIN ' + QUOTENAME(sp.name) + N' DISABLE;' + @crlf ELSE N'' END
END + @crlf
FROM sys.server_principals sp
LEFT JOIN sys.sql_logins sl
    ON sp.principal_id = sl.principal_id
WHERE sp.type IN ('S','U','G')
  AND sp.name NOT LIKE N'##MS_%##'
  AND sp.name NOT IN (N'sa')
ORDER BY sp.name;

SELECT @sql;
"@

Write-ScriptFile `
    -Path (Join-Path $OutDir "01_Logins\create_logins.sql") `
    -Lines @($loginScript)

# ---------------------------------------------------------------------
# 02 Server Roles and Memberships
# ---------------------------------------------------------------------

$serverRoleScript = Invoke-ScalarText @"
DECLARE @crlf nchar(2) = NCHAR(13) + NCHAR(10);
DECLARE @sql nvarchar(max) = N'';

SELECT @sql +=
    CASE 
        WHEN is_fixed_role = 0 THEN
            N'IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N''' + REPLACE(name,'''','''''') + N''')' + @crlf +
            N'    CREATE SERVER ROLE ' + QUOTENAME(name) + N';' + @crlf
        ELSE N''
    END
FROM sys.server_principals
WHERE type = 'R'
ORDER BY name;

SELECT @sql +=
    N'ALTER SERVER ROLE ' + QUOTENAME(r.name) + N' ADD MEMBER ' + QUOTENAME(m.name) + N';' + @crlf
FROM sys.server_role_members rm
JOIN sys.server_principals r
    ON rm.role_principal_id = r.principal_id
JOIN sys.server_principals m
    ON rm.member_principal_id = m.principal_id
WHERE m.name NOT LIKE N'##MS_%##'
ORDER BY r.name, m.name;

SELECT @sql;
"@

Write-ScriptFile `
    -Path (Join-Path $OutDir "02_ServerRoles\server_roles_and_members.sql") `
    -Lines @($serverRoleScript)

# ---------------------------------------------------------------------
# 03 Linked Servers
# Passwords for linked server mappings cannot be recovered.
# ---------------------------------------------------------------------

$linkScript = Invoke-ScalarText @"
DECLARE @crlf nchar(2) = NCHAR(13) + NCHAR(10);
DECLARE @sql nvarchar(max) = N'';

SELECT @sql +=
N'EXEC master.dbo.sp_addlinkedserver ' +
N'@server = N''' + REPLACE(name,'''','''''') + N''', ' +
N'@srvproduct = N''' + REPLACE(COALESCE(product,N''),'''','''''') + N''', ' +
N'@provider = N''' + REPLACE(COALESCE(provider,N''),'''','''''') + N''', ' +
N'@datasrc = N''' + REPLACE(COALESCE(data_source,N''),'''','''''') + N''';' + @crlf +
N'EXEC master.dbo.sp_serveroption @server=N''' + REPLACE(name,'''','''''') + N''', @optname=N''collation compatible'', @optvalue=N''' + CASE WHEN is_collation_compatible=1 THEN N'true' ELSE N'false' END + N''';' + @crlf +
N'EXEC master.dbo.sp_serveroption @server=N''' + REPLACE(name,'''','''''') + N''', @optname=N''data access'', @optvalue=N''' + CASE WHEN is_data_access_enabled=1 THEN N'true' ELSE N'false' END + N''';' + @crlf +
N'EXEC master.dbo.sp_serveroption @server=N''' + REPLACE(name,'''','''''') + N''', @optname=N''rpc'', @optvalue=N''' + CASE WHEN is_rpc_enabled=1 THEN N'true' ELSE N'false' END + N''';' + @crlf +
N'EXEC master.dbo.sp_serveroption @server=N''' + REPLACE(name,'''','''''') + N''', @optname=N''rpc out'', @optvalue=N''' + CASE WHEN is_rpc_out_enabled=1 THEN N'true' ELSE N'false' END + N''';' + @crlf +
N'EXEC master.dbo.sp_serveroption @server=N''' + REPLACE(name,'''','''''') + N''', @optname=N''use remote collation'', @optvalue=N''' + CASE WHEN uses_remote_collation=1 THEN N'true' ELSE N'false' END + N''';' + @crlf +
@crlf
FROM sys.servers
WHERE is_linked = 1
ORDER BY name;

SELECT @sql;
"@

Write-ScriptFile `
    -Path (Join-Path $OutDir "03_LinkedServers\linked_servers.sql") `
    -Lines @(
        "-- WARNING: linked server remote passwords cannot be extracted.",
        "-- Re-enter passwords manually after rebuild where needed.",
        $linkScript
    )

Invoke-Query "
SELECT s.name AS linked_server_name,
       ll.local_principal_id,
       sp.name AS local_principal_name,
       ll.uses_self_credential,
       ll.remote_name
FROM sys.linked_logins ll
JOIN sys.servers s
    ON ll.server_id = s.server_id
LEFT JOIN sys.server_principals sp
    ON ll.local_principal_id = sp.principal_id
ORDER BY s.name, sp.name;
" | Export-Csv (Join-Path $OutDir "03_LinkedServers\linked_server_login_mappings_inventory.csv") -NoTypeInformation -Encoding UTF8

# ---------------------------------------------------------------------
# 04 Credentials
# Secrets cannot be recovered.
# ---------------------------------------------------------------------

$credentialScript = Invoke-ScalarText @"
DECLARE @crlf nchar(2) = NCHAR(13) + NCHAR(10);
DECLARE @sql nvarchar(max) = N'';

SELECT @sql +=
N'-- SECRET/PASSWORD MUST BE RE-ENTERED MANUALLY' + @crlf +
N'CREATE CREDENTIAL ' + QUOTENAME(name) +
N' WITH IDENTITY = N''' + REPLACE(credential_identity,'''','''''') + N''', SECRET = N''REPLACE_WITH_SECRET'';' + @crlf + @crlf
FROM sys.credentials
ORDER BY name;

SELECT @sql;
"@

Write-ScriptFile `
    -Path (Join-Path $OutDir "04_Credentials\credentials.sql") `
    -Lines @(
        "-- WARNING: credential secrets cannot be extracted.",
        $credentialScript
    )

# ---------------------------------------------------------------------
# 05 SQL Agent Jobs
# ---------------------------------------------------------------------

foreach ($job in $srv.JobServer.Jobs) {
    if ($job.IsSystemObject -eq $false) {
        $name = Safe-FileName $job.Name
        $path = Join-Path $OutDir "05_SQLAgent_Jobs\$name.sql"
        $script = $job.Script()
        Write-ScriptFile -Path $path -Lines $script
    }
}

# ---------------------------------------------------------------------
# 06 Operators
# ---------------------------------------------------------------------

foreach ($op in $srv.JobServer.Operators) {
    $name = Safe-FileName $op.Name
    $path = Join-Path $OutDir "06_SQLAgent_Operators\$name.sql"
    $script = $op.Script()
    Write-ScriptFile -Path $path -Lines $script
}

# ---------------------------------------------------------------------
# 07 Alerts
# ---------------------------------------------------------------------

foreach ($alert in $srv.JobServer.Alerts) {
    $name = Safe-FileName $alert.Name
    $path = Join-Path $OutDir "07_SQLAgent_Alerts\$name.sql"
    $script = $alert.Script()
    Write-ScriptFile -Path $path -Lines $script
}

# ---------------------------------------------------------------------
# 08 SQL Agent Proxies
# SMO support varies by version. Also export inventory from msdb.
# ---------------------------------------------------------------------

Invoke-Query "
SELECT p.proxy_id,
       p.name AS proxy_name,
       p.credential_id,
       c.name AS credential_name,
       p.enabled,
       p.description
FROM msdb.dbo.sysproxies p
LEFT JOIN sys.credentials c
    ON p.credential_id = c.credential_id
ORDER BY p.name;
" | Export-Csv (Join-Path $OutDir "08_SQLAgent_Proxies\proxies_inventory.csv") -NoTypeInformation -Encoding UTF8

Invoke-Query "
SELECT p.name AS proxy_name,
       s.subsystem
FROM msdb.dbo.sysproxysubsystem ps
JOIN msdb.dbo.sysproxies p
    ON ps.proxy_id = p.proxy_id
JOIN msdb.dbo.syssubsystems s
    ON ps.subsystem_id = s.subsystem_id
ORDER BY p.name, s.subsystem;
" | Export-Csv (Join-Path $OutDir "08_SQLAgent_Proxies\proxy_subsystems_inventory.csv") -NoTypeInformation -Encoding UTF8

Invoke-Query "
SELECT p.name AS proxy_name,
       sp.name AS principal_name
FROM msdb.dbo.sysproxylogin pl
JOIN msdb.dbo.sysproxies p
    ON pl.proxy_id = p.proxy_id
JOIN sys.server_principals sp
    ON pl.sid = sp.sid
ORDER BY p.name, sp.name;
" | Export-Csv (Join-Path $OutDir "08_SQLAgent_Proxies\proxy_principals_inventory.csv") -NoTypeInformation -Encoding UTF8

# ---------------------------------------------------------------------
# 09 Database Mail
# Passwords cannot be recovered.
# ---------------------------------------------------------------------

$dbMailScript = Invoke-ScalarText @"
DECLARE @crlf nchar(2) = NCHAR(13) + NCHAR(10);
DECLARE @sql nvarchar(max) = N'';

SELECT @sql +=
N'EXEC msdb.dbo.sysmail_add_profile_sp @profile_name = N''' + REPLACE(name,'''','''''') + N''', @description = N''' + REPLACE(COALESCE(description,N''),'''','''''') + N''';' + @crlf
FROM msdb.dbo.sysmail_profile
ORDER BY name;

SELECT @sql += @crlf;

SELECT @sql +=
N'-- PASSWORD MUST BE RE-ENTERED MANUALLY IF REQUIRED' + @crlf +
N'EXEC msdb.dbo.sysmail_add_account_sp ' +
N'@account_name = N''' + REPLACE(a.name,'''','''''') + N''', ' +
N'@description = N''' + REPLACE(COALESCE(a.description,N''),'''','''''') + N''', ' +
N'@email_address = N''' + REPLACE(COALESCE(a.email_address,N''),'''','''''') + N''', ' +
N'@display_name = N''' + REPLACE(COALESCE(a.display_name,N''),'''','''''') + N''', ' +
N'@replyto_address = N''' + REPLACE(COALESCE(a.replyto_address,N''),'''','''''') + N''', ' +
N'@mailserver_name = N''' + REPLACE(COALESCE(s.servername,N''),'''','''''') + N''', ' +
N'@port = ' + CONVERT(nvarchar(20), COALESCE(s.port,25)) + N', ' +
N'@enable_ssl = ' + CONVERT(nvarchar(1), COALESCE(s.enable_ssl,0)) + N';' + @crlf + @crlf
FROM msdb.dbo.sysmail_account a
LEFT JOIN msdb.dbo.sysmail_server s
    ON a.account_id = s.account_id
ORDER BY a.name;

SELECT @sql +=
N'EXEC msdb.dbo.sysmail_add_profileaccount_sp @profile_name = N''' + REPLACE(p.name,'''','''''') + N''', @account_name = N''' + REPLACE(a.name,'''','''''') + N''', @sequence_number = ' + CONVERT(nvarchar(20), pa.sequence_number) + N';' + @crlf
FROM msdb.dbo.sysmail_profileaccount pa
JOIN msdb.dbo.sysmail_profile p
    ON pa.profile_id = p.profile_id
JOIN msdb.dbo.sysmail_account a
    ON pa.account_id = a.account_id
ORDER BY p.name, pa.sequence_number;

SELECT @sql;
"@

Write-ScriptFile `
    -Path (Join-Path $OutDir "09_DatabaseMail\database_mail.sql") `
    -Lines @(
        "-- WARNING: Database Mail passwords cannot be extracted.",
        $dbMailScript
    )

Invoke-Query "
SELECT *
FROM msdb.dbo.sysmail_configuration
ORDER BY paramname;
" | Export-Csv (Join-Path $OutDir "09_DatabaseMail\database_mail_configuration.csv") -NoTypeInformation -Encoding UTF8

# ---------------------------------------------------------------------
# 10 SSIS packages stored in msdb
# SQL Server 2017 may use SSISDB catalog, file system, or msdb legacy store.
# This exports inventory. Package binary extraction is not handled here.
# ---------------------------------------------------------------------

Invoke-Query "
IF OBJECT_ID('msdb.dbo.sysssispackages') IS NOT NULL
BEGIN
    SELECT p.name AS package_name,
           p.id,
           p.description,
           p.createdate,
           p.folderid,
           f.foldername,
           p.ownersid
    FROM msdb.dbo.sysssispackages p
    LEFT JOIN msdb.dbo.sysssispackagefolders f
        ON p.folderid = f.folderid
    ORDER BY f.foldername, p.name;
END
" | Export-Csv (Join-Path $OutDir "10_SSIS_msdb\ssis_msdb_packages_inventory.csv") -NoTypeInformation -Encoding UTF8

Invoke-Query "
IF DB_ID('SSISDB') IS NOT NULL
BEGIN
    SELECT name, create_date, compatibility_level, state_desc
    FROM sys.databases
    WHERE name = 'SSISDB';
END
" | Export-Csv (Join-Path $OutDir "10_SSIS_msdb\ssisdb_database_inventory.csv") -NoTypeInformation -Encoding UTF8

# ---------------------------------------------------------------------
# 11 Endpoints
# ---------------------------------------------------------------------

foreach ($ep in $srv.Endpoints) {
    if ($ep.IsSystemObject -eq $false) {
        $name = Safe-FileName $ep.Name
        $path = Join-Path $OutDir "11_Endpoints\$name.sql"
        $script = $ep.Script()
        Write-ScriptFile -Path $path -Lines $script
    }
}

Invoke-Query "
SELECT *
FROM sys.endpoints
ORDER BY name;
" | Export-Csv (Join-Path $OutDir "11_Endpoints\endpoints_inventory.csv") -NoTypeInformation -Encoding UTF8

# ---------------------------------------------------------------------
# 12 Certificates / Keys
# Private keys cannot be scripted by SELECT.
# BACKUP CERTIFICATE WITH PRIVATE KEY must be executed manually with password.
# ---------------------------------------------------------------------

$certScript = Invoke-ScalarText @"
DECLARE @crlf nchar(2) = NCHAR(13) + NCHAR(10);
DECLARE @sql nvarchar(max) = N'';

SELECT @sql +=
N'-- Certificate found: ' + QUOTENAME(c.name) + @crlf +
N'-- Subject: ' + COALESCE(c.subject,N'') + @crlf +
N'-- Expiry: ' + CONVERT(nvarchar(30), c.expiry_date, 120) + @crlf +
N'-- If private key is required, run BACKUP CERTIFICATE manually before rebuild.' + @crlf +
N'-- BACKUP CERTIFICATE ' + QUOTENAME(c.name) + N' TO FILE = ''C:\Backup\' + REPLACE(c.name,'''','') + N'.cer'' WITH PRIVATE KEY (FILE = ''C:\Backup\' + REPLACE(c.name,'''','') + N'.pvk'', ENCRYPTION BY PASSWORD = ''StrongPasswordHere'');' + @crlf + @crlf
FROM sys.certificates c
WHERE c.name NOT LIKE N'##%'
ORDER BY c.name;

SELECT @sql;
"@

Write-ScriptFile `
    -Path (Join-Path $OutDir "12_Certificates_Keys\certificates_backup_commands_template.sql") `
    -Lines @(
        "-- WARNING: certificate private keys are not exported by this script.",
        "-- Review and run BACKUP CERTIFICATE commands manually where needed.",
        $certScript
    )

Invoke-Query "
SELECT name,
       certificate_id,
       principal_id,
       pvt_key_encryption_type_desc,
       issuer_name,
       subject,
       start_date,
       expiry_date,
       thumbprint
FROM sys.certificates
ORDER BY name;
" | Export-Csv (Join-Path $OutDir "12_Certificates_Keys\certificates_inventory.csv") -NoTypeInformation -Encoding UTF8

Invoke-Query "
SELECT name,
       symmetric_key_id,
       principal_id,
       algorithm_desc,
       key_length,
       key_guid,
       create_date,
       modify_date
FROM sys.symmetric_keys
ORDER BY name;
" | Export-Csv (Join-Path $OutDir "12_Certificates_Keys\symmetric_keys_inventory.csv") -NoTypeInformation -Encoding UTF8

Invoke-Query "
SELECT name,
       asymmetric_key_id,
       principal_id,
       algorithm_desc,
       key_length,
       pvt_key_encryption_type_desc,
       thumbprint
FROM sys.asymmetric_keys
ORDER BY name;
" | Export-Csv (Join-Path $OutDir "12_Certificates_Keys\asymmetric_keys_inventory.csv") -NoTypeInformation -Encoding UTF8

# ---------------------------------------------------------------------
# Final notes
# ---------------------------------------------------------------------

$notes = @"
EXPORT COMPLETED: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

Server instance:
$ServerInstance

Output:
$OutDir

IMPORTANT LIMITATIONS:
1. Credential secrets cannot be extracted.
2. Linked server remote passwords cannot be extracted.
3. Database Mail SMTP passwords cannot be extracted.
4. Certificate private keys are not exported automatically.
5. SSIS packages in msdb are inventoried only; export packages separately if used.
6. SQL Agent proxies depend on credentials; credential secrets must be re-entered.
7. After rebuilding system databases, reapply the SQL Server CU/security update manually.
8. Do not restore old model/msdb/master backups unless their collation is Greek_CI_AS.

Recommended manual exports:
- Backup certificates with private keys.
- Export SSIS packages from SSMS/SSDT if stored in msdb.
- Script SQL Agent jobs from SSMS as a second validation.
- Save SQL Server Configuration Manager service account/startup parameter screenshots.
"@

[System.IO.File]::WriteAllText((Join-Path $OutDir "README_EXPORT_LIMITATIONS.txt"), $notes, [System.Text.Encoding]::UTF8)

Write-Host ""
Write-Host "Export completed."
Write-Host "Folder: $OutDir"
Write-Host ""
Write-Host "Review README_EXPORT_LIMITATIONS.txt before rebuilding system databases."