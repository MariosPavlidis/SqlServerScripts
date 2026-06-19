# ============================================================
# SQL Server -> Oracle Migration: Data Export + CTL Generator
# Uses MIGRATION_COL_PROFILE for accurate sqlldr type mapping
# Exports .dat files and generates .ctl files per table
# ============================================================

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------
$SS_SERVER   = "YOUR_SERVER\INSTANCE"
$SS_DATABASE = "YOUR_DATABASE"
$SS_USER     = "YOUR_USERNAME"
$SS_PASSWORD = "YOUR_PASSWORD"

$ORA_SCHEMA  = "YOUR_ORACLE_SCHEMA"
$ORA_USER    = "YOUR_ORACLE_USER"
$ORA_PASS    = "YOUR_ORACLE_PASSWORD"
$ORA_HOST    = "YOUR_ORACLE_HOST"
$ORA_PORT    = "1521"
$ORA_SERVICE = "YOUR_SERVICE_NAME"

$ORA_EASY    = "$ORA_HOST" + ":" + "$ORA_PORT" + "/" + "$ORA_SERVICE"
$ORA_CONN    = "$ORA_USER/$ORA_PASS@$ORA_EASY"

$BATCH_SIZE  = 10000
$DELIMITER   = "|"
$NULL_MARKER = "<NULL>"
$DATE_FORMAT = "yyyy-MM-dd HH:mm:ss.fff"

# ------------------------------------------------------------
# Paths
# ------------------------------------------------------------
if ($PSScriptRoot -and $PSScriptRoot -ne "") {
    $BASE_DIR = $PSScriptRoot
} else {
    $BASE_DIR = "C:\Users\mpaulidis\Documents\export"
}

$DATA_DIR   = Join-Path $BASE_DIR "exportData"
$CTL_DIR    = Join-Path $BASE_DIR "exportDDL\sqlldr"
$LOG_FILE   = Join-Path $BASE_DIR "exportDDL\sqlldr\_export_log.txt"
$MASTER_BAT = Join-Path $CTL_DIR  "run_all_sqlldr.bat"
$MASTER_SH  = Join-Path $CTL_DIR  "run_all_sqlldr.sh"

foreach ($dir in @($DATA_DIR, $CTL_DIR)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

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
# Connection string
# ------------------------------------------------------------
$connStr = "Server=$SS_SERVER;" +
           "Database=$SS_DATABASE;" +
           "User Id=$SS_USER;" +
           "Password=$SS_PASSWORD;" +
           "Connection Timeout=30;" +
           "Encrypt=False;"

# ------------------------------------------------------------
# Helper: open connection
# ------------------------------------------------------------
function Get-Connection {
    $c = New-Object System.Data.SqlClient.SqlConnection($connStr)
    $c.Open()
    return $c
}

# ------------------------------------------------------------
# Helper: execute non-query
# ------------------------------------------------------------
function Invoke-SqlNonQuery {
    param([string]$sql)
    $c = Get-Connection
    $cmd = $c.CreateCommand()
    $cmd.CommandText    = $sql
    $cmd.CommandTimeout = 60
    $cmd.ExecuteNonQuery() | Out-Null
    $c.Close()
}

# ============================================================
# STEP 0: Startup
# ============================================================
Write-Step "STEP 0 - STARTUP"
Write-Log "BASE_DIR    : $BASE_DIR"
Write-Log "DATA_DIR    : $DATA_DIR"
Write-Log "CTL_DIR     : $CTL_DIR"
Write-Log "Server      : $SS_SERVER"
Write-Log "Database    : $SS_DATABASE"
Write-Log "Oracle conn : $ORA_EASY"
Write-Log "Oracle schema: $ORA_SCHEMA"
Write-Log "Delimiter   : $DELIMITER"
Write-Log "Null marker : $NULL_MARKER"

# ============================================================
# STEP 1: Test connection + smoke test
# ============================================================
Write-Step "STEP 1 - Test SQL Server connection"
try {
    $testConn = Get-Connection
    $cmdSmoke = $testConn.CreateCommand()
    $cmdSmoke.CommandText =
        "SELECT DB_NAME() AS db, SUSER_NAME() AS usr, " +
        "CAST(GETDATE() AS VARCHAR(30)) AS srv_time, " +
        "@@SERVERNAME AS srv"
    $rdr = $cmdSmoke.ExecuteReader()
    if ($rdr.Read()) {
        Write-Success "Connected OK"
        Write-Log "  DB          : $($rdr['db'])"
        Write-Log "  User        : $($rdr['usr'])"
        Write-Log "  Server      : $($rdr['srv'])"
        Write-Log "  Server time : $($rdr['srv_time'])"
    }
    $rdr.Close()

    # Check MIGRATION_EXPORT_LIST exists
    $cmdChk = $testConn.CreateCommand()
    $cmdChk.CommandText =
        "SELECT COUNT(*) AS cnt FROM dbo.MIGRATION_EXPORT_LIST " +
        "WHERE export_status NOT IN ('EXPORTED','VERIFIED','ON_HOLD') " +
        "AND severity_level <> 1"
    $pending = $cmdChk.ExecuteScalar()
    Write-Log "  Pending tables to export: $pending"

    # Check MIGRATION_COL_PROFILE exists
    $cmdPrf = $testConn.CreateCommand()
    $cmdPrf.CommandText =
        "SELECT COUNT(*) FROM dbo.MIGRATION_COL_PROFILE"
    $profCount = $cmdPrf.ExecuteScalar()
    Write-Log "  Col profile rows: $profCount"

    if ($profCount -eq 0) {
        Write-Warn "MIGRATION_COL_PROFILE is empty - CTL files will use static type mapping"
        Write-Warn "Run combined Script 1+2a first for data-driven mapping"
    }

    $testConn.Close()
    Write-Success "Connection test passed"
}
catch [System.Data.SqlClient.SqlException] {
    Write-Err "SQL connection failed - error $($_.Exception.Number): $($_.Exception.Message)"
    exit 1
}
catch {
    Write-Err "Connection failed: $($_.Exception.GetType().FullName)"
    Write-Err "Message: $($_.Exception.Message)"
    if ($_.Exception.InnerException) {
        Write-Err "Inner: $($_.Exception.InnerException.Message)"
    }
    exit 1
}

# ============================================================
# STEP 2: Load table list from MIGRATION_EXPORT_LIST
# ============================================================
Write-Step "STEP 2 - Load table list"
$tableMeta = $null
try {
    $conn = Get-Connection
    $cmd  = $conn.CreateCommand()
    $cmd.CommandText =
    "SELECT " +
    "    mel.schema_name, " +
    "    mel.table_name, " +
    "    mel.full_name, " +
    "    mel.estimated_rows, " +
    "    mel.severity_level, " +
    "    mel.has_identity, " +
    "    mel.columns_lob, " +
    "    mel.export_status, " +
    "    CASE WHEN EXISTS ( " +
    "        SELECT 1 FROM dbo.MIGRATION_COL_PROFILE p " +
    "        WHERE p.schema_name = mel.schema_name " +
    "          AND p.table_name  = mel.table_name " +
    "    ) THEN 1 ELSE 0 END AS is_profiled " +
    "FROM dbo.MIGRATION_EXPORT_LIST mel " +
    "WHERE mel.export_status NOT IN ('EXPORTED','VERIFIED','ON_HOLD') " +
    "  AND mel.severity_level <> 1 " +
    "ORDER BY mel.export_order"
    $adapter   = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
    $tableMeta = New-Object System.Data.DataTable
    $adapter.Fill($tableMeta) | Out-Null
    $conn.Close()
    Write-Success "Loaded $($tableMeta.Rows.Count) tables"

    $profiled   = ($tableMeta.Select("is_profiled = 1")).Count
    $unprofiled = ($tableMeta.Select("is_profiled = 0")).Count
    Write-Log "  Profiled tables   : $profiled"
    Write-Log "  Unprofiled tables : $unprofiled"
    if ($unprofiled -gt 0) {
        Write-Warn "$unprofiled tables have no column profile - CTL will use static mapping"
    }
}
catch {
    Write-Err "Failed to load table list: $($_.Exception.Message)"
    exit 1
}

if ($tableMeta.Rows.Count -eq 0) {
    Write-Warn "No tables to export - check MIGRATION_EXPORT_LIST"
    exit 0
}

# ============================================================
# STEP 3: Load column profiles for all tables at once
#         Avoids one query per column in the loop
# ============================================================
Write-Step "STEP 3 - Load column profiles"
$colProfileMap = @{}   # key: "schema.table.column" -> profile row

try {
    $conn = Get-Connection
    $cmd  = $conn.CreateCommand()
    $cmd.CommandText =
        "SELECT " +
        "    schema_name, table_name, column_name, " +
        "    ss_type, declared_max_length, " +
        "    has_milliseconds, has_unicode, has_time_component, " +
        "    actual_max_length, actual_max_bytes, actual_max_scale, " +
        "    all_values_integer, null_pct, " +
        "    recommended_type, recommendation_note, " +
        "    col_position, is_nullable " +
        "FROM dbo.MIGRATION_COL_PROFILE " +
        "ORDER BY schema_name, table_name, col_position"
    $adapter  = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
    $profData = New-Object System.Data.DataTable
    $adapter.Fill($profData) | Out-Null
    $conn.Close()

    foreach ($prow in $profData.Rows) {
        $key = "$($prow['schema_name']).$($prow['table_name']).$($prow['column_name'])"
        $colProfileMap[$key] = $prow
    }
    Write-Success "Loaded $($profData.Rows.Count) column profiles into memory"
}
catch {
    Write-Warn "Could not load column profiles: $($_.Exception.Message)"
    Write-Warn "Will use static type mapping for all columns"
}

# ============================================================
# STEP 4: Helper - Format field value for export
# ============================================================
function Format-Field {
    param($value, [string]$typeName)

    if ($value -eq [System.DBNull]::Value -or $null -eq $value) {
        return $NULL_MARKER
    }

    if ($typeName -eq "DateTime") {
        return ([datetime]$value).ToString(
            $DATE_FORMAT,
            [System.Globalization.CultureInfo]::InvariantCulture)
    }
    if ($typeName -eq "DateTimeOffset") {
        return ([datetimeoffset]$value).ToString(
            "yyyy-MM-dd HH:mm:ss.fff zzz",
            [System.Globalization.CultureInfo]::InvariantCulture)
    }
    if ($typeName -eq "Decimal") {
        return ([decimal]$value).ToString(
            [System.Globalization.CultureInfo]::InvariantCulture)
    }
    if ($typeName -eq "Double") {
        return ([double]$value).ToString(
            "R",
            [System.Globalization.CultureInfo]::InvariantCulture)
    }
    if ($typeName -eq "Single") {
        return ([float]$value).ToString(
            "R",
            [System.Globalization.CultureInfo]::InvariantCulture)
    }
    if ($typeName -eq "Boolean") {
        if ($value) { return "1" } else { return "0" }
    }
    if ($typeName -eq "Byte[]" -or $typeName -eq "Byte") {
        try {
            return [System.BitConverter]::ToString([byte[]]$value).Replace("-","")
        } catch { return $NULL_MARKER }
    }
    if ($typeName -eq "Guid") {
        return $value.ToString("N").ToUpper()
    }
    if ($typeName -eq "Int16" -or
        $typeName -eq "Int32" -or
        $typeName -eq "Int64") {
        return $value.ToString(
            [System.Globalization.CultureInfo]::InvariantCulture)
    }

    # String - escape delimiter and flatten newlines
    $str = $value.ToString()
    $str = $str.Replace($DELIMITER, "\$DELIMITER")
    $str = $str.Replace("`r`n"," ").Replace("`n"," ").Replace("`r"," ")
    return $str
}

# ============================================================
# STEP 5: Helper - Build CTL column definition
#         Uses profile data where available, static otherwise
# ============================================================
function Get-CtlColDef {
    param(
        [string]$schemaName,
        [string]$tableName,
        [string]$colName,
        [string]$dotNetType,
        [bool]$isIdentity,
        [int]$sqlMaxLength
    )

    $nm      = "NULLIF ${colName}='$NULL_MARKER'"
    $profKey = "$schemaName.$tableName.$($colName.ToUpper())"

    # Try lowercase column name too (profile stores original case)
    $profile = $null
    if ($colProfileMap.ContainsKey($profKey)) {
        $profile = $colProfileMap[$profKey]
    } else {
        # Try case-insensitive search
        $matchKey = $colProfileMap.Keys |
            Where-Object { $_ -ieq $profKey } |
            Select-Object -First 1
        if ($matchKey) { $profile = $colProfileMap[$matchKey] }
    }

    # Identity columns - always FILLER
    if ($isIdentity) {
        return "    $colName FILLER  -- identity: Oracle generates value"
    }

    # --------------------------------------------------------
    # Profile-driven mapping
    # --------------------------------------------------------
    if ($profile -ne $null) {
        $recType = $profile["recommended_type"].ToString()
        $ssType  = $profile["ss_type"].ToString()
        $note    = if ($profile["recommendation_note"] -ne [System.DBNull]::Value) {
                       $profile["recommendation_note"].ToString()
                   } else { "" }

        $noteStr = if ($note -ne "") { "  -- [P] $note" } else { "" }

        # Date/time types
        if ($recType -eq "DATE") {
            if ($ssType -eq "date") {
                return "    $colName DATE 'YYYY-MM-DD' $nm$noteStr"
            }
            return "    $colName DATE 'YYYY-MM-DD HH24:MI:SS' $nm$noteStr"
        }
        if ($recType -like "TIMESTAMP(3)*" -and $recType -notlike "*TIME ZONE*") {
            return "    $colName TIMESTAMP 'YYYY-MM-DD HH24:MI:SS.FF3' $nm$noteStr"
        }
        if ($recType -like "TIMESTAMP*" -and $recType -like "*TIME ZONE*") {
            return "    $colName TIMESTAMP WITH TIME ZONE " +
                   "'YYYY-MM-DD HH24:MI:SS.FF3 TZH:TZM' $nm$noteStr"
        }
        if ($recType -like "TIMESTAMP*") {
            return "    $colName TIMESTAMP 'YYYY-MM-DD HH24:MI:SS.FF3' $nm$noteStr"
        }
        if ($recType -like "INTERVAL*") {
            return "    $colName INTERVAL DAY(0) TO SECOND(3) $nm$noteStr"
        }
        if ($recType -like "NUMBER*") {
            # Check if it has decimal places
            if ($recType -match "NUMBER\(\d+\)$") {
                return "    $colName INTEGER EXTERNAL $nm$noteStr"
            }
            return "    $colName DECIMAL EXTERNAL $nm$noteStr"
        }
        if ($recType -eq "BINARY_DOUBLE") {
            return "    $colName FLOAT EXTERNAL $nm$noteStr"
        }
        if ($recType -eq "BINARY_FLOAT") {
            return "    $colName FLOAT EXTERNAL $nm$noteStr"
        }
        if ($recType -eq "CLOB" -or $recType -eq "NCLOB") {
            return "    $colName CHAR(65534) $nm$noteStr"
        }
        if ($recType -eq "BLOB") {
            return "    $colName CHAR(65534) $nm$noteStr"
        }
        if ($recType -eq "XMLTYPE") {
            return "    $colName CHAR(65534) $nm$noteStr"
        }
if ($recType -eq "RAW(16)") {
    return "    $colName CHAR(32) $nm$noteStr  -- GUID as hex"
}
if ($recType -eq "RAW(8)") {
    return "    $colName CHAR(16) $nm$noteStr  -- rowversion as hex"
}
        if ($recType -like "RAW(*") {
            # Extract size from RAW(n)
            if ($recType -match "RAW\((\d+)\)") {
                $rawSize = [int]$matches[1] * 2
                return "    $colName CHAR($rawSize) $nm$noteStr"
            }
            return "    $colName CHAR(4000) $nm$noteStr"
        }
        if ($recType -like "VARCHAR2(*") {
            if ($recType -match "VARCHAR2\((\d+)\)") {
                $sz = [int]$matches[1]
                return "    $colName CHAR($sz) $nm$noteStr"
            }
        }
        if ($recType -like "NVARCHAR2(*") {
            if ($recType -match "NVARCHAR2\((\d+)\)") {
                $sz = [int]$matches[1]
                return "    $colName CHAR($sz) $nm$noteStr"
            }
        }
        if ($recType -like "CHAR(*") {
            if ($recType -match "CHAR\((\d+)\)") {
                $sz = [int]$matches[1]
                return "    $colName CHAR($sz) $nm$noteStr"
            }
        }
        if ($recType -like "NCHAR(*") {
            if ($recType -match "NCHAR\((\d+)\)") {
                $sz = [int]$matches[1]
                return "    $colName CHAR($sz) $nm$noteStr"
            }
        }

        # Fallback for any other profiled type
        return "    $colName CHAR(4000) $nm  -- profiled: $recType"
    }

    # --------------------------------------------------------
    # Static mapping fallback (no profile available)
    # --------------------------------------------------------
    $staticNote = "  -- [S] not profiled - static mapping"

    if ($dotNetType -eq "DateTime") {
        return "    $colName TIMESTAMP 'YYYY-MM-DD HH24:MI:SS.FF3' $nm$staticNote"
    }
    if ($dotNetType -eq "DateTimeOffset") {
        return "    $colName TIMESTAMP WITH TIME ZONE " +
               "'YYYY-MM-DD HH24:MI:SS.FF3 TZH:TZM' $nm$staticNote"
    }
    if ($dotNetType -eq "Decimal") {
        return "    $colName DECIMAL EXTERNAL $nm$staticNote"
    }
    if ($dotNetType -eq "Double" -or $dotNetType -eq "Single") {
        return "    $colName FLOAT EXTERNAL $nm$staticNote"
    }
    if ($dotNetType -eq "Boolean" -or
        $dotNetType -eq "Int16"   -or
        $dotNetType -eq "Int32"   -or
        $dotNetType -eq "Int64"   -or
        $dotNetType -eq "Byte") {
        return "    $colName INTEGER EXTERNAL $nm$staticNote"
    }
    if ($dotNetType -eq "Byte[]") {
        $hexLen = if ($sqlMaxLength -gt 0) { $sqlMaxLength * 2 } else { 65534 }
        return "    $colName CHAR($hexLen) $nm$staticNote"
    }
    if ($dotNetType -eq "Guid") {
        return "    $colName CHAR(32) $nm$staticNote"
    }

    # String fallback - use declared length
    $strLen = if ($sqlMaxLength -eq -1)     { 65534 }
              elseif ($sqlMaxLength -gt 0)  { $sqlMaxLength * 2 }
              else                          { 4000 }
    return "    $colName CHAR($strLen) $nm$staticNote"
}

# ============================================================
# STEP 6: Helper - Write CTL file
# ============================================================
function Write-CtlFile {
    param(
        [string]$schemaName,
        [string]$tableName,
        [string]$dataFile,
        [System.Data.DataTable]$schemaTable,
        [hashtable]$identityColumns,
        [hashtable]$sqlMaxLengths,
        [bool]$hasLob,
        [long]$estRows
    )

    $ctlFile  = Join-Path $CTL_DIR "$tableName.ctl"
    $badFile  = Join-Path $CTL_DIR "$tableName.bad"
    $discFile = Join-Path $CTL_DIR "$tableName.dsc"
    $loadMode = if ($hasLob) { "CONVENTIONAL" } else { "DIRECT" }

    $ctl = [System.Collections.Generic.List[string]]::new()
    $ctl.Add("-- ============================================")
    $ctl.Add("-- SQL*Loader Control File")
    $ctl.Add("-- Target   : $($ORA_SCHEMA.ToUpper()).$($tableName.ToUpper())")
    $ctl.Add("-- Source   : $schemaName.$tableName")
    $ctl.Add("-- Rows est : $estRows")
    $ctl.Add("-- Mode     : $loadMode")
    $ctl.Add("-- Generated: " + (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
    if ($hasLob) {
        $ctl.Add("-- NOTE     : LOB columns detected - DIRECT=TRUE disabled")
    }
    $ctl.Add("-- ============================================")
    $ctl.Add("OPTIONS (")
    $ctl.Add("    SKIP     = 1,")
    $ctl.Add("    ERRORS   = 1000,")
    $ctl.Add("    ROWS     = 10000,")
    $ctl.Add("    BINDSIZE = 20971520,")
    if ($loadMode -eq "DIRECT") {
        $ctl.Add("    DIRECT   = TRUE,")
    }
    $ctl.Add("    SILENT   = (FEEDBACK)")
    $ctl.Add(")")
    $ctl.Add("LOAD DATA")
    $ctl.Add("CHARACTERSET AL32UTF8")
    $ctl.Add("INFILE '$dataFile'")
    $ctl.Add("BADFILE '$badFile'")
    $ctl.Add("DISCARDFILE '$discFile'")
    $ctl.Add("APPEND")
    $ctl.Add("INTO TABLE $($ORA_SCHEMA.ToUpper()).$($tableName.ToUpper())")
    $ctl.Add("FIELDS TERMINATED BY '$DELIMITER'")
    $ctl.Add('OPTIONALLY ENCLOSED BY ''"''')
    $ctl.Add("TRAILING NULLCOLS")
    $ctl.Add("(")

    $colDefs = [System.Collections.Generic.List[string]]::new()
    foreach ($srow in $schemaTable.Rows) {
        $colName   = $srow["ColumnName"].ToString().ToUpper()
        $dotType   = $srow["DataTypeName"].ToString()
        $colSize   = [int]$srow["ColumnSize"]
        $isIdent   = $identityColumns.ContainsKey($colName.ToLower())
        $maxLen    = if ($sqlMaxLengths.ContainsKey($colName.ToLower())) {
                         $sqlMaxLengths[$colName.ToLower()]
                     } else { $colSize }

        $def = Get-CtlColDef `
                    -schemaName  $schemaName `
                    -tableName   $tableName `
                    -colName     $colName `
                    -dotNetType  $dotType `
                    -isIdentity  $isIdent `
                    -sqlMaxLength $maxLen

        $colDefs.Add($def)
    }

    $ctl.Add($colDefs -join ("," + [System.Environment]::NewLine))
    $ctl.Add(")")

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

[System.IO.File]::WriteAllLines(
    $ctlFile, $ctl, $utf8NoBom)

    return $ctlFile
}

# ============================================================
# STEP 7: Initialize master scripts
# ============================================================
Write-Step "STEP 7 - Initialize master loader scripts"

$shLines  = [System.Collections.Generic.List[string]]::new()
$batLines = [System.Collections.Generic.List[string]]::new()

$shLines.Add("#!/bin/bash")
$shLines.Add("# ============================================")
$shLines.Add("# Oracle SQL*Loader - Run All Tables")
$shLines.Add("# Generated: " + (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
$shLines.Add("# Connection: $ORA_EASY")
$shLines.Add("# ============================================")
$shLines.Add('ORA_CONN="' + $ORA_CONN + '"')
$shLines.Add('LOG_DIR="./sqlldr_logs"')
$shLines.Add('mkdir -p "$LOG_DIR"')
$shLines.Add("SUCCESS=0")
$shLines.Add("FAILED=0")
$shLines.Add("")

$batLines.Add("@ECHO OFF")
$batLines.Add("SETLOCAL ENABLEDELAYEDEXPANSION")
$batLines.Add("REM ============================================")
$batLines.Add("REM Oracle SQL*Loader - Run All Tables")
$batLines.Add("REM Generated: " + (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
$batLines.Add("REM Connection: $ORA_EASY")
$batLines.Add("REM ============================================")
$batLines.Add("SET SQLLDR=C:\Oracle\oracle19c\product\19.0.0\client_1\bin\sqlldr.exe")
$batLines.Add("SET ORA_CONN=$ORA_CONN")
$batLines.Add("SET LOG_DIR=.\sqlldr_logs")
$batLines.Add("IF NOT EXIST %LOG_DIR% MKDIR %LOG_DIR%")
$batLines.Add("SET SUCCESS=0")
$batLines.Add("SET FAILED=0")
$batLines.Add("")

# ============================================================
# STEP 8: Main loop - export data + generate CTL
# ============================================================
Write-Step "STEP 8 - Export tables + generate CTL files"

$successCount = 0
$failCount    = 0
$failList     = @()
$idx          = 0
$tableCount   = $tableMeta.Rows.Count

foreach ($row in $tableMeta.Rows) {

    $idx++
    $schemaName  = $row["schema_name"].ToString()
    $tableName   = $row["table_name"].ToString()
    $fullName    = $row["full_name"].ToString()
    $estRows     = $row["estimated_rows"]
    $hasIdentity = $row["has_identity"].ToString()
    $lobCols     = [int]$row["columns_lob"]
    $isProfiled  = ([int]$row["is_profiled"]) -eq 1

    $dataFile = Join-Path $DATA_DIR "$tableName.dat"
    $errFile  = Join-Path $DATA_DIR "$tableName.err"

    Write-Step "[$idx/$tableCount] $fullName"
    Write-Log "Estimated rows : $estRows"
    Write-Log "LOB columns    : $lobCols"
    Write-Log "Has identity   : $hasIdentity"
    Write-Log "Is profiled    : $isProfiled"
    Write-Log "Data file      : $dataFile"

    # Ensure output directory exists
    $dataDir = [System.IO.Path]::GetDirectoryName($dataFile)
    if (-not (Test-Path $dataDir)) {
        New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    }

    try {
        # Mark IN_PROGRESS
        Write-Log "Marking IN_PROGRESS..."
        $sqlIP =
            "UPDATE dbo.MIGRATION_EXPORT_LIST " +
            "SET export_status = 'IN_PROGRESS', " +
            "export_started_at = SYSUTCDATETIME(), " +
            "updated_at = SYSUTCDATETIME() " +
            "WHERE schema_name = '$schemaName' " +
            "AND table_name = '$tableName'"
        Invoke-SqlNonQuery $sqlIP
        Write-Success "Marked IN_PROGRESS"

        # Get identity columns and max lengths from SQL Server
        Write-Log "Loading column metadata..."
        $connMeta = Get-Connection
        $cmdMeta  = $connMeta.CreateCommand()
        $cmdMeta.CommandText =
            "SELECT " +
            "    LOWER(c.name) AS col_name, " +
            "    c.max_length  AS max_length, " +
            "    CASE WHEN ic.object_id IS NOT NULL THEN 1 ELSE 0 END AS is_identity " +
            "FROM sys.tables   t " +
            "JOIN sys.schemas  s   ON s.schema_id     = t.schema_id " +
            "JOIN sys.columns  c   ON c.object_id     = t.object_id " +
            "JOIN sys.types    tp  ON tp.user_type_id = c.user_type_id " +
            "LEFT JOIN sys.identity_columns ic " +
            "                      ON ic.object_id = c.object_id " +
            "                     AND ic.column_id = c.column_id " +
            "WHERE s.name = '$schemaName' " +
            "AND   t.name = '$tableName' " +
            "AND   t.is_ms_shipped = 0"
        $adpMeta    = New-Object System.Data.SqlClient.SqlDataAdapter($cmdMeta)
        $dtMeta     = New-Object System.Data.DataTable
        $adpMeta.Fill($dtMeta) | Out-Null
        $connMeta.Close()

        $identityCols = @{}
        $sqlMaxLens   = @{}
        foreach ($mrow in $dtMeta.Rows) {
            $cn = $mrow["col_name"].ToString()
            $sqlMaxLens[$cn]   = [int]$mrow["max_length"]
            if ([int]$mrow["is_identity"] -eq 1) {
                $identityCols[$cn] = $true
            }
        }
        Write-Log "  Columns: $($dtMeta.Rows.Count)  Identity cols: $($identityCols.Count)"

        # Open data connection and stream rows
        Write-Log "Opening data connection..."
        $connData = Get-Connection
        Write-Success "Data connection opened (state: $($connData.State))"

        Write-Log "Executing SELECT..."
        $cmdData = $connData.CreateCommand()
        $cmdData.CommandText    = "SELECT * FROM [$schemaName].[$tableName] WITH (NOLOCK)"
        $cmdData.CommandTimeout = 3600

        $reader = $cmdData.ExecuteReader(
                    [System.Data.CommandBehavior]::SequentialAccess)
        Write-Success "Reader opened - $($reader.FieldCount) columns"

        # Get schema table for CTL generation
        $schemaTable = $reader.GetSchemaTable()

        # Get column names and .NET types
        $colNames  = @()
        $typeNames = @()
        for ($i = 0; $i -lt $reader.FieldCount; $i++) {
            $colNames  += $reader.GetName($i)
            $typeNames += $reader.GetFieldType($i).Name
        }
        Write-Log "Columns: $($colNames -join ', ')"

        # Detect LOB columns for CTL mode
        $hasLob = $false
        foreach ($srow in $schemaTable.Rows) {
            $dtn = $srow["DataTypeName"].ToString().ToLower()
            $csz = [int]$srow["ColumnSize"]
            if ($dtn -in @("text","ntext","image","xml") -or
                ($dtn -eq "varbinary" -and $csz -eq -1)) {
                $hasLob = $true
                break
            }
        }
        Write-Log "Has LOB columns: $hasLob"

        # Open output file
        Write-Log "Opening output file..."
        $writer = New-Object System.IO.StreamWriter(
                    $dataFile,
                    $false,
                    [System.Text.Encoding]::UTF8)
        $writer.WriteLine($colNames -join $DELIMITER)
        Write-Success "Output file opened, header written"

        # Stream rows
        $rowCount = 0
        $errCount = 0

        try {
            while ($reader.Read()) {
                try {
                    $fields = @()
                    for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                        $fields += Format-Field $reader.GetValue($i) $typeNames[$i]
                    }
                    $writer.WriteLine($fields -join $DELIMITER)
                    $rowCount++
                    if ($rowCount % $BATCH_SIZE -eq 0) {
                        $writer.Flush()
                        Write-Log "  ... $rowCount rows written" "DEBUG"
                    }
                }
                catch {
                    $errCount++
                    $errLine = "Row $rowCount | $($_.Exception.Message)"
                    Add-Content -Path $errFile -Value $errLine
                    if ($errCount -le 5) {
                        Write-Warn "Row error: $errLine"
                    }
                }
            }
        }
        finally {
            $writer.Flush()
            $writer.Close()
            $writer.Dispose()
            Write-Success "Writer closed"
        }

        try { $reader.Close()   } catch {}
        try { $connData.Close() } catch {}

        Write-Success "Rows written : $rowCount"
        if ($errCount -gt 0) {
            Write-Warn "Row errors   : $errCount (see $errFile)"
        }

        # Generate CTL file
        Write-Log "Writing CTL file..."
        $ctlFile = Write-CtlFile `
                        -schemaName     $schemaName `
                        -tableName      $tableName `
                        -dataFile       $dataFile `
                        -schemaTable    $schemaTable `
                        -identityColumns $identityCols `
                        -sqlMaxLengths  $sqlMaxLens `
                        -hasLob         $hasLob `
                        -estRows        $estRows
        Write-Success "CTL file     : $ctlFile"

        # Add to master scripts
        $shLines.Add("# --- $tableName ---")
        $shLines.Add('echo "Loading ' + $tableName + ' (~' + $estRows + ' rows)..."')
        $shLines.Add("sqlldr " + '$ORA_CONN' + " \")
        $shLines.Add("    control='" + $ctlFile + "' \")
        $shLines.Add("    log='" + '$LOG_DIR' + "/" + $tableName + ".log' \")
        $shLines.Add("    bad='" + '$LOG_DIR' + "/" + $tableName + ".bad' \")
        $shLines.Add("    discard='" + '$LOG_DIR' + "/" + $tableName + ".dsc'")
        $shLines.Add('RC=$?')
        $shLines.Add('if [ $RC -eq 0 ] || [ $RC -eq 2 ]; then')
        $shLines.Add('    echo "  OK: ' + $tableName + '"')
        $shLines.Add('    SUCCESS=$((SUCCESS+1))')
        $shLines.Add('else')
        $shLines.Add('    echo "  FAILED: ' + $tableName + ' (rc=$RC)"')
        $shLines.Add('    FAILED=$((FAILED+1))')
        $shLines.Add('fi')
        $shLines.Add("")

        $batLines.Add("REM --- $tableName ---")
        $batLines.Add("ECHO Loading $tableName (~$estRows rows)...")
        $batLines.Add(
            '"%SQLLDR%" %ORA_CONN%' +
            ' control="' + $ctlFile + '"' +
            ' log="%LOG_DIR%\' + $tableName + '.log"' +
            ' bad="%LOG_DIR%\' + $tableName + '.bad"' +
            ' discard="%LOG_DIR%\' + $tableName + '.dsc"'
        )
        $batLines.Add("IF !ERRORLEVEL! EQU 0 (")
        $batLines.Add("    ECHO   OK: $tableName")
        $batLines.Add("    SET /A SUCCESS+=1")
        $batLines.Add(") ELSE (")
        $batLines.Add("    ECHO   FAILED: $tableName")
        $batLines.Add("    SET /A FAILED+=1")
        $batLines.Add(")")
        $batLines.Add("")

        # Mark EXPORTED
        Write-Log "Marking EXPORTED..."
        $exportNote = "Exported $rowCount rows, $errCount errors."
        $sqlExp =
            "UPDATE dbo.MIGRATION_EXPORT_LIST " +
            "SET export_status = 'EXPORTED', " +
            "export_completed_at = SYSUTCDATETIME(), " +
            "updated_at = SYSUTCDATETIME(), " +
            "notes = ISNULL(notes,'') + ' | $exportNote' " +
            "WHERE schema_name = '$schemaName' " +
            "AND table_name = '$tableName'"
        Invoke-SqlNonQuery $sqlExp
        Write-Success "Marked EXPORTED"

        $successCount++
    }
    catch {
        $errMsg = $_.Exception.Message
        Write-Err "FAILED: $fullName"
        Write-Err "Type   : $($_.Exception.GetType().FullName)"
        Write-Err "Message: $errMsg"
        if ($_.Exception.InnerException) {
            Write-Err "Inner  : $($_.Exception.InnerException.Message)"
        }
        Write-Err "Line   : $($_.ScriptStackTrace)"

        $failList   += $fullName
        $failCount++

        try {
            $safeMsg  = $errMsg -replace "'","''"
            $sqlReset =
                "UPDATE dbo.MIGRATION_EXPORT_LIST " +
                "SET export_status = 'ERROR', " +
                "updated_at = SYSUTCDATETIME(), " +
                "notes = ISNULL(notes,'') + ' | ERROR: $safeMsg' " +
                "WHERE schema_name = '$schemaName' " +
                "AND table_name = '$tableName'"
            Invoke-SqlNonQuery $sqlReset
            Write-Warn "Status set to ERROR"
        } catch {
            Write-Err "Could not update status: $($_.Exception.Message)"
        }
    }
}

# ============================================================
# STEP 9: Finalize master scripts
# ============================================================
Write-Step "STEP 9 - Write master loader scripts"

$shLines.Add("")
$shLines.Add('echo ""')
$shLines.Add('echo "============================================"')
$shLines.Add('echo " SQL*Loader complete"')
$shLines.Add('echo " Succeeded : $SUCCESS"')
$shLines.Add('echo " Failed    : $FAILED"')
$shLines.Add('echo "============================================"')
$shLines.Add('if [ $FAILED -gt 0 ]; then exit 1; fi')

$batLines.Add("ECHO.")
$batLines.Add("ECHO ============================================")
$batLines.Add("ECHO  SQL*Loader complete")
$batLines.Add("ECHO  Succeeded : !SUCCESS!")
$batLines.Add("ECHO  Failed    : !FAILED!")
$batLines.Add("ECHO ============================================")
$batLines.Add("ENDLOCAL")

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

[System.IO.File]::WriteAllLines($MASTER_SH,  $shLines,  $utf8NoBom)
[System.IO.File]::WriteAllLines($MASTER_BAT, $batLines, $utf8NoBom)
Write-Success "Shell script : $MASTER_SH"
Write-Success "Batch script : $MASTER_BAT"

# ============================================================
# STEP 10: Final summary
# ============================================================
Write-Step "STEP 10 - Summary"
Write-Log "Succeeded     : $successCount"
Write-Log "Failed        : $failCount"
if ($failList.Count -gt 0) {
    Write-Warn "Failed tables : $($failList -join ', ')"
}
Write-Log "Data files    : $DATA_DIR\*.dat"
Write-Log "CTL files     : $CTL_DIR\*.ctl"
Write-Log "Shell script  : $MASTER_SH"
Write-Log "Batch script  : $MASTER_BAT"
Write-Log "Log           : $LOG_FILE"
Write-Log ""
Write-Log "Next steps:"
Write-Log "  1. Run DDL  : sqlplus $ORA_USER/***@$ORA_EASY @exportDDL\master_ddl.sql"
Write-Log "  2. Load data: .\exportDDL\sqlldr\run_all_sqlldr.bat"
Write-Log "  3. Check    : exportDDL\sqlldr\sqlldr_logs\*.log"

# Final status from tracking table
try {
    $connFin = Get-Connection
    $cmdFin  = $connFin.CreateCommand()
    $cmdFin.CommandText =
        "SELECT export_status, COUNT(*) AS tables, " +
        "SUM(estimated_rows) AS estimated_rows " +
        "FROM dbo.MIGRATION_EXPORT_LIST " +
        "GROUP BY export_status ORDER BY export_status"
    $adFin = New-Object System.Data.SqlClient.SqlDataAdapter($cmdFin)
    $dtFin = New-Object System.Data.DataTable
    $adFin.Fill($dtFin) | Out-Null
    $connFin.Close()
    Write-Host ""
    Write-Host "MIGRATION_EXPORT_LIST final status:" -ForegroundColor Cyan
    $dtFin | Format-Table -AutoSize
} catch {
    Write-Warn "Could not retrieve final status: $($_.Exception.Message)"
}