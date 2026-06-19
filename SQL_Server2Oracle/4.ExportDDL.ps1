# ============================================================
# SQL Server -> Oracle Migration: DDL Export
# Uses built-in .NET SqlClient - no sqlcmd needed
# Exports one .sql file per table to .\exportDDL
# ============================================================

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------
$SS_SERVER   = "YOUR_SERVER\INSTANCE"
$SS_DATABASE = "YOUR_DATABASE"
$SS_USER     = "YOUR_USERNAME"
$SS_PASSWORD = "YOUR_PASSWORD"
$ORA_SCHEMA  = "YOUR_ORACLE_SCHEMA"

$SCRIPT_DIR  = Split-Path -Parent $MyInvocation.MyCommand.Path
$OUT_DIR     = Join-Path $SCRIPT_DIR "exportDDL"
$LOG_FILE    = Join-Path $OUT_DIR "_ddl_export_log.txt"

# ------------------------------------------------------------
# Invariant culture - critical on el-GR locale
# ------------------------------------------------------------
[System.Threading.Thread]::CurrentThread.CurrentCulture   `
    = [System.Globalization.CultureInfo]::InvariantCulture
[System.Threading.Thread]::CurrentThread.CurrentUICulture `
    = [System.Globalization.CultureInfo]::InvariantCulture

# ------------------------------------------------------------
# Logging
# ------------------------------------------------------------
function Write-Log {
    param(
        [string]$msg,
        [ValidateSet("INFO","OK","WARN","ERROR","STEP","DEBUG")]
        [string]$level = "INFO"
    )
    $ts    = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
    $line  = "[$ts] [$($level.PadRight(5))] $msg"
    $color = switch ($level) {
        "OK"    { "Green"  }
        "WARN"  { "Yellow" }
        "ERROR" { "Red"    }
        "STEP"  { "Cyan"   }
        "DEBUG" { "Gray"   }
        default { "White"  }
    }
    Write-Host $line -ForegroundColor $color
    Add-Content -Path $LOG_FILE -Value $line
}

function Write-Step    { param([string]$m) Write-Log "--- $m ---" "STEP"  }
function Write-Success { param([string]$m) Write-Log $m "OK"               }
function Write-Warn    { param([string]$m) Write-Log $m "WARN"             }
function Write-Err     { param([string]$m) Write-Log $m "ERROR"            }

# ------------------------------------------------------------
# Output directory
# ------------------------------------------------------------
if (-not (Test-Path $OUT_DIR)) {
    New-Item -ItemType Directory -Path $OUT_DIR -Force | Out-Null
}

# ------------------------------------------------------------
# Connection string
# ------------------------------------------------------------
$connStr = "Server=$SS_SERVER;" +
           "Database=$SS_DATABASE;" +
           "User Id=$SS_USER;" +
           "Password=$SS_PASSWORD;" +
           "Connection Timeout=30;" +
           "Encrypt=False;"

# ============================================================
# STEP 0: Startup
# ============================================================
Write-Step "STEP 0 - STARTUP"
Write-Log "Script dir   : $SCRIPT_DIR"
Write-Log "Output dir   : $OUT_DIR"
Write-Log "Server       : $SS_SERVER"
Write-Log "Database     : $SS_DATABASE"
Write-Log "Oracle schema: $ORA_SCHEMA"

# ============================================================
# STEP 1: Test connection
# ============================================================
Write-Step "STEP 1 - Test connection"
try {
    $testConn = New-Object System.Data.SqlClient.SqlConnection($connStr)
    $testConn.Open()
    Write-Success "Connected - server: $($testConn.ServerVersion)  db: $($testConn.Database)"

    $cmdSmoke = $testConn.CreateCommand()
    $cmdSmoke.CommandText = "SELECT DB_NAME() AS db, SUSER_NAME() AS usr, " +
                            "CAST(GETDATE() AS VARCHAR(30)) AS srv_time"
    $rdr = $cmdSmoke.ExecuteReader()
    if ($rdr.Read()) {
        Write-Log "  DB   : $($rdr['db'])"
        Write-Log "  User : $($rdr['usr'])"
        Write-Log "  Time : $($rdr['srv_time'])"
    }
    $rdr.Close()
    $testConn.Close()
    Write-Success "Connection test passed"
}
catch [System.Data.SqlClient.SqlException] {
    Write-Err "SQL connection failed - error $($_.Exception.Number): $($_.Exception.Message)"
    exit 1
}
catch {
    Write-Err "Connection failed: $($_.Exception.Message)"
    exit 1
}

# ============================================================
# STEP 2: Get table list from MIGRATION_EXPORT_LIST
# ============================================================
Write-Step "STEP 2 - Load table list"

$tableMeta = $null
try {
    $connList = New-Object System.Data.SqlClient.SqlConnection($connStr)
    $connList.Open()
    $cmdList  = $connList.CreateCommand()
    $cmdList.CommandText =
        "SELECT schema_name, table_name " +
        "FROM dbo.MIGRATION_EXPORT_LIST " +
        "WHERE severity_level <> 1 " +
        "ORDER BY export_order"
    $adapter   = New-Object System.Data.SqlClient.SqlDataAdapter($cmdList)
    $tableMeta = New-Object System.Data.DataTable
    $adapter.Fill($tableMeta) | Out-Null
    $connList.Close()
    Write-Success "Table list loaded - $($tableMeta.Rows.Count) tables"
}
catch {
    Write-Err "Failed to load table list: $($_.Exception.Message)"
    exit 1
}

if ($tableMeta.Rows.Count -eq 0) {
    Write-Warn "No tables found in MIGRATION_EXPORT_LIST."
    exit 0
}

# ============================================================
# STEP 3: DDL query template
# ============================================================
# Built as a function so schema/table name are substituted cleanly
function Get-OracleDDL {
    param(
        [string]$schemaName,
        [string]$tableName,
        [System.Data.SqlClient.SqlConnection]$conn
    )

    $sql = "SET NOCOUNT ON; " +
    "WITH col_map AS ( " +
        "SELECT " +
            "c.name AS column_name, " +
            "c.column_id AS col_position, " +
            "c.is_nullable, " +
            "CASE tp.name " +
                "WHEN 'int'              THEN 'NUMBER(10)' " +
                "WHEN 'bigint'           THEN 'NUMBER(19)' " +
                "WHEN 'smallint'         THEN 'NUMBER(5)' " +
                "WHEN 'tinyint'          THEN 'NUMBER(3)' " +
                "WHEN 'bit'              THEN 'NUMBER(1)' " +
                "WHEN 'decimal'          THEN 'NUMBER(' + CAST(c.precision AS VARCHAR) + ',' + CAST(c.scale AS VARCHAR) + ')' " +
                "WHEN 'numeric'          THEN 'NUMBER(' + CAST(c.precision AS VARCHAR) + ',' + CAST(c.scale AS VARCHAR) + ')' " +
                "WHEN 'money'            THEN 'NUMBER(19,4)' " +
                "WHEN 'smallmoney'       THEN 'NUMBER(10,4)' " +
                "WHEN 'float'            THEN 'BINARY_DOUBLE' " +
                "WHEN 'real'             THEN 'BINARY_FLOAT' " +
                "WHEN 'char'             THEN 'CHAR(' + CAST(c.max_length AS VARCHAR) + ')' " +
                "WHEN 'varchar'          THEN CASE WHEN c.max_length = -1 THEN 'CLOB' ELSE 'VARCHAR2(' + CAST(c.max_length AS VARCHAR) + ')' END " +
                "WHEN 'nchar'            THEN 'NCHAR(' + CAST(c.max_length/2 AS VARCHAR) + ')' " +
                "WHEN 'nvarchar'         THEN CASE WHEN c.max_length = -1 THEN 'NCLOB' ELSE 'NVARCHAR2(' + CAST(c.max_length/2 AS VARCHAR) + ')' END " +
                "WHEN 'text'             THEN 'CLOB' " +
                "WHEN 'ntext'            THEN 'NCLOB' " +
                "WHEN 'date'             THEN 'DATE' " +
                "WHEN 'datetime'         THEN 'DATE' " +
                "WHEN 'smalldatetime'    THEN 'DATE' " +
                "WHEN 'datetime2'        THEN 'TIMESTAMP(' + CAST(c.scale AS VARCHAR) + ')' " +
                "WHEN 'datetimeoffset'   THEN 'TIMESTAMP(' + CAST(c.scale AS VARCHAR) + ') WITH TIME ZONE' " +
                "WHEN 'time'             THEN 'INTERVAL DAY(0) TO SECOND(' + CAST(c.scale AS VARCHAR) + ')' " +
                "WHEN 'binary'           THEN 'RAW(' + CAST(c.max_length AS VARCHAR) + ')' " +
                "WHEN 'varbinary'        THEN CASE WHEN c.max_length = -1 THEN 'BLOB' ELSE 'RAW(' + CAST(c.max_length AS VARCHAR) + ')' END " +
                "WHEN 'image'            THEN 'BLOB' " +
                "WHEN 'timestamp'        THEN 'RAW(8)' " +
                "WHEN 'uniqueidentifier' THEN 'RAW(16)' " +
                "WHEN 'xml'              THEN 'XMLTYPE' " +
                "WHEN 'sql_variant'      THEN '/* UNSUPPORTED: sql_variant */' " +
                "WHEN 'hierarchyid'      THEN '/* UNSUPPORTED: hierarchyid */' " +
                "WHEN 'geography'        THEN '/* UNSUPPORTED: geography */' " +
                "WHEN 'geometry'         THEN '/* UNSUPPORTED: geometry */' " +
                "ELSE '/* UNKNOWN: ' + tp.name + ' */' " +
            "END AS oracle_type, " +
            "CASE tp.name " +
                "WHEN 'datetime'         THEN ' /* datetime->DATE: sub-second precision lost */' " +
                "WHEN 'smalldatetime'    THEN ' /* smalldatetime->DATE: seconds lost */' " +
                "WHEN 'bit'              THEN ' /* bit->NUMBER(1): 0 or 1 only */' " +
                "WHEN 'timestamp'        THEN ' /* SS rowversion->RAW(8): not a datetime */' " +
                "WHEN 'uniqueidentifier' THEN ' /* GUID->RAW(16): use HEXTORAW() on load */' " +
                "WHEN 'float'            THEN ' /* float->BINARY_DOUBLE: precision may differ */' " +
                "WHEN 'real'             THEN ' /* real->BINARY_FLOAT: precision may differ */' " +
                "ELSE '' " +
            "END AS conversion_note, " +
            "CASE WHEN ic.object_id IS NOT NULL THEN 1 ELSE 0 END AS is_identity, " +
            "ISNULL(ic.seed_value, 1)      AS identity_seed, " +
            "ISNULL(ic.increment_value, 1) AS identity_increment " +
        "FROM sys.tables t " +
        "JOIN sys.schemas s   ON s.schema_id     = t.schema_id " +
        "JOIN sys.columns c   ON c.object_id     = t.object_id " +
        "JOIN sys.types   tp  ON tp.user_type_id = c.user_type_id " +
        "LEFT JOIN sys.identity_columns ic " +
                             "ON ic.object_id = c.object_id " +
                            "AND ic.column_id = c.column_id " +
        "WHERE t.is_ms_shipped = 0 " +
        "AND t.type = 'U' " +
        "AND s.name = '" + $schemaName + "' " +
        "AND t.name = '" + $tableName  + "' " +
    "), " +
    "pk_cols AS ( " +
        "SELECT STRING_AGG(c.name, ', ') WITHIN GROUP (ORDER BY ic.key_ordinal) AS pk_columns " +
        "FROM sys.tables t " +
        "JOIN sys.schemas s   ON s.schema_id  = t.schema_id " +
        "JOIN sys.indexes ix  ON ix.object_id = t.object_id AND ix.is_primary_key = 1 " +
        "JOIN sys.index_columns ic ON ic.object_id = ix.object_id AND ic.index_id = ix.index_id " +
        "JOIN sys.columns c   ON c.object_id  = ic.object_id AND c.column_id = ic.column_id " +
        "WHERE s.name = '" + $schemaName + "' " +
        "AND t.name   = '" + $tableName  + "' " +
    "), " +
    "col_lines AS ( " +
        "SELECT col_position, " +
            "'    ' + UPPER(column_name) + ' ' + oracle_type " +
            "+ CASE WHEN is_identity = 1 " +
                "THEN ' GENERATED BY DEFAULT AS IDENTITY (START WITH ' " +
                    "+ CAST(identity_seed AS VARCHAR) " +
                    "+ ' INCREMENT BY ' " +
                    "+ CAST(identity_increment AS VARCHAR) + ')' " +
                "ELSE '' END " +
            "+ CASE WHEN is_nullable = 0 THEN ' NOT NULL' ELSE '' END " +
            "+ conversion_note AS col_def " +
        "FROM col_map " +
    "), " +
    "col_block AS ( " +
        "SELECT STRING_AGG(col_def, ',' + CHAR(10)) " +
               "WITHIN GROUP (ORDER BY col_position) AS columns_block " +
        "FROM col_lines " +
    ") " +
    "SELECT " +
        "'-- ----------------------------------------' + CHAR(10) " +
        "+ '-- Source : " + $schemaName + "." + $tableName + "' + CHAR(10) " +
        "+ '-- Target : " + $ORA_SCHEMA.ToUpper() + "." + $tableName.ToUpper() + "' + CHAR(10) " +
        "+ '-- Generated: ' + CONVERT(VARCHAR, GETDATE(), 120) + CHAR(10) " +
        "+ '-- ----------------------------------------' + CHAR(10) " +
        "+ 'CREATE TABLE " + $ORA_SCHEMA.ToUpper() + "." + $tableName.ToUpper() + "' + CHAR(10) " +
        "+ '(' + CHAR(10) " +
        "+ cb.columns_block " +
        "+ CASE WHEN pk.pk_columns IS NOT NULL " +
            "THEN ',' + CHAR(10) + '    CONSTRAINT PK_" + $tableName.ToUpper() + " PRIMARY KEY (' + UPPER(pk.pk_columns) + ')' " +
            "ELSE '' END " +
        "+ CHAR(10) + ');' + CHAR(10) " +
    "FROM col_block cb CROSS JOIN pk_cols pk;"

    $cmd = $conn.CreateCommand()
    $cmd.CommandText    = $sql
    $cmd.CommandTimeout = 120
    $rdr = $cmd.ExecuteReader()
    $ddl = ""
    if ($rdr.Read()) {
        $ddl = $rdr.GetValue(0).ToString()
    }
    $rdr.Close()
    return $ddl
}

# ============================================================
# STEP 4: Export DDL per table
# ============================================================
Write-Step "STEP 4 - Export DDL files"

$successCount = 0
$failCount    = 0
$failList     = @()
$idx          = 0
$tableCount   = $tableMeta.Rows.Count

foreach ($row in $tableMeta.Rows) {

    $idx++
    $schemaName = $row["schema_name"].ToString()
    $tableName  = $row["table_name"].ToString()
    $outFile    = Join-Path $OUT_DIR "$tableName.sql"

    Write-Log "[$idx/$tableCount] $schemaName.$tableName -> $outFile"

    try {
        $conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
        $conn.Open()
        Write-Log "  Connection opened"

        $ddl = Get-OracleDDL -schemaName $schemaName -tableName $tableName -conn $conn
        $conn.Close()

        if ([string]::IsNullOrWhiteSpace($ddl)) {
            Write-Warn "  Empty DDL returned - table may have no columns or be unsupported"
            $failCount++
            $failList += "$schemaName.$tableName"
            continue
        }

        # Write the .sql file
        [System.IO.File]::WriteAllText($outFile, $ddl, [System.Text.Encoding]::UTF8)
        Write-Success "  Written: $outFile ($([System.IO.FileInfo]::new($outFile).Length) bytes)"
        $successCount++
    }
    catch {
        Write-Err "  FAILED: $schemaName.$tableName"
        Write-Err "  Exception : $($_.Exception.GetType().FullName)"
        Write-Err "  Message   : $($_.Exception.Message)"
        if ($_.Exception.InnerException) {
            Write-Err "  Inner     : $($_.Exception.InnerException.Message)"
        }
        try { $conn.Close() } catch {}
        $failCount++
        $failList += "$schemaName.$tableName"
    }
}

# ============================================================
# STEP 5: Write master DDL script
# ============================================================
Write-Step "STEP 5 - Write master_ddl.sql"

$masterFile = Join-Path $OUT_DIR "master_ddl.sql"
$master     = [System.Text.StringBuilder]::new()

$master.AppendLine("-- ============================================================") | Out-Null
$master.AppendLine("-- Oracle DDL Master Script")                                      | Out-Null
$master.AppendLine("-- Generated : " + (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))    | Out-Null
$master.AppendLine("-- Source DB : $SS_DATABASE on $SS_SERVER")                        | Out-Null
$master.AppendLine("-- Target    : $ORA_SCHEMA")                                       | Out-Null
$master.AppendLine("-- Run via SQL*Plus:")                                              | Out-Null
$master.AppendLine("--   sqlplus user/pass@tns @master_ddl.sql")                       | Out-Null
$master.AppendLine("-- ============================================================") | Out-Null
$master.AppendLine("")                                                                  | Out-Null

Get-ChildItem -Path $OUT_DIR -Filter "*.sql" |
    Where-Object { $_.Name -ne "master_ddl.sql" } |
    Sort-Object Name |
    ForEach-Object {
        $master.AppendLine("@" + $_.FullName) | Out-Null
    }

[System.IO.File]::WriteAllText(
    $masterFile,
    $master.ToString(),
    [System.Text.Encoding]::UTF8)

Write-Success "Master script written: $masterFile"

# ============================================================
# STEP 6: Summary
# ============================================================
Write-Step "STEP 6 - Summary"
Write-Log "Succeeded  : $successCount"
Write-Log "Failed     : $failCount"
if ($failList.Count -gt 0) {
    Write-Warn "Failed tables: $($failList -join ', ')"
}
Write-Log "Output dir : $OUT_DIR"
Write-Log "Master DDL : $masterFile"
Write-Log "Log file   : $LOG_FILE"
Write-Log ""
Write-Log "To run on Oracle:"
Write-Log "  sqlplus $ORA_SCHEMA/YOUR_PASS@YOUR_TNS @$masterFile"