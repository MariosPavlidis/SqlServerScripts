
-- OS information
SELECT
    windows_release,
    windows_service_pack_level,
    windows_sku,
    os_language_version
FROM sys.dm_os_windows_info;


-- Instance information
SELECT
	SERVERPROPERTY('ServerName')   AS ServerName,
	SERVERPROPERTY('InstanceName')   AS InstanceName,
	SERVERPROPERTY('MachineName')   AS MachineName,
    SERVERPROPERTY('ProductVersion')   AS ProductVersion,
    SERVERPROPERTY('ProductLevel')     AS ProductLevel,
    SERVERPROPERTY('ProductUpdateLevel') AS CU,
    SERVERPROPERTY('Edition')          AS Edition,
    SERVERPROPERTY('EngineEdition')    AS EngineEdition,
	SERVERPROPERTY('Collation')    AS Collation,
	case SERVERPROPERTY('FilestreamEffectiveLevel') 
	when 0 then 'disabeld' 
	when 1 then 'enabled for Transact-SQL access' 
	when 2 then 'enabled for Transact-SQL and local Win32 streaming access'   
	when 3 then 'enabled for Transact-SQL and both local and remote Win32 streaming access'
	end AS FilestreamEffectiveLevel,
	case SERVERPROPERTY('IsHadrEnabled')   
	when 0 then 'Disabled'
	when 1 then 'Enabled'
	end AS Hadr,
	case SERVERPROPERTY('IsClustered') 
	when 0 then 'Disabled'
	when 1 then 'Enabled'
	end  as isClustered,
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
-------------------------------------------------------------------

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

select name,create_date,compatibility_level,collation_name,user_access_desc,state_desc,recovery_model_desc,log_reuse_wait_desc,
is_encrypted,is_master_key_encrypted_by_server,is_cdc_enabled,
containment_desc,delayed_durability_desc,is_memory_optimized_enabled
page_verify_option_desc,is_query_store_on,
is_read_only,is_auto_close_on,is_auto_shrink_on,
is_accelerated_database_recovery_on,is_auto_create_stats_on,is_auto_update_stats_on,
is_read_committed_snapshot_on,snapshot_isolation_state_desc
from sys.databases


	---errorlog files information
EXEC sys.sp_enumerrorlogs;