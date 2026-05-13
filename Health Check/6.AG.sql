-- AG health overview
SELECT
    ag.name                             AS AGName,
    ar.replica_server_name              AS ReplicaServer,
    ars.role_desc                       AS Role,
    ars.operational_state_desc,
    ars.connected_state_desc,
    ars.synchronization_health_desc,
    ar.availability_mode_desc,
    ar.failover_mode_desc,
    ar.seeding_mode_desc
FROM sys.availability_groups            ag
JOIN sys.availability_replicas          ar  ON ar.group_id = ag.group_id
JOIN sys.dm_hadr_availability_replica_states ars
    ON ars.replica_id = ar.replica_id
ORDER BY ag.name, ars.role_desc;

-- Per-database synchronisation state and lag
SELECT
    ag.name                             AS AGName,
    drs.database_id,
    DB_NAME(drs.database_id)            AS DatabaseName,
    ar.replica_server_name,
    drs.synchronization_state_desc,
    drs.synchronization_health_desc,
    drs.log_send_queue_size             AS LogSendQueueKB,
    drs.log_send_rate                   AS LogSendRateKBps,
    drs.redo_queue_size                 AS RedoQueueKB,
    drs.redo_rate                       AS RedoRateKBps,
    drs.last_commit_time
FROM sys.dm_hadr_database_replica_states drs
JOIN sys.availability_replicas           ar  ON ar.replica_id = drs.replica_id
JOIN sys.availability_groups             ag  ON ag.group_id   = ar.group_id
ORDER BY ag.name, ar.replica_server_name, DB_NAME(drs.database_id);

-- Listener names, IPs, and port per AG
SELECT
    ag.name                             AS AGName,
    agl.dns_name                        AS ListenerDNS,
    agl.port,
    ip.ip_address,
    ip.ip_subnet_mask,
    ip.state_desc                       AS IPState
FROM sys.availability_group_listeners   agl
JOIN sys.availability_groups            ag  ON ag.group_id = agl.group_id
JOIN sys.availability_group_listener_ip_addresses ip
    ON ip.listener_id = agl.listener_id
ORDER BY ag.name;

SELECT ag.name AS AGName, ar.replica_server_name, 
DB_NAME(drs.database_id) AS DatabaseName,
 ar.availability_mode_desc, ar.failover_mode_desc, 
 DATEDIFF(SECOND, drs.last_commit_time, pri.last_commit_time) AS EstimatedDataLossSec 
 FROM sys.dm_hadr_database_replica_states drs 
 JOIN sys.availability_replicas ar ON ar.replica_id = drs.replica_id 
 JOIN sys.availability_groups ag ON ag.group_id = ar.group_id 
  JOIN sys.dm_hadr_database_replica_states pri 
  ON pri.database_id = drs.database_id AND pri.group_id = drs.group_id AND pri.is_primary_replica = 1 
  WHERE drs.is_primary_replica = 0 
 ORDER BY EstimatedDataLossSec DESC;

 EXEC xp_readerrorlog 0, 1, N'availability', NULL,   '20260401','20260506', N'desc';
 
-- Also check for role change events
EXEC xp_readerrorlog 0, 1, N'HADR', NULL,'20260401','20260506', N'desc';

