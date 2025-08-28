-- Page Life Expectancy (PLE) value for each NUMA node in current instance  (Query 46) (PLE by NUMA Node)
select @@SERVERNAME AS [Server Name],
(select cntr_value from sys.dm_os_performance_counters where counter_name='Page life expectancy' and object_name like '%Buffer Manager%') as "Current",
cast ((select value_in_use  from sys.configurations where configuration_id=1544) as numeric)/4000.0*300.0 Optimal