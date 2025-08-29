/*
Source : https://learn.microsoft.com/en-us/troubleshoot/azure/synapse-analytics/dedicated-sql/query-execution-performance/dsql-perf-cci-health
Column name	                                Description
tables_assessed_count	                    Count of CCI tables
partitions_assessed_count	                Count of partitions
                                            Note: Non-partitioned tables will be counted as 1.
actual_rowgroup_count	                    Physical count of rowgroups
ideal_rowgroup_count	                    Calculated number of rowgroups that would be ideal for the number of rows
uncompressed_rowgroup_count	                Number of rowgroups that contain uncompressed data. (Also known as: OPEN rows)
actual_size_in_mb	                        Physical size of CCI data in MB
uncompressed_size_in_mb                 	Physical size of uncompressed data in MB
excess_pct                              	Percent of rowgroups that could be further optimized
excess_size_in_mb                       	Estimated MB from unoptimized rowgroups

*/

WITH cci_detail AS (
    SELECT t.object_id,
          rg.partition_number,
          COUNT(*) AS total_rowgroup_count,
          SUM(CASE WHEN rg.state = 1 THEN 1 END) AS open_rowgroup_count,
          CEILING((SUM(rg.[total_rows]) - SUM(rg.deleted_rows))/COUNT(DISTINCT rg.distribution_id)/1048576.) * COUNT(DISTINCT rg.distribution_id) AS [ideal_rowgroup_count],
          SUM(rg.size_in_bytes/1024/1024.) AS size_in_mb,
          SUM(CASE WHEN rg.state = 1 THEN rg.size_in_bytes END /1024/1024.) AS open_size_in_mb
   FROM sys.pdw_nodes_column_store_row_groups rg
   JOIN sys.pdw_nodes_tables nt ON rg.object_id = nt.object_id
       AND rg.pdw_node_id = nt.pdw_node_id
       AND rg.distribution_id = nt.distribution_id
   JOIN sys.pdw_table_mappings mp ON nt.name = mp.physical_name
   JOIN sys.tables t ON mp.object_id = t.object_id
   GROUP BY t.object_id,
            rg.partition_number
)
SELECT COUNT(DISTINCT object_id) AS tables_assessed_count,
       COUNT(*) AS partitions_assessed_count,
       SUM(total_rowgroup_count) AS actual_rowgroup_count,
       SUM(ideal_rowgroup_count) AS ideal_rowgroup_count,
       SUM(open_rowgroup_count) AS uncompressed_rowgroup_count,
       CAST(SUM(size_in_mb) AS DECIMAL(19, 4)) AS actual_size_in_mb,
       CAST(SUM(open_size_in_mb) AS DECIMAL(19, 4)) AS uncompressed_size_in_mb,
       CAST(((SUM(total_rowgroup_count) - SUM(ideal_rowgroup_count)) / SUM(total_rowgroup_count)) * 100. AS DECIMAL(9, 4)) AS excess_pct,
       CAST(((SUM(total_rowgroup_count) - SUM(ideal_rowgroup_count)) / SUM(total_rowgroup_count)) * 1. AS DECIMAL(9, 4)) * SUM(size_in_mb) AS excess_size_in_mb
FROM cci_detail