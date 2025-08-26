/* Exec xp_ReadErrorLog  LogNumber, LogType, SearchItem1, StartDate, EndDate, SortOrder

 LogNumber: It is the log number of the error log. You can see the lognumber in the above screenshot. Zero is always referred to as the current log file
 LogType: We can use this command to read both SQL Server error logs and agent logs
 1 – To read the SQL Server error log
 2- To read SQL Agent logs
 SearchItem1: In this parameter, we specify the search keyword
 SearchItem2: We can use additional search items. Both conditions ( SearchItem1 and SearchItem2) should be satisfied with the results
 StartDate and EndDate: We can filter the error log between StartDate and EndDate
 SortOrder: We can specify ASC (Ascending) or DSC (descending) for sorting purposes
*/
DECLARE @logFileType SMALLINT= 1;
DECLARE @start DATETIME;
DECLARE @end DATETIME;
DECLARE @logno INT= 0;
SET @start = cast( dateadd(day,-2,sysdatetime()) as datetime);
SET @end = sysdatetime();
DECLARE @searchString1 NVARCHAR(256)= 'Login Failed';
DECLARE @searchString2 NVARCHAR(256)= '';
EXEC master.dbo.xp_readerrorlog 
     @logno, 
     @logFileType, 
     @searchString1, 
     @searchString2, 
     @start, 
     @end;