-- Run this query on the Global Primary

-- Check the results to see if synchronization_state_desc is SYNCHRONIZED
SELECT ag.name,
       drs.database_id AS [Availability Group],
       db_name(drs.database_id) AS database_name,
       drs.synchronization_state_desc,
       drs.last_hardened_lsn
FROM sys.dm_hadr_database_replica_states AS drs
     INNER JOIN
     sys.availability_groups AS ag
     ON drs.group_id = ag.group_id
WHERE ag.name = 'distributedAG'
ORDER BY [Availability Group];