/*
Source: https://learn.microsoft.com/en-us/troubleshoot/azure/synapse-analytics/dedicated-sql/query-execution-performance/dsql-perf-cci-health
Opportunity title	                                        Description	                                     Recommendations
Small table	                                                Table contains fewer than 15M rows	            Consider changing the index from CCI to:
                                                                                                            Heap for staging tables
                                                                                                            Standard clustered index (rowstore) for dimension or other small lookups

Partitioning opportunity or under-partitioned table	        Calculated ideal rowgroup count is greater than 180M (or ~188M rows)	Implement a partitioning strategy or change the existing partitioning strategy to reduce the number of rows per partition to less than 188M (approximately three row groups per partition per distribution)


Over-partitioned table	                                    Table contains fewer than 15M rows for the largest partition	Consider:
                                                                                                                            Changing the index from CCI to standard clustered index (rowstore)
                                                                                                                            Changing the partition grain to be closer to 60M rows per partition


*/

WITH cci_info AS (
    SELECT t.object_id AS [object_id],
          MAX(SCHEMA_NAME(t.schema_id)) AS [schema_name],
          MAX(t.name) AS [table_name],
          rg.partition_number AS [partition_number],
          SUM(rg.[total_rows]) AS [row_count_total],
          CEILING((SUM(rg.[total_rows]) - SUM(rg.[deleted_rows]))/COUNT(DISTINCT rg.distribution_id)/1048576.) * COUNT(DISTINCT rg.distribution_id) AS [ideal_rowgroup_count]
   FROM sys.[pdw_nodes_column_store_row_groups] rg
   JOIN sys.[pdw_nodes_tables] nt ON rg.[object_id] = nt.[object_id]
       AND rg.[pdw_node_id] = nt.[pdw_node_id]
       AND rg.[distribution_id] = nt.[distribution_id]
   JOIN sys.[pdw_table_mappings] mp ON nt.[name] = mp.[physical_name]
   JOIN sys.[tables] t ON mp.[object_id] = t.[object_id]
   GROUP BY t.object_id,
            rg.partition_number
)
SELECT object_id,
       MAX(SCHEMA_NAME),
       MAX(TABLE_NAME),
       COUNT(*) AS number_of_partitions,
       MAX(row_count_total) AS max_partition_row_count,
       MAX(ideal_rowgroup_count) partition_ideal_row_count,
       CASE
           -- non-partitioned tables
           WHEN COUNT(*) = 1 AND MAX(row_count_total) < 15000000 THEN 'Small table'
           WHEN COUNT(*) = 1 AND MAX(ideal_rowgroup_count) > 180 THEN 'Partitioning opportunity'
           -- partitioned tables
           WHEN COUNT(*) > 1 AND MAX(row_count_total) < 15000000 THEN 'Over-partitioned table'
           WHEN COUNT(*) > 1 AND MAX(ideal_rowgroup_count) > 180 THEN 'Under-partitioned table'
       END AS warning_category
FROM cci_info
GROUP BY object_id