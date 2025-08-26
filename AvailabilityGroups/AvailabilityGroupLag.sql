select db_name(d1),s1, t2 as [Primary],t1 as [Secondary],  
convert(char(8),dateadd(s,datediff(s,t1,t2),'1900-1-1'),8) as [Lag] from  
(select database_id d1 , last_commit_time t1  
FROM sys.dm_hadr_database_replica_states  
where replica_id =(select replica_id from sys.dm_hadr_availability_replica_states where role_desc='SECONDARY')  
and synchronization_state_desc!='SYNCHRONIZED'  
) A,  
(select database_id d2, last_commit_time t2 , database_state_desc s1 FROM sys.dm_hadr_database_replica_states  
where replica_id =(select replica_id from sys.dm_hadr_availability_replica_states where role_desc='PRIMARY')) B  
where A.d1=B.d2