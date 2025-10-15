DECLARE @command varchar(4000) 
SELECT @command = 'USE ? .........' 
EXEC sp_MSforeachdb @command 