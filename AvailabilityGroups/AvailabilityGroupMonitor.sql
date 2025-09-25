SELECT r.replica_server_name, r.endpoint_url, rs.connected_state_desc, rs.role_desc, 
rs.operational_state_desc, rs.recovery_health_desc,rs.synchronization_health_desc, 
r.availability_mode_desc, r.failover_mode_desc 
FROM sys.dm_hadr_availability_replica_states rs 
INNER JOIN sys.availability_replicas r ON rs.replica_id=r.replica_id 
ORDER BY r.replica_server_name;

GO

SELECT ag.name, ag.is_distributed, ar.replica_server_name, ar.availability_mode_desc, ars.connected_state_desc, ars.role_desc, 
ars.operational_state_desc, ars.synchronization_health_desc 
FROM sys.availability_groups ag 
JOIN sys.availability_replicas ar on ag.group_id=ar.group_id 
LEFT JOIN sys.dm_hadr_availability_replica_states ars ON ars.replica_id=ar.replica_id 
WHERE ag.is_distributed=1;

GO

SELECT ag.name , drs.database_id , drs.group_id , drs.replica_id , 
drs.synchronization_state_desc , drs.end_of_log_lsn 
FROM sys.dm_hadr_database_replica_states drs, sys.availability_groups ag 
WHERE drs.group_id = ag.group_id;

GO

&nbsp;

When secondary AG is in state not synchronizing, then check if any restarts have occurred. Check errorlog for connection timeoutσ

