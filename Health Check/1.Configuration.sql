-- OS information
SELECT
    windows_release,
    windows_service_pack_level,
    windows_sku,
    os_language_version
FROM sys.dm_os_windows_info;


-- Version, edition, and patch information
SELECT
    SERVERPROPERTY('ProductVersion')   AS ProductVersion,
    SERVERPROPERTY('ProductLevel')     AS ProductLevel,
    SERVERPROPERTY('ProductUpdateLevel') AS CU,
    SERVERPROPERTY('Edition')          AS Edition,
    SERVERPROPERTY('EngineEdition')    AS EngineEdition,
    @@VERSION                          AS FullVersion;

select * from sys.configurations
where name in (
'max degree of parallelism',
'cost threshold for parallelism',	--50
'min server memory (MB)',
'max server memory (MB)', --	75% of server memory 
'optimize for ad hoc workloads',
'backup compression default','backup checksum default',
'xp_cmdshell')


select sqlserver_start_time from sys.dm_os_sys_info

select physical_memory_kb/1024/1024 physical_memory_gb,
virtual_memory_kb/1024/1024 virtual_memory_gb,
committed_kb/1024/1024 committed_gb,
committed_target_kb/1024/1024 commited_target_gb,
visible_target_kb/1024/1024 visible_target_gb from sys.dm_os_sys_info

select virtual_machine_type_desc,
hyperthread_ratio from sys.dm_os_sys_info

select 
cpu_count,
socket_count, 
cores_per_socket,
numa_node_count,
softnuma_configuration_desc,
scheduler_count,
scheduler_total_count,
max_workers_count
from sys.dm_os_sys_info

--Instant File Initialization
EXEC xp_readerrorlog 0, 1, N'Database Instant File Initialization';

--Service Account
SELECT 
    servicename,
    startup_type_desc,
    status_desc,
    service_account
FROM sys.dm_server_services
WHERE servicename LIKE 'SQL Server (%'
   OR servicename = 'SQL Server (MSSQLSERVER)';

-- Configured max and min server memory
SELECT
    name,
    value_in_use    AS CurrentValueMB,
    value           AS ConfiguredValueMB,
    description
FROM sys.configurations
WHERE name IN ('max server memory (MB)', 'min server memory (MB)')
ORDER BY name;