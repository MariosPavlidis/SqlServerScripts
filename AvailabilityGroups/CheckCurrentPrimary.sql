if(select ars.role_desc from sys.dm_hadr_availability_replica_states ars  
inner join sys.availability_groups ag on ars.group_id = ag.group_id  
where ag.name = 'profitsag'  
and ars.is_local = 1) = 'PRIMARY'  
begin  
Print 'This is Primary Replica Proceeding to Next Step'  
end  
else  
begin  
RAISERROR('This job should not run in Secondary',16,1)  
end