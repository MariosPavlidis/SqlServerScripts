select
s.Name + N'.' + t.name as [Table]
,i1.index_id as [Index1 ID], i1.name as [Index1 Name]
,dupIdx.index_id as [Index2 ID], dupIdx.name as [Index2 Name]
,c.name as [Column]
from
sys.tables t join sys.indexes i1 on
t.object_id = i1.object_id
join sys.index_columns ic1 on
ic1.object_id = i1.object_id and
ic1.index_id = i1.index_id and
ic1.index_column_id = 1
join sys.columns c on
c.object_id = ic1.object_id and
c.column_id = ic1.column_id
join sys.schemas s on
t.schema_id = s.schema_id
cross apply
(
select i2.index_id, i2.name
from
sys.indexes i2 join sys.index_columns ic2 on
ic2.object_id = i2.object_id and
ic2.index_id = i2.index_id and
ic2.index_column_id = 1
where
i2.object_id = i1.object_id and
i2.index_id > i1.index_id and
ic2.column_id = ic1.column_id
) dupIdx
order by
s.name, t.name, i1.index_id;