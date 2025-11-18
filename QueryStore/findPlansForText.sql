SELECT 
       qsqt.query_sql_text, 
       qsqt.query_text_id, 
       qsp.query_id, 
       qsp.plan_id
   FROM 
       sys.query_store_query_text qsqt
   JOIN 
       sys.query_store_query qsq ON qsqt.query_text_id = qsq.query_text_id
   JOIN 
       sys.query_store_plan qsp ON qsq.query_id = qsp.query_id
   WHERE 
        qsqt.query_sql_text LIKE N'%FROM FIXING_RATE A%';