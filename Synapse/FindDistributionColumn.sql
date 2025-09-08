select name,collation_name,is_nullable from sys.pdw_column_distribution_properties  cdp
    LEFT OUTER JOIN sys.columns c
    ON cdp.[object_id] = c.[object_id]    AND cdp.[column_id] = c.[column_id]
    where distribution_ordinal = 1 and c.object_id=object_id('sch.table')