@ECHO OFF
SETLOCAL ENABLEDELAYEDEXPANSION

:: ============================================================
:: SQL Server → Oracle Migration: DDL Export
:: Connects via sqlcmd and exports one .sql file per table
:: Output directory: .\exportDDL
:: ============================================================

:: ------------------------------------------------------------
:: Connection variables — edit these before running
:: ------------------------------------------------------------
SET SS_SERVER=YOUR_SERVER\INSTANCE
SET SS_DATABASE=YOUR_DATABASE
SET SS_USER=YOUR_USERNAME
SET SS_PASSWORD=YOUR_PASSWORD

:: ------------------------------------------------------------
:: Output directory
:: ------------------------------------------------------------
SET OUT_DIR=.\exportDDL

IF NOT EXIST "%OUT_DIR%" (
    MKDIR "%OUT_DIR%"
    ECHO Created output directory: %OUT_DIR%
)

:: ------------------------------------------------------------
:: Step 1: Export the table list (schema + table name)
--          into a temp CSV so we can loop over it
:: ------------------------------------------------------------
ECHO.
ECHO [1/3] Retrieving table list from %SS_DATABASE%...

SET TABLE_LIST=%TEMP%\migration_table_list.csv

sqlcmd ^
    -S "%SS_SERVER%" ^
    -d "%SS_DATABASE%" ^
    -U "%SS_USER%" ^
    -P "%SS_PASSWORD%" ^
    -W ^
    -s "," ^
    -h -1 ^
    -Q "SELECT s.name, t.name FROM sys.tables t JOIN sys.schemas s ON s.schema_id = t.schema_id WHERE t.is_ms_shipped = 0 AND t.type = 'U' AND t.name NOT IN ('MIGRATION_LOG','MIGRATION_EXPORT_LIST','MIGRATION_ERRORS') ORDER BY s.name, t.name;" ^
    -o "%TABLE_LIST%"

IF %ERRORLEVEL% NEQ 0 (
    ECHO [ERROR] Failed to retrieve table list. Check connection settings.
    GOTO :EOF
)

:: ------------------------------------------------------------
:: Step 2: Count tables found
:: ------------------------------------------------------------
SET TABLE_COUNT=0
FOR /F "tokens=*" %%L IN (%TABLE_LIST%) DO (
    SET /A TABLE_COUNT+=1
)

ECHO Found %TABLE_COUNT% tables to export.
ECHO.

:: ------------------------------------------------------------
:: Step 3: Loop over each table and export its DDL
:: ------------------------------------------------------------
ECHO [2/3] Exporting DDL files...
ECHO.

SET SUCCESS_COUNT=0
SET FAIL_COUNT=0
SET FAIL_LIST=

FOR /F "tokens=1,2 delims=," %%A IN (%TABLE_LIST%) DO (

    SET SCHEMA_NAME=%%A
    SET TABLE_NAME=%%B

    :: Strip any trailing whitespace/CR sqlcmd may add
    SET SCHEMA_NAME=!SCHEMA_NAME: =!
    SET TABLE_NAME=!TABLE_NAME: =!

    SET OUT_FILE=%OUT_DIR%\!SCHEMA_NAME!.!TABLE_NAME!.sql

    ECHO   Exporting !SCHEMA_NAME!.!TABLE_NAME! ...

    sqlcmd ^
        -S "%SS_SERVER%" ^
        -d "%SS_DATABASE%" ^
        -U "%SS_USER%" ^
        -P "%SS_PASSWORD%" ^
        -W ^
        -h -1 ^
        -y 0 ^
        -Q "SET NOCOUNT ON; WITH col_map AS ( SELECT s.name AS schema_name, t.name AS table_name, c.name AS column_name, c.column_id AS col_position, c.is_nullable AS is_nullable, CASE tp.name WHEN 'int'              THEN 'NUMBER(10)' WHEN 'bigint'           THEN 'NUMBER(19)' WHEN 'smallint'         THEN 'NUMBER(5)' WHEN 'tinyint'          THEN 'NUMBER(3)' WHEN 'bit'              THEN 'NUMBER(1)' WHEN 'decimal'          THEN 'NUMBER(' + CAST(c.precision AS VARCHAR) + ',' + CAST(c.scale AS VARCHAR) + ')' WHEN 'numeric'          THEN 'NUMBER(' + CAST(c.precision AS VARCHAR) + ',' + CAST(c.scale AS VARCHAR) + ')' WHEN 'money'            THEN 'NUMBER(19,4)' WHEN 'smallmoney'       THEN 'NUMBER(10,4)' WHEN 'float'            THEN 'BINARY_DOUBLE' WHEN 'real'             THEN 'BINARY_FLOAT' WHEN 'char'             THEN 'CHAR(' + CAST(c.max_length AS VARCHAR) + ')' WHEN 'varchar'          THEN CASE WHEN c.max_length = -1 THEN 'CLOB' ELSE 'VARCHAR2(' + CAST(c.max_length AS VARCHAR) + ')' END WHEN 'nchar'            THEN 'NCHAR(' + CAST(c.max_length/2 AS VARCHAR) + ')' WHEN 'nvarchar'         THEN CASE WHEN c.max_length = -1 THEN 'NCLOB' ELSE 'NVARCHAR2(' + CAST(c.max_length/2 AS VARCHAR) + ')' END WHEN 'text'             THEN 'CLOB' WHEN 'ntext'            THEN 'NCLOB' WHEN 'date'             THEN 'DATE' WHEN 'datetime'         THEN 'DATE' WHEN 'smalldatetime'    THEN 'DATE' WHEN 'datetime2'        THEN 'TIMESTAMP(' + CAST(c.scale AS VARCHAR) + ')' WHEN 'datetimeoffset'   THEN 'TIMESTAMP(' + CAST(c.scale AS VARCHAR) + ') WITH TIME ZONE' WHEN 'time'             THEN 'INTERVAL DAY(0) TO SECOND(' + CAST(c.scale AS VARCHAR) + ')' WHEN 'binary'           THEN 'RAW(' + CAST(c.max_length AS VARCHAR) + ')' WHEN 'varbinary'        THEN CASE WHEN c.max_length = -1 THEN 'BLOB' ELSE 'RAW(' + CAST(c.max_length AS VARCHAR) + ')' END WHEN 'image'            THEN 'BLOB' WHEN 'timestamp'        THEN 'RAW(8)' WHEN 'uniqueidentifier' THEN 'RAW(16)' WHEN 'xml'              THEN 'XMLTYPE' WHEN 'sql_variant'      THEN '/* UNSUPPORTED: sql_variant */' WHEN 'hierarchyid'      THEN '/* UNSUPPORTED: hierarchyid */' WHEN 'geography'        THEN '/* UNSUPPORTED: geography */' WHEN 'geometry'         THEN '/* UNSUPPORTED: geometry */' ELSE '/* UNKNOWN: ' + tp.name + ' */' END AS oracle_type, CASE tp.name WHEN 'datetime'         THEN ' /* datetime->DATE: sub-second precision lost */' WHEN 'smalldatetime'    THEN ' /* smalldatetime->DATE: seconds lost */' WHEN 'bit'              THEN ' /* bit->NUMBER(1): 0 or 1 only */' WHEN 'timestamp'        THEN ' /* SS rowversion->RAW(8): not a datetime */' WHEN 'uniqueidentifier' THEN ' /* GUID->RAW(16): use HEXTORAW() on load */' WHEN 'float'            THEN ' /* float->BINARY_DOUBLE: precision may differ */' WHEN 'real'             THEN ' /* real->BINARY_FLOAT: precision may differ */' ELSE '' END AS conversion_note, CASE WHEN ic.object_id IS NOT NULL THEN 1 ELSE 0 END AS is_identity, ISNULL(ic.seed_value,1) AS identity_seed, ISNULL(ic.increment_value,1) AS identity_increment FROM sys.tables t JOIN sys.schemas s ON s.schema_id = t.schema_id JOIN sys.columns c ON c.object_id = t.object_id JOIN sys.types tp ON tp.user_type_id = c.user_type_id LEFT JOIN sys.identity_columns ic ON ic.object_id = c.object_id AND ic.column_id = c.column_id WHERE t.is_ms_shipped = 0 AND t.type = 'U' AND s.name = '!SCHEMA_NAME!' AND t.name = '!TABLE_NAME!' ), pk_cols AS ( SELECT STRING_AGG(c.name,', ') WITHIN GROUP (ORDER BY ic.key_ordinal) AS pk_columns FROM sys.tables t JOIN sys.schemas s ON s.schema_id = t.schema_id JOIN sys.indexes ix ON ix.object_id = t.object_id AND ix.is_primary_key = 1 JOIN sys.index_columns ic ON ic.object_id = ix.object_id AND ic.index_id = ix.index_id JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id WHERE s.name = '!SCHEMA_NAME!' AND t.name = '!TABLE_NAME!' ), col_lines AS ( SELECT col_position, '    ' + UPPER(column_name) + ' ' + oracle_type + CASE WHEN is_identity = 1 THEN ' GENERATED BY DEFAULT AS IDENTITY (START WITH ' + CAST(identity_seed AS VARCHAR) + ' INCREMENT BY ' + CAST(identity_increment AS VARCHAR) + ')' ELSE '' END + CASE WHEN is_nullable = 0 THEN ' NOT NULL' ELSE '' END + conversion_note AS col_def FROM col_map ), col_block AS ( SELECT STRING_AGG(col_def, ',' + CHAR(10)) WITHIN GROUP (ORDER BY col_position) AS columns_block FROM col_lines ) SELECT '-- ----------------------------------------' + CHAR(10) + '-- Source: !SCHEMA_NAME!.!TABLE_NAME!' + CHAR(10) + '-- Generated: ' + CONVERT(VARCHAR,GETDATE(),120) + CHAR(10) + '-- ----------------------------------------' + CHAR(10) + 'CREATE TABLE ' + UPPER('!SCHEMA_NAME!') + '.' + UPPER('!TABLE_NAME!') + CHAR(10) + '(' + CHAR(10) + cb.columns_block + CASE WHEN pk.pk_columns IS NOT NULL THEN ',' + CHAR(10) + '    CONSTRAINT PK_' + UPPER('!TABLE_NAME!') + ' PRIMARY KEY (' + UPPER(pk.pk_columns) + ')' ELSE '' END + CHAR(10) + ');' + CHAR(10) FROM col_block cb CROSS JOIN pk_cols pk;" ^
        -o "!OUT_FILE!"

    IF !ERRORLEVEL! EQU 0 (
        SET /A SUCCESS_COUNT+=1
    ) ELSE (
        SET /A FAIL_COUNT+=1
        SET FAIL_LIST=!FAIL_LIST! !SCHEMA_NAME!.!TABLE_NAME!
        ECHO   [WARN] Failed: !SCHEMA_NAME!.!TABLE_NAME!
    )
)

:: ------------------------------------------------------------
:: Step 4: Write a master script that runs all files in order
:: ------------------------------------------------------------
ECHO.
ECHO [3/3] Writing master_ddl.sql ...

SET MASTER_FILE=%OUT_DIR%\master_ddl.sql

ECHO -- ============================================================ > "%MASTER_FILE%"
ECHO -- Oracle DDL Master Script >> "%MASTER_FILE%"
ECHO -- Generated: %DATE% %TIME% >> "%MASTER_FILE%"
ECHO -- Database:  %SS_DATABASE% >> "%MASTER_FILE%"
ECHO -- Run this on Oracle via SQL*Plus: >> "%MASTER_FILE%"
ECHO --   sqlplus user/pass@tns @master_ddl.sql >> "%MASTER_FILE%"
ECHO -- ============================================================ >> "%MASTER_FILE%"
ECHO. >> "%MASTER_FILE%"

FOR %%F IN (%OUT_DIR%\*.sql) DO (
    SET FNAME=%%~nxF
    IF NOT "!FNAME!"=="master_ddl.sql" (
        ECHO @%%F >> "%MASTER_FILE%"
    )
)

:: ------------------------------------------------------------
:: Summary
:: ------------------------------------------------------------
ECHO.
ECHO ============================================================
ECHO  Export complete
ECHO  Succeeded : %SUCCESS_COUNT%
ECHO  Failed    : %FAIL_COUNT%
IF NOT "%FAIL_LIST%"=="" (
ECHO  Failed tables: %FAIL_LIST%
)
ECHO  Output dir: %OUT_DIR%
ECHO  Master DDL: %OUT_DIR%\master_ddl.sql
ECHO ============================================================
ECHO.
ECHO To run on Oracle:
ECHO   sqlplus YOUR_USER/YOUR_PASS@YOUR_TNS @%OUT_DIR%\master_ddl.sql
ECHO.

ENDLOCAL