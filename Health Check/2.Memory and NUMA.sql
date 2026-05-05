-- Configured max and min server memory
SELECT
    name,
    value_in_use    AS CurrentValueMB,
    value           AS ConfiguredValueMB,
    description
FROM sys.configurations
WHERE name IN ('max server memory (MB)', 'min server memory (MB)')
ORDER BY name;

-- Host physical memory and OS pressure state
SELECT
    total_physical_memory_kb / 1024             AS TotalPhysicalMemoryMB,
    available_physical_memory_kb / 1024         AS AvailablePhysicalMemoryMB,
    total_page_file_kb / 1024                   AS TotalPageFileMB,
    available_page_file_kb / 1024               AS AvailablePageFileMB,
    CAST(100.0 * (total_page_file_kb - available_page_file_kb)/ NULLIF(total_page_file_kb, 0) AS DECIMAL(5,1)) AS PageFileUsedPct,
    system_memory_state_desc                    AS OSMemoryState
FROM sys.dm_os_sys_memory;
 
-- Current SQL Server memory consumption vs configured max
SELECT
    physical_memory_in_use_kb / 1024            AS SQLPhysicalMemoryMB,
    virtual_address_space_committed_kb / 1024   AS VASCommittedMB,
    locked_page_allocations_kb / 1024           AS LockedPagesMB,
    large_page_allocations_kb / 1024            AS LargePagesMB,
    page_fault_count,
    memory_utilization_percentage               AS MemUtilPct
FROM sys.dm_os_process_memory;


-- Memory clerks -- top consumers inside SQL Server
SELECT TOP 10
    type                                        AS ClerkType,
    name                                        AS ClerkName,
    SUM(pages_kb) / 1024                        AS AllocatedMB
FROM sys.dm_os_memory_clerks
GROUP BY type, name
ORDER BY AllocatedMB DESC;



-- Memory per NUMA node
SELECT
    memory_node_id,
    virtual_address_space_reserved_kb / 1024.0   AS va_reserved_mb,
    virtual_address_space_committed_kb / 1024.0  AS va_committed_mb,
    locked_page_allocations_kb / 1024.0          AS locked_pages_mb,
    pages_kb / 1024.0                            AS pages_mb,
    foreign_committed_kb / 1024.0                AS foreign_committed_mb,  -- cross-NUMA allocation!
    shared_memory_reserved_kb / 1024.0           AS shared_reserved_mb,
    shared_memory_committed_kb / 1024.0          AS shared_committed_mb
FROM sys.dm_os_memory_nodes
ORDER BY memory_node_id;

-- NUMA nodes with CPU and memory details
SELECT
    n.node_id,
    n.node_state_desc,
    n.memory_node_id,
    n.processor_group,
    n.online_scheduler_count,
    n.idle_scheduler_count,
    n.active_worker_count,
    n.avg_load_balance,
    mn.pages_kb / 1024.0                        AS node_pages_mb
FROM sys.dm_os_nodes               n
JOIN sys.dm_os_memory_nodes        mn
    ON n.memory_node_id = mn.memory_node_id
WHERE n.node_state_desc <> 'ONLINE DAC'
ORDER BY n.node_id;

-- Per-NUMA node scheduler detail
SELECT
    parent_node_id                      AS NUMANode,
    COUNT(*)                            AS SchedulerCount,
    SUM(current_tasks_count)            AS CurrentTasks,
    SUM(runnable_tasks_count)           AS RunnableTasks,
    SUM(work_queue_count)               AS WorkQueueDepth,
    SUM(pending_disk_io_count)          AS PendingDiskIO
FROM sys.dm_os_schedulers
WHERE status = 'VISIBLE ONLINE'
GROUP BY parent_node_id
ORDER BY parent_node_id;

-- Memory used by buffer pool per database
SELECT
    CASE database_id
        WHEN 32767 THEN 'ResourceDB'
        ELSE DB_NAME(database_id)
    END                                          AS database_name,
    COUNT(*)                                     AS page_count,
    COUNT(*) * 8 / 1024.0                        AS size_mb,
    SUM(CAST(is_modified AS INT))                AS dirty_pages
FROM sys.dm_os_buffer_descriptors
GROUP BY database_id
ORDER BY size_mb DESC;


-- Page life expectancy per NUMA node (target: > 300s, ideally > 1000s)
SELECT
    [object_name],
    instance_name,
    cntr_value                                   AS page_life_expectancy_sec
FROM sys.dm_os_performance_counters
WHERE counter_name = 'Page life expectancy'
ORDER BY instance_name;

-- Memory grants and pending requests (workload pressure)
SELECT
    pool_id,
    [name]                                       AS pool_name,
    max_memory_kb / 1024.0                       AS max_memory_mb,
    used_memory_kb / 1024.0                      AS used_memory_mb,
    target_memory_kb / 1024.0                    AS target_memory_mb,
    cache_memory_kb / 1024.0                     AS cache_memory_mb,
    compile_memory_kb / 1024.0                   AS compile_memory_mb
FROM sys.dm_resource_governor_resource_pools;

-- Pending memory grants (queries waiting for memory)
SELECT
    session_id,
    granted_memory_kb / 1024.0                  AS granted_mb,
    requested_memory_kb / 1024.0                AS requested_mb,
    required_memory_kb / 1024.0                 AS required_mb,
    queue_id,
    wait_order,
    is_next_candidate
FROM sys.dm_exec_query_memory_grants
WHERE grant_time IS NULL                         -- NULL = still waiting
ORDER BY requested_memory_kb DESC;