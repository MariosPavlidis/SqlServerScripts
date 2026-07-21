-- Wait statistics analysis (based on Paul Randal's script)
-- Benign/idle wait types are excluded below, grouped by category. No URLs.

WITH [Waits] AS
    (SELECT
        [wait_type],
        [wait_time_ms] / 1000.0 AS [WaitS],
        ([wait_time_ms] - [signal_wait_time_ms]) / 1000.0 AS [ResourceS],
        [signal_wait_time_ms] / 1000.0 AS [SignalS],
        [waiting_tasks_count] AS [WaitCount],
        100.0 * [wait_time_ms] / SUM ([wait_time_ms]) OVER() AS [Percentage],
        max_wait_time_ms / 1000.0 AS MaxWaitSec,
        ROW_NUMBER() OVER(ORDER BY [wait_time_ms] DESC) AS [RowNum]
    FROM sys.dm_os_wait_stats
    WHERE [wait_type] NOT IN (
        -- Idle system / background tasks
        N'CHECKPOINT_QUEUE',
        N'CHKPT',
        N'DIRTY_PAGE_POLL',
        N'DISPATCHER_QUEUE_SEMAPHORE',
        N'KSOURCE_WAKEUP',
        N'LAZYWRITER_SLEEP',
        N'LOGMGR_QUEUE',
        N'MEMORY_ALLOCATION_EXT',
        N'ONDEMAND_TASK_QUEUE',
        N'REQUEST_FOR_DEADLOCK_SEARCH',
        N'RESOURCE_QUEUE',
        N'SERVER_IDLE_CHECK',
        N'SOS_WORK_DISPATCHER',
        N'SP_SERVER_DIAGNOSTICS_SLEEP',
        N'STARTUP_DEPENDENCY_MANAGER',
        N'WAIT_FOR_RESULTS',
        N'WAITFOR',
        N'WAITFOR_TASKSHUTDOWN',

        -- Sleep waits
        N'SLEEP_BPOOL_FLUSH',
        N'SLEEP_BPOOL_STEAL',
        N'SLEEP_BUFFERPOOL_HELPLW',
        N'SLEEP_DBSTARTUP',
        N'SLEEP_DCOMSTARTUP',
        N'SLEEP_MASTERDBREADY',
        N'SLEEP_MASTERMDREADY',
        N'SLEEP_MASTERUPGRADED',
        N'SLEEP_MSDBSTARTUP',
        N'SLEEP_RETRY_VIRTUALALLOC',
        N'SLEEP_SYSTEMTASK',
        N'SLEEP_TASK',
        N'SLEEP_TEMPDBSTARTUP',
        N'SLEEP_WORKSPACE_ALLOCATEPAGE',

        -- Service Broker (idle waiters)
        N'BROKER_EVENTHANDLER',
        N'BROKER_RECEIVE_WAITFOR',
        N'BROKER_TASK_STOP',
        N'BROKER_TO_FLUSH',
        N'BROKER_TRANSMITTER',

        -- CLR
        N'CLR_AUTO_EVENT',
        N'CLR_MANUAL_EVENT',
        N'CLR_SEMAPHORE',

        -- Parallelism (consumer side is benign; CXPACKET/CXSYNC_PORT are NOT filtered)
        N'CXCONSUMER',
        N'EXECSYNC',

        -- Database Mirroring
        -- (comment these five out if you have mirroring issues)
        N'DBMIRROR_DBM_EVENT',
        N'DBMIRROR_DBM_MUTEX',
        N'DBMIRROR_EVENTS_QUEUE',
        N'DBMIRROR_WORKER_QUEUE',
        N'DBMIRRORING_CMD',

        -- Availability Groups (idle/background HADR tasks)
        -- (comment these out if you have AG issues)
        N'HADR_CLUSAPI_CALL',
        N'HADR_FABRIC_CALLBACK',
        N'HADR_FILESTREAM_IOMGR_IOCOMPLETION',
        N'HADR_LOGCAPTURE_WAIT',
        N'HADR_NOTIFICATION_DEQUEUE',
        N'HADR_TIMER_TASK',
        N'HADR_WORK_QUEUE',

        -- Parallel redo (AG secondary background threads)
        N'PARALLEL_REDO_DRAIN_WORKER',
        N'PARALLEL_REDO_LOG_CACHE',
        N'PARALLEL_REDO_TRAN_LIST',
        N'PARALLEL_REDO_WORKER_SYNC',
        N'PARALLEL_REDO_WORKER_WAIT_WORK',
        N'REDO_THREAD_PENDING_WORK',

        -- Full-text search
        N'FSAGENT',
        N'FT_IFTS_SCHEDULER_IDLE_WAIT',
        N'FT_IFTSHC_MUTEX',

        -- Query Store background tasks
        N'QDS_ASYNC_QUEUE',
        N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP',
        N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP',
        N'QDS_SHUTDOWN_QUEUE',

        -- Preemptive (benign background OS calls only)
        N'PREEMPTIVE_HADR_LEASE_MECHANISM',
        N'PREEMPTIVE_OS_FLUSHFILEBUFFERS',
        N'PREEMPTIVE_SP_SERVER_DIAGNOSTICS',
        N'PREEMPTIVE_XE_CALLBACKEXECUTE',
        N'PREEMPTIVE_XE_DISPATCHER',
        N'PREEMPTIVE_XE_GETTARGETSTATE',
        N'PREEMPTIVE_XE_SESSIONCOMMIT',
        N'PREEMPTIVE_XE_TARGETFINALIZE',
        N'PREEMPTIVE_XE_TARGETINIT',

        -- PWAIT / startup
        N'PWAIT_ALL_COMPONENTS_INITIALIZED',
        N'PWAIT_DIRECTLOGCONSUMER_GETNEXT',
        N'PWAIT_EXTENSIBILITY_CLEANUP_TASK',

        -- Accelerated Database Recovery (PVS background)
        N'PVS_PREALLOCATE',

        -- SQL Trace / Profiler
        N'SQLTRACE_BUFFER_FLUSH',
        N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
        N'SQLTRACE_WAIT_ENTRIES',

        -- Extended Events
        N'XE_DISPATCHER_JOIN',
        N'XE_DISPATCHER_WAIT',
        N'XE_LIVE_TARGET_TVF',
        N'XE_TIMER_EVENT',

        -- In-Memory OLTP (XTP) background/checkpoint
        N'WAIT_XTP_CKPT_CLOSE',
        N'WAIT_XTP_HOST_WAIT',
        N'WAIT_XTP_OFFLINE_CKPT_NEW_LOG',
        N'WAIT_XTP_RECOVERY',

        -- Backup (VDI idle) / misc
        N'VDI_CLIENT_OTHER',
        N'SNI_HTTP_ACCEPT'
        )
    AND [waiting_tasks_count] > 0)
SELECT
    MAX ([W1].[wait_type]) AS [WaitType],
    CAST (MAX ([W1].[WaitS]) AS DECIMAL (16,0)) AS [Wait_Sec],
    CAST (MAX ([W1].[ResourceS]) AS DECIMAL (16,0)) AS [Resource_Sec],
    CAST (MAX ([W1].[SignalS]) AS DECIMAL (16,0)) AS [Signal_Sec],
    MAX ([W1].[WaitCount]) AS [WaitCount],
    CAST (MAX ([W1].[Percentage]) AS DECIMAL (5,2)) AS [Percentage],
    CAST (MAX ([W1].[MaxWaitSec]) AS DECIMAL (16,2)) AS [MaxWait_Sec],
    CAST ((MAX ([W1].[WaitS]) / MAX ([W1].[WaitCount])) AS DECIMAL (16,3)) AS [AvgWait_Sec],
    CAST ((MAX ([W1].[ResourceS]) / MAX ([W1].[WaitCount])) AS DECIMAL (16,3)) AS [AvgRes_Sec],
    CAST ((MAX ([W1].[SignalS]) / MAX ([W1].[WaitCount])) AS DECIMAL (16,3)) AS [AvgSig_Sec]
FROM [Waits] AS [W1]
INNER JOIN [Waits] AS [W2] ON [W2].[RowNum] <= [W1].[RowNum]
GROUP BY [W1].[RowNum]
HAVING SUM ([W2].[Percentage]) - MAX( [W1].[Percentage] ) < 95 -- percentage threshold
GO