-- All steps for all jobs with subsystem and on-fail actions
SELECT
    j.name                                        AS job_name,
    js.step_id,
    js.step_name,
    js.subsystem,
    js.database_name,
    CASE js.on_success_action
        WHEN 1 THEN 'Quit - Success'
        WHEN 2 THEN 'Quit - Failure'
        WHEN 3 THEN 'Go to next step'
        WHEN 4 THEN 'Go to step ' + CAST(js.on_success_step_id AS VARCHAR)
    END                                           AS on_success,
    CASE js.on_fail_action
        WHEN 1 THEN 'Quit - Success'
        WHEN 2 THEN 'Quit - Failure'
        WHEN 3 THEN 'Go to next step'
        WHEN 4 THEN 'Go to step ' + CAST(js.on_fail_step_id AS VARCHAR)
    END                                           AS on_failure,
    js.retry_attempts,
    js.retry_interval,
    js.output_file_name
FROM msdb.dbo.sysjobs                j
JOIN msdb.dbo.sysjobsteps            js ON j.job_id = js.job_id
ORDER BY j.name, js.step_id;