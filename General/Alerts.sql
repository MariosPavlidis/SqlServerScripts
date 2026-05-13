/*
================================================================================
  SQL SERVER ALERTING SETUP SCRIPT
  Purpose : Create SQL Agent alerts for major error categories
  Author  : DBA Team
  Notes   : Run as sysadmin. Requires SQL Server Agent to be running.
            Adjust @operator_name to match your environment.
            Review severity thresholds and error numbers before deploying.
================================================================================
*/

USE msdb;
GO

SET NOCOUNT ON;
GO

-- ============================================================
-- CONFIGURATION: set your operator name here
-- ============================================================
DECLARE @operator_name NVARCHAR(128) = N'DBA_Operator';

-- Verify operator exists before proceeding
IF NOT EXISTS (
    SELECT 1 FROM msdb.dbo.sysoperators WHERE name = @operator_name
)
BEGIN
    RAISERROR(
        'Operator [%s] does not exist. Create it first via SQL Agent > Operators.',
        16, 1, @operator_name
    );
    RETURN;
END
GO

-- ============================================================
-- HELPER: drop alert if it already exists
-- ============================================================
IF OBJECT_ID('tempdb..#DropAlert') IS NOT NULL DROP TABLE #DropAlert;

CREATE TABLE #DropAlert (alert_name NVARCHAR(128));
GO

-- ============================================================
-- SECTION 1: SEVERITY-BASED ALERTS (Sev 17–25)
-- ============================================================
-- Sev 17 = Insufficient resources (memory, locks, disk space)
-- Sev 18 = Non-fatal internal error
-- Sev 19 = Fatal resource error (non-configurable)
-- Sev 20 = Fatal error for current process
-- Sev 21 = Fatal error for all processes on database
-- Sev 22 = Fatal error - table or index suspected damaged
-- Sev 23 = Fatal error - database integrity suspect
-- Sev 24 = Fatal hardware error
-- Sev 25 = Fatal error (catch-all)

DECLARE @sev      INT       = 17;
DECLARE @op       NVARCHAR(128) = N'DBA_Operator';
DECLARE @sev_name NVARCHAR(128);

WHILE @sev <= 25
BEGIN
    SET @sev_name = N'Alert - Severity ' + CAST(@sev AS NVARCHAR(2));

    IF EXISTS (SELECT 1 FROM msdb.dbo.sysalerts WHERE name = @sev_name)
        EXEC msdb.dbo.sp_delete_alert @name = @sev_name;

    EXEC msdb.dbo.sp_add_alert
        @name              = @sev_name,
        @message_id        = 0,
        @severity          = @sev,
        @enabled           = 1,
        @delay_between_responses = 60,   -- seconds between repeat notifications
        @include_event_description_in = 1,
        @notification_message = N'';

    EXEC msdb.dbo.sp_add_notification
        @alert_name    = @sev_name,
        @operator_name = @op,
        @notification_method = 1;        -- 1=email, 2=pager, 4=net send

    PRINT 'Created: ' + @sev_name;
    SET @sev = @sev + 1;
END
GO

-- ============================================================
-- SECTION 2: SPECIFIC ERROR NUMBER ALERTS
-- ============================================================
-- Each block: drop-if-exists → sp_add_alert → sp_add_notification

DECLARE @op NVARCHAR(128) = N'DBA_Operator';

-- ----------------------------------------------------------
-- 2.1  DATA CORRUPTION & INTEGRITY
-- ----------------------------------------------------------

-- 823  : I/O error (sector read failure / hardware fault)
IF EXISTS (SELECT 1 FROM msdb.dbo.sysalerts WHERE name = N'Alert - Error 823 (I/O Error)')
    EXEC msdb.dbo.sp_delete_alert @name = N'Alert - Error 823 (I/O Error)';

EXEC msdb.dbo.sp_add_alert
    @name              = N'Alert - Error 823 (I/O Error)',
    @message_id        = 823,
    @severity          = 0,
    @enabled           = 1,
    @delay_between_responses = 60,
    @include_event_description_in = 1;

EXEC msdb.dbo.sp_add_notification
    @alert_name    = N'Alert - Error 823 (I/O Error)',
    @operator_name = @op,
    @notification_method = 1;

PRINT 'Created: Alert - Error 823 (I/O Error)';

-- 824  : Logical consistency-based I/O error (page torn or bad checksum)
IF EXISTS (SELECT 1 FROM msdb.dbo.sysalerts WHERE name = N'Alert - Error 824 (Logical I/O Error)')
    EXEC msdb.dbo.sp_delete_alert @name = N'Alert - Error 824 (Logical I/O Error)';

EXEC msdb.dbo.sp_add_alert
    @name              = N'Alert - Error 824 (Logical I/O Error)',
    @message_id        = 824,
    @severity          = 0,
    @enabled           = 1,
    @delay_between_responses = 60,
    @include_event_description_in = 1;

EXEC msdb.dbo.sp_add_notification
    @alert_name    = N'Alert - Error 824 (Logical I/O Error)',
    @operator_name = @op,
    @notification_method = 1;

PRINT 'Created: Alert - Error 824 (Logical I/O Error)';

-- 825  : Read-retry required (usually signals dying disk)
IF EXISTS (SELECT 1 FROM msdb.dbo.sysalerts WHERE name = N'Alert - Error 825 (Read Retry)')
    EXEC msdb.dbo.sp_delete_alert @name = N'Alert - Error 825 (Read Retry)';

EXEC msdb.dbo.sp_add_alert
    @name              = N'Alert - Error 825 (Read Retry)',
    @message_id        = 825,
    @severity          = 0,
    @enabled           = 1,
    @delay_between_responses = 60,
    @include_event_description_in = 1;

EXEC msdb.dbo.sp_add_notification
    @alert_name    = N'Alert - Error 825 (Read Retry)',
    @operator_name = @op,
    @notification_method = 1;

PRINT 'Created: Alert - Error 825 (Read Retry)';

-- ----------------------------------------------------------
-- 2.2  TRANSACTION LOG
-- ----------------------------------------------------------

-- 9002 : Transaction log full
IF EXISTS (SELECT 1 FROM msdb.dbo.sysalerts WHERE name = N'Alert - Error 9002 (Log Full)')
    EXEC msdb.dbo.sp_delete_alert @name = N'Alert - Error 9002 (Log Full)';

EXEC msdb.dbo.sp_add_alert
    @name              = N'Alert - Error 9002 (Log Full)',
    @message_id        = 9002,
    @severity          = 0,
    @enabled           = 1,
    @delay_between_responses = 60,
    @include_event_description_in = 1;

EXEC msdb.dbo.sp_add_notification
    @alert_name    = N'Alert - Error 9002 (Log Full)',
    @operator_name = @op,
    @notification_method = 1;

PRINT 'Created: Alert - Error 9002 (Log Full)';

-- 3041 : Backup failed (raised before a more specific message)
IF EXISTS (SELECT 1 FROM msdb.dbo.sysalerts WHERE name = N'Alert - Error 3041 (Backup Failed)')
    EXEC msdb.dbo.sp_delete_alert @name = N'Alert - Error 3041 (Backup Failed)';

EXEC msdb.dbo.sp_add_alert
    @name              = N'Alert - Error 3041 (Backup Failed)',
    @message_id        = 3041,
    @severity          = 0,
    @enabled           = 1,
    @delay_between_responses = 60,
    @include_event_description_in = 1;

EXEC msdb.dbo.sp_add_notification
    @alert_name    = N'Alert - Error 3041 (Backup Failed)',
    @operator_name = @op,
    @notification_method = 1;

PRINT 'Created: Alert - Error 3041 (Backup Failed)';

-- ----------------------------------------------------------
-- 2.3  AVAILABILITY & CONNECTIVITY
-- ----------------------------------------------------------

-- 17806: SSPI handshake failure (Kerberos / login issue)
IF EXISTS (SELECT 1 FROM msdb.dbo.sysalerts WHERE name = N'Alert - Error 17806 (SSPI Handshake Failed)')
    EXEC msdb.dbo.sp_delete_alert @name = N'Alert - Error 17806 (SSPI Handshake Failed)';

EXEC msdb.dbo.sp_add_alert
    @name              = N'Alert - Error 17806 (SSPI Handshake Failed)',
    @message_id        = 17806,
    @severity          = 0,
    @enabled           = 1,
    @delay_between_responses = 300,      -- noisy; suppress repeats for 5 min
    @include_event_description_in = 1;

EXEC msdb.dbo.sp_add_notification
    @alert_name    = N'Alert - Error 17806 (SSPI Handshake Failed)',
    @operator_name = @op,
    @notification_method = 1;

PRINT 'Created: Alert - Error 17806 (SSPI Handshake Failed)';

-- 17207: OS error during database file open (permission or missing file)
IF EXISTS (SELECT 1 FROM msdb.dbo.sysalerts WHERE name = N'Alert - Error 17207 (File Open Failed)')
    EXEC msdb.dbo.sp_delete_alert @name = N'Alert - Error 17207 (File Open Failed)';

EXEC msdb.dbo.sp_add_alert
    @name              = N'Alert - Error 17207 (File Open Failed)',
    @message_id        = 17207,
    @severity          = 0,
    @enabled           = 1,
    @delay_between_responses = 60,
    @include_event_description_in = 1;

EXEC msdb.dbo.sp_add_notification
    @alert_name    = N'Alert - Error 17207 (File Open Failed)',
    @operator_name = @op,
    @notification_method = 1;

PRINT 'Created: Alert - Error 17207 (File Open Failed)';

-- ----------------------------------------------------------
-- 2.4  ALWAYS ON / DATABASE MIRRORING
-- ----------------------------------------------------------

-- 1480 : AG role change (primary/secondary switch)
IF EXISTS (SELECT 1 FROM msdb.dbo.sysalerts WHERE name = N'Alert - Error 1480 (AG Role Change)')
    EXEC msdb.dbo.sp_delete_alert @name = N'Alert - Error 1480 (AG Role Change)';

EXEC msdb.dbo.sp_add_alert
    @name              = N'Alert - Error 1480 (AG Role Change)',
    @message_id        = 1480,
    @severity          = 0,
    @enabled           = 1,
    @delay_between_responses = 60,
    @include_event_description_in = 1;

EXEC msdb.dbo.sp_add_notification
    @alert_name    = N'Alert - Error 1480 (AG Role Change)',
    @operator_name = @op,
    @notification_method = 1;

PRINT 'Created: Alert - Error 1480 (AG Role Change)';

-- 35264: AG database not synchronizing
IF EXISTS (SELECT 1 FROM msdb.dbo.sysalerts WHERE name = N'Alert - Error 35264 (AG Not Synchronizing)')
    EXEC msdb.dbo.sp_delete_alert @name = N'Alert - Error 35264 (AG Not Synchronizing)';

EXEC msdb.dbo.sp_add_alert
    @name              = N'Alert - Error 35264 (AG Not Synchronizing)',
    @message_id        = 35264,
    @severity          = 0,
    @enabled           = 1,
    @delay_between_responses = 60,
    @include_event_description_in = 1;

EXEC msdb.dbo.sp_add_notification
    @alert_name    = N'Alert - Error 35264 (AG Not Synchronizing)',
    @operator_name = @op,
    @notification_method = 1;

PRINT 'Created: Alert - Error 35264 (AG Not Synchronizing)';

-- 35265: AG database not synchronized (data loss risk)
IF EXISTS (SELECT 1 FROM msdb.dbo.sysalerts WHERE name = N'Alert - Error 35265 (AG Not Synchronized)')
    EXEC msdb.dbo.sp_delete_alert @name = N'Alert - Error 35265 (AG Not Synchronized)';

EXEC msdb.dbo.sp_add_alert
    @name              = N'Alert - Error 35265 (AG Not Synchronized)',
    @message_id        = 35265,
    @severity          = 0,
    @enabled           = 1,
    @delay_between_responses = 60,
    @include_event_description_in = 1;

EXEC msdb.dbo.sp_add_notification
    @alert_name    = N'Alert - Error 35265 (AG Not Synchronized)',
    @operator_name = @op,
    @notification_method = 1;

PRINT 'Created: Alert - Error 35265 (AG Not Synchronized)';

-- ----------------------------------------------------------
-- 2.5  MEMORY & RESOURCES
-- ----------------------------------------------------------

-- 701  : Insufficient system memory in resource pool
IF EXISTS (SELECT 1 FROM msdb.dbo.sysalerts WHERE name = N'Alert - Error 701 (Insufficient Memory)')
    EXEC msdb.dbo.sp_delete_alert @name = N'Alert - Error 701 (Insufficient Memory)';

EXEC msdb.dbo.sp_add_alert
    @name              = N'Alert - Error 701 (Insufficient Memory)',
    @message_id        = 701,
    @severity          = 0,
    @enabled           = 1,
    @delay_between_responses = 60,
    @include_event_description_in = 1;

EXEC msdb.dbo.sp_add_notification
    @alert_name    = N'Alert - Error 701 (Insufficient Memory)',
    @operator_name = @op,
    @notification_method = 1;

PRINT 'Created: Alert - Error 701 (Insufficient Memory)';

-- 1105 : Could not allocate space (data file / filegroup full)
IF EXISTS (SELECT 1 FROM msdb.dbo.sysalerts WHERE name = N'Alert - Error 1105 (Filegroup Full)')
    EXEC msdb.dbo.sp_delete_alert @name = N'Alert - Error 1105 (Filegroup Full)';

EXEC msdb.dbo.sp_add_alert
    @name              = N'Alert - Error 1105 (Filegroup Full)',
    @message_id        = 1105,
    @severity          = 0,
    @enabled           = 1,
    @delay_between_responses = 60,
    @include_event_description_in = 1;

EXEC msdb.dbo.sp_add_notification
    @alert_name    = N'Alert - Error 1105 (Filegroup Full)',
    @operator_name = @op,
    @notification_method = 1;

PRINT 'Created: Alert - Error 1105 (Filegroup Full)';

-- ----------------------------------------------------------
-- 2.6  SECURITY
-- ----------------------------------------------------------

-- 18456: Login failed (repeated failures may indicate brute force)
IF EXISTS (SELECT 1 FROM msdb.dbo.sysalerts WHERE name = N'Alert - Error 18456 (Login Failed)')
    EXEC msdb.dbo.sp_delete_alert @name = N'Alert - Error 18456 (Login Failed)';

EXEC msdb.dbo.sp_add_alert
    @name              = N'Alert - Error 18456 (Login Failed)',
    @message_id        = 18456,
    @severity          = 0,
    @enabled           = 1,
    @delay_between_responses = 300,      -- suppress noise; adjust per environment
    @include_event_description_in = 1;

EXEC msdb.dbo.sp_add_notification
    @alert_name    = N'Alert - Error 18456 (Login Failed)',
    @operator_name = @op,
    @notification_method = 1;

PRINT 'Created: Alert - Error 18456 (Login Failed)';

-- 15457: sp_configure change applied (configuration change audit)
IF EXISTS (SELECT 1 FROM msdb.dbo.sysalerts WHERE name = N'Alert - Error 15457 (Configuration Change)')
    EXEC msdb.dbo.sp_delete_alert @name = N'Alert - Error 15457 (Configuration Change)';

EXEC msdb.dbo.sp_add_alert
    @name              = N'Alert - Error 15457 (Configuration Change)',
    @message_id        = 15457,
    @severity          = 0,
    @enabled           = 1,
    @delay_between_responses = 60,
    @include_event_description_in = 1;

EXEC msdb.dbo.sp_add_notification
    @alert_name    = N'Alert - Error 15457 (Configuration Change)',
    @operator_name = @op,
    @notification_method = 1;

PRINT 'Created: Alert - Error 15457 (Configuration Change)';

-- ----------------------------------------------------------
-- 2.7  BLOCKING & DEADLOCKS
-- ----------------------------------------------------------

-- 1205 : Transaction deadlock victim chosen
IF EXISTS (SELECT 1 FROM msdb.dbo.sysalerts WHERE name = N'Alert - Error 1205 (Deadlock Victim)')
    EXEC msdb.dbo.sp_delete_alert @name = N'Alert - Error 1205 (Deadlock Victim)';

EXEC msdb.dbo.sp_add_alert
    @name              = N'Alert - Error 1205 (Deadlock Victim)',
    @message_id        = 1205,
    @severity          = 0,
    @enabled           = 1,
    @delay_between_responses = 60,
    @include_event_description_in = 1;

EXEC msdb.dbo.sp_add_notification
    @alert_name    = N'Alert - Error 1205 (Deadlock Victim)',
    @operator_name = @op,
    @notification_method = 1;

PRINT 'Created: Alert - Error 1205 (Deadlock Victim)';

-- ----------------------------------------------------------
-- 2.8  CORRUPTION DETECTION (DBCC)
-- ----------------------------------------------------------

-- 7886 : DBCC CHECKDB found corruption
IF EXISTS (SELECT 1 FROM msdb.dbo.sysalerts WHERE name = N'Alert - Error 7886 (DBCC Corruption)')
    EXEC msdb.dbo.sp_delete_alert @name = N'Alert - Error 7886 (DBCC Corruption)';

EXEC msdb.dbo.sp_add_alert
    @name              = N'Alert - Error 7886 (DBCC Corruption)',
    @message_id        = 7886,
    @severity          = 0,
    @enabled           = 1,
    @delay_between_responses = 60,
    @include_event_description_in = 1;

EXEC msdb.dbo.sp_add_notification
    @alert_name    = N'Alert - Error 7886 (DBCC Corruption)',
    @operator_name = @op,
    @notification_method = 1;

PRINT 'Created: Alert - Error 7886 (DBCC Corruption)';

GO

-- ============================================================
-- SECTION 3: VERIFY ALL ALERTS
-- ============================================================
SELECT
    a.name                                       AS alert_name,
    CASE a.message_id WHEN 0 THEN 'Severity ' + CAST(a.severity AS VARCHAR)
                      ELSE 'Error ' + CAST(a.message_id AS VARCHAR)
    END                                          AS trigger_on,
    a.enabled,
    a.delay_between_responses                    AS delay_sec,
    o.name                                       AS operator,
    n.notification_method
FROM msdb.dbo.sysalerts          AS a
JOIN msdb.dbo.sysnotifications   AS n ON a.id = n.alert_id
JOIN msdb.dbo.sysoperators       AS o ON n.operator_id = o.id
ORDER BY
    CASE WHEN a.message_id = 0 THEN a.severity ELSE 100 + a.message_id END,
    a.name;

GO

/*
================================================================================
  QUICK REFERENCE — ALERTS CREATED
  ─────────────────────────────────────────────────────────────────────────────
  SEVERITY-BASED (Sev 17–25)
    Sev 17  Insufficient resources
    Sev 18  Non-fatal internal error
    Sev 19  Fatal resource error
    Sev 20  Fatal error – current process
    Sev 21  Fatal error – all processes on database
    Sev 22  Table/index suspected damaged
    Sev 23  Database integrity suspect
    Sev 24  Fatal hardware error
    Sev 25  Fatal error (catch-all)

  ERROR-SPECIFIC
    701     Insufficient system memory
    823     I/O hardware error
    824     Logical consistency I/O error (torn page / bad checksum)
    825     Read-retry required (failing disk)
    1105    Filegroup full / cannot allocate space
    1205    Deadlock victim chosen
    1480    Always On – role change
    3041    Backup failed
    7886    DBCC found corruption
    9002    Transaction log full
    15457   sp_configure change applied (audit)
    17207   OS error on file open
    17806   SSPI handshake failed
    18456   Login failed
    35264   AG database not synchronizing
    35265   AG database not synchronized

  POST-DEPLOYMENT CHECKLIST
    [ ] Confirm SQL Agent is running
    [ ] Confirm operator email/pager is configured
    [ ] Test with:  EXEC msdb.dbo.sp_notify_operator
                        @name='DBA_Operator',
                        @subject='Test alert',
                        @body='Alert system is live.';
    [ ] Review delay_between_responses for noisy alerts (18456, 17806)
    [ ] Consider Database Mail profile if not already set up:
          EXEC msdb.dbo.sp_configure 'Database Mail XPs', 1;
          RECONFIGURE;
================================================================================
*/