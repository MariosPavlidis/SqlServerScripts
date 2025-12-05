SELECT DISTINCT DB_NAME(s.database_id) AS database_name,f.name, f.physical_name,type_desc,size *8.0/1024 as [Current MB],d.log_reuse_wait_desc,
cast(growth as nvarchar) + case 
when is_percent_growth=0 then ' MB'
when is_percent_growth=1 then '%'
end growth,
case  
when f.max_size= -1 and growth>0 then 'Until disk full' 
when (f.max_size=-1 or f.max_size=268435456) and growth=0 then 'No Growth'
when f.max_size=268435456 then '2 TB (or disk full!)'
else cast (f.max_size*8.0/1024 as char ) end as [Max MBs],
s.volume_mount_point + ' ('+
s.logical_volume_name +')', s.file_system_type, s.total_bytes /1024/1024/1024 as [Total GBs], s.available_bytes /1024/1024/1024 as [Available GBs],
round(((s.available_bytes*1.0)/s.total_bytes)*100,2) as percent_free, v.io_stall_read_ms,
v.io_stall_write_ms
FROM sys.master_files AS f join sys.databases d on d.database_id=f.database_id
CROSS APPLY sys.dm_os_volume_stats(f.database_id, f.file_id) AS s
CROSS APPLY sys.dm_io_virtual_file_stats (f.database_id,f.file_id) as v
order by [Current MB] desc

