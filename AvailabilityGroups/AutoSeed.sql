-- Seeding attempts and outcomes (history + status)
SELECT
    ag.name                                    AS AG,
    adc.database_name                          AS DatabaseName,
    ar.replica_server_name                     AS TargetReplica,
    ase.start_time                             AS StartTime,
    ase.completion_time                        AS CompletionTime,
    ase.current_state							AS State,
    ase.performed_seeding                      AS PerformedSeeding,
    ase.number_of_attempts                     AS Attempts,
    ase.failure_state                          AS FailureState,
    ase.failure_state_desc                     AS FailureStateDesc,
    ase.error_code                             AS ErrorCode
FROM sys.dm_hadr_automatic_seeding AS ase
LEFT JOIN sys.availability_groups           AS ag  ON ag.group_id            = ase.ag_id
LEFT JOIN sys.availability_databases_cluster AS adc ON adc.group_database_id  = ase.ag_db_id
LEFT JOIN sys.availability_replicas         AS ar  ON ar.replica_id          = ase.ag_remote_replica_id
ORDER BY ase.start_time DESC;
