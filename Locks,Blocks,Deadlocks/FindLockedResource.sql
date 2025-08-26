select resource_type,resource_database_id,
resource_description,resource_associated_entity_id ,
request_mode,request_type,request_status, 
request_session_id,request_request_id  
from sys.dm_tran_locks  
where request_session_id in ( 
    select session_id from sys.dm_exec_requests 
    where blocking_session_id >0 
    union 
    select blocking_session_id from sys.dm_exec_requests 
    where blocking_session_id >0)  
and request_status<>'GRANT'


---KEY
SELECT  
sc.name as schema_name,  
so.name as object_name,  
si.name as index_name  
FROM sys.partitions AS p  
JOIN sys.objects as so on  
p.object_id=so.object_id  
JOIN sys.indexes as si on  
p.index_id=si.index_id and  
p.object_id=si.object_id  
JOIN sys.schemas AS sc on  
so.schema_id=sc.schema_id  
WHERE hobt_id = 72057594077380608 ;  
GO


SELECT  
%%lockres%%, *  
FROM Messages (NOLOCK)  
WHERE %%lockres%% = '(292f8c74fa1d)';  
GO

--PAGE
DBCC TRACEON(3604); 
dbcc PAGE(21,1,78,3)

SELECT  
sc.name as schema_name,  
so.name as object_name,  
si.name as index_name  
FROM sys.objects as so  
JOIN sys.indexes as si on  
so.object_id=si.object_id  
JOIN sys.schemas AS sc on  
so.schema_id=sc.schema_id  
WHERE  
so.object_id =  
and si.index_id = ;  
GO