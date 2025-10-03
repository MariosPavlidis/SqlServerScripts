select * into dba.vTAbleSizes_20251001
from dbo.vTableSizes


select two_part_name, distribution_column,distribution_policy_name,
max(row_count) as "Max",avg(row_count) as "Avg",min(row_count) as "Min",
 (max(row_count * 1.000) - min(row_count * 1.000))/max(row_count * 1.000) as "Skew",
max(row_count)/avg(row_count) skew2
    from dba.vTAbleSizes_20251001
    where row_count > 1000
    and distribution_policy_name='HASH'
    group by two_part_name,distribution_column,distribution_policy_name    
        order by skew2 desc