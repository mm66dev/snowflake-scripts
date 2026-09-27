--#This is snowflake related DDL
USE ROLE ACCOUNTADMIN;
-- #Create Notification integration for email alerts
CREATE NOTIFICATION INTEGRATION IF NOT EXISTS SFDBA_NOTIFICATION_INTEGRATION
TYPE = EMAIL
ENABLED = TRUE
ALLOWED_RECIPIENTS = ('abc@xyz.com')
COMMENT = 'Email notification integration for Snowflake DBAs';

-- #Start email verification
CALL SYSTEM$START_USER_EMAIL_VERIFICATION('abc');

-#Send test email
begin
    CALL SYSTEM$SEND_EMAIL( 'SNOWFLAKE_ADMIN_ALERTS', 'abc@xyz.com'
end;

-#Create required tables, functions & procedures to help log/email from maintenance tasks.

-- #LOG Table
CREATE ICEBERG TABLE IF NOT EXISTS ADMIN.UTILS.LOG(
    TS TIMESTAMP_NTZ(6) DEFAULT CURRENT_TIMESTAMP(6),
    SOURCE VARCHAR,
    LEVEL VARCHAR,
    MESSAGE VARCHAR,
    CONSTRAINT CHK_LEVEL CHECK (LEVEL IN ('INFO','WARNING','ERROR','DEBUG'))
)
ICEBERG_VERSION = 2
CATALOG = 'SNOWFLAKE';


-- #Stringify exception/error attributes
CREATE OR REPLACE FUNCTION ADMIN.UTILS.FN_ERROR_CONSTRUCT(_SQLCODE INTEGER, _SQLSTATE VARCHAR, _SQLERRM VARCHAR)
RETURNS TEXT LANGUAGE SQL
AS
$$
    OBJECT_CONSTRUCT_KEEP_NULL('sqlcode', _SQLCODE, 'sqlerrm', _SQLERRM, 'sqlstate', _SQLSTATE)::TEXT
$$;

--#Generic SP to log messages into ADMIN.UTILS.LOG
CREATE OR REPLACE PROCEDURE ADMIN.UTILS.SP_LOG(_LEVEL VARCHAR DEFAULT 'INFO', _MESSAGE VARCHAR DEFAULT 'NA',  _SOURCE VARCHAR DEFAULT 'NA')
RETURNS BOOLEAN LANGUAGE SQL
AS
$$
BEGIN
    INSERT INTO ADMIN.UTILS.LOG(SOURCE, LEVEL, MESSAGE)     VALUES (:_SOURCE, :_LEVEL, :_MESSAGE);
END;
$$;


--#To log informational messages
CREATE OR REPLACE PROCEDURE ADMIN.UTILS.SP_LOG_INFO(MESSAGE VARCHAR DEFAULT 'NA', SOURCE VARCHAR DEFAULT 'NA')
RETURNS BOOLEAN LANGUAGE SQL
AS
$$
BEGIN
    CALL ADMIN.UTILS.SP_LOG('INFO', :MESSAGE, :SOURCE);
END;
$$;

--#To log error messages
CREATE OR REPLACE PROCEDURE ADMIN.UTILS.SP_LOG_ERROR( MESSAGE VARCHAR DEFAULT 'NA',  SOURCE VARCHAR DEFAULT 'NA')
RETURNS BOOLEAN  LANGUAGE SQL
AS
$$
BEGIN
    CALL ADMIN.UTILS.SP_LOG('ERROR', :MESSAGE, :SOURCE);
END;
$$;

--#To log debug messages
CREATE OR REPLACE PROCEDURE ADMIN.UTILS.SP_LOG_DEBUG( MESSAGE VARCHAR DEFAULT 'NA', SOURCE VARCHAR DEFAULT 'NA')
RETURNS BOOLEAN LANGUAGE SQL
AS
$$
BEGIN
    CALL ADMIN.UTILS.SP_LOG('DEBUG', :MESSAGE, :SOURCE);
END;
$$;

-- #To log warning messages
CREATE OR REPLACE PROCEDURE ADMIN.UTILS.SP_LOG_WARN( MESSAGE VARCHAR DEFAULT 'NA', SOURCE VARCHAR DEFAULT 'NA')
RETURNS BOOLEAN LANGUAGE SQL
AS
$$
BEGIN
    CALL ADMIN.UTILS.SP_LOG('WARN', MESSAGE, SOURCE);
END;
$$;


-- #Standard proc To send email notifications
CREATE OR REPLACE PROCEDURE ADMIN.UTILS.SP_SEND_MAIL(SUBJECT VARCHAR DEFAULT NULL, BODY VARCHAR DEFAULT NULL )
RETURNS BOOLEAN LANGUAGE SQL
AS
$$
DECLARE
    v_environment TEXT DEFAULT current_account_name();
    v_email_notification_integration TEXT DEFAULT 'SNOWFLAKE_DBA_ALERTS_TEMP';
    v_recipients TEXT := 'sf-dba@myco.com';
    v_proc_name TEXT DEFAULT 'ADMIN.UTILS.SP_SEND_MAIL';
BEGIN
    -- Check if inputs are valid
    IF (SUBJECT IS NOT NULL AND BODY IS NOT NULL) THEN
        CALL SYSTEM$SEND_EMAIL( v_email_notification_integration, v_recipients, v_environment || ':' || SUBJECT, BODY, 'text/html' );
        RETURN TRUE;
    ELSE
        CALL ADMIN.UTILS.SP_LOG_ERROR('Failed to send mail: SUBJECT or BODY was NULL.', v_proc_name);
        RETURN FALSE;
    END IF;
EXCEPTION 
    WHEN OTHER THEN
        CALL ADMIN.UTILS.SP_LOG_ERROR('SYSTEM$SEND_EMAIL crashed: ' || SQLERRM, v_proc_name);
        RETURN FALSE;
END;
$$;

-- CALL ADMIN.UTILS.SP SEND MAIL('Test subject', 'Test email body');
CREATE OR REPLACE ICEBERG TABLE ADMIN.UTILS.KV_STORE(
    KEY VARCHAR PRIMARY KEY,
    VALUE TEXT,
    UPDATED_AT TIMESTAMP_NTZ(6) DEFAULT CURRENT_TIMESTAMP(6),
    UPDATED_BY VARCHAR DEFAULT CURRENT_USER()
)
ICEBERG_VERSION = 2
CATALOG = 'SNOWFLAKE';

--#Get value for key from KV_STORE
CREATE OR REPLACE FUNCTION ADMIN.UTILS.FN_KV_GET(P_KEY VARCHAR)
RETURNS VARCHAR LANGUAGE SQL
AS
$$
    SELECT VALUE FROM ADMIN.UTILS.KV_STORE WHERE KEY = P_KEY
$$;

DELETE FROM ADMIN.UTILS.KV_STORE;
-- # WAREHOUSE IDLE USAGE CHECK FOR EVERY WEEK
INSERT INTO ADMIN.UTILS.KV_STORE(KEY, VALUE) VALUES
('SQL-WAREHOUSE-IDLE-USAGE-CHECK', $$
SELECT 
    warehouse_name, 
    SUM(credits_used) AS credits_used, 
    SUM(credits_used_compute) AS credits_used_compute,
    SUM(credits_used_cloud_services) AS credits_used_cloud_services, 
    SUM(credits_used_compute) - SUM(credits_attributed_compute_queries) AS idle_cost,
    100 - (SUM(credits_attributed_compute_queries) / SUM(credits_used) * 100) AS idle_percentage
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time >= DATEADD(DAYS, -7, CURRENT_DATE())
  AND end_time < CURRENT_DATE()
GROUP BY warehouse_name
HAVING SUM(credits_used) > 0
ORDER BY idle_percentage DESC;
$$);


-- # SQL ERROR LOG CHECK FOR EVERY 10 MINS
INSERT INTO ADMIN.UTILS.KV_STORE(KEY, VALUE) VALUES
('SQL-ERROR-LOG-CHECK', $$
SELECT FROM ADMIN.UTILS.LOG WHERE SEVERITY = 'ERROR' AND TS >= DATEADD(MINUTE, -10, CURRENT_TIMESTAMP()) LIMIT 100
$$);

-- # SQL LONG RUNNING QUERIES CHECK FOR EVERY HOUR OR SO
INSERT INTO ADMIN.UTILS.KV_STORE(KEY, VALUE) VALUES
('SQL-LONG-RUNNING-QUERIES-CHECK', $$
SELECT 
    query_id, 
    query_text, 
    user_name, 
    role_name, 
    execution_status AS status, 
    start_time,
    DATEDIFF(MINUTE, start_time, CURRENT_TIMESTAMP()) AS elapsed_time_min, 
    bytes_scanned, 
    rows_produced,
    compilation_time / 1000 AS compilation_secs,
    queued_overload_time / 1000 AS queued_overload_secs,
    queued_provisioning_time / 1000 AS queued_provisioning_secs,
    transaction_blocked_time / 1000 AS blocked_secs, -- Fixed: Added missing comma
    query_type, 
    session_id, 
    cluster_number,
    warehouse_name, 
    warehouse_size
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY( -- Fixed: Fixed dots/spaces
    END_TIME_RANGE_START => DATEADD(HOUR, -24, CURRENT_TIMESTAMP()), -- Fixed: Added underscores
    RESULT_LIMIT => 10000
))
-- Fixed: Used the full DATEDIFF expression instead of the alias name
WHERE DATEDIFF(MINUTE, start_time, CURRENT_TIMESTAMP()) > 30 
  AND execution_status NOT IN ('SUCCESS', 'FAILED') 
ORDER BY elapsed_time_min DESC;
$$);

-- # WAREHOUSE IDLE USAGE CHECK FOR EVERY WEEK
INSERT INTO ADMIN.UTILS.KV_STORE(KEY, VALUE) VALUES
('SQL-WAREHOUSE-IDLE-USAGE-CHECK', $$
SELECT 
    warehouse_name, 
    SUM(credits_used) AS credits_used, 
    SUM(credits_used_compute) AS credits_used_compute,
    SUM(credits_used_cloud_services) AS credits_used_cloud_services, 
    SUM(credits_used_compute) - SUM(credits_attributed_compute_queries) AS idle_cost,
    100 - (SUM(credits_attributed_compute_queries) / SUM(credits_used) * 100) AS idle_percentage
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time >= DATEADD(DAYS, -7, CURRENT_DATE())
  AND end_time < CURRENT_DATE()
GROUP BY warehouse_name
HAVING SUM(credits_used) > 7
ORDER BY idle_percentage DESC;
$$);

-- # TASKS SUSPENDED IN ADMIN.UTILS SCHEMA CHECK FOR EVERY DAY
INSERT INTO ADMIN.UTILS.KV_STORE(KEY, VALUE) VALUES
('SQL-TASKS-SUSPENDED-IN-ADMIN.UTILS-SCHEMA-CHECK',$$
SHOW TASKS IN ADMIN.UTILS ->> SELECT "name", "state", "schedule" FROM $1 WHERE "state" != 'started';
$$);


-- # TABLE TYPE SUMMARY REPORT
INSERT INTO ADMIN.UTILS.KV_STORE(KEY, VALUE) VALUES
('SQL-TABLE-TYPE-SUMMARY-REPORT',$$
SELECT
    TABLE_CATALOG AS DATABASE_NAME,
    COUNT_IF(IS_ICEBERG = 'YES') AS ICEBERG_COUNT,
    COUNT_IF(IS_DYNAMIC = 'YES') AS DYNAMIC_COUNT,
    COUNT_IF(IS_HYBRID = 'YES') AS HYBRID_COUNT,
    COUNT_IF(IS_TRANSIENT = 'YES') AS TRANSIENT_COUNT,
    -- A permanent table is one where none of the specialized extensions or transient flags apply
    COUNT_IF(
        IS_ICEBERG = 'NO' AND 
        IS_DYNAMIC = 'NO' AND 
        IS_HYBRID = 'NO' AND 
        (IS_TRANSIENT = 'NO' OR IS_TRANSIENT IS NULL)
    ) AS PERMANENT_COUNT,
    COUNT(*) AS TOTAL_COUNT
FROM SNOWFLAKE.ACCOUNT_USAGE.TABLES -- Fixed: Removed the space
WHERE DELETED IS NULL
GROUP BY TABLE_CATALOG;
$$);


CREATE OR REPLACE PROCEDURE ADMIN.UTILS.SP_EXECUTE_SQL_TO_HTML(sql_text VARCHAR)
RETURNS OBJECT
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    -- Fixed: Named all variables properly and removed formatting typos
    proc_name VARCHAR DEFAULT 'ADMIN.UTILS.SP_EXECUTE_SQL_TO_HTML';
    html VARCHAR DEFAULT '';
    row_count NUMBER DEFAULT 0;
    col_count NUMBER DEFAULT 0;
    qid VARCHAR;
    col_names ARRAY DEFAULT ARRAY_CONSTRUCT();
    rs_query VARCHAR;
    cname VARCHAR;
    cval VARCHAR;
    escaped VARCHAR;
    res RESULTSET;
    err_message VARCHAR;
BEGIN -- Fixed: Added the mandatory BEGIN block
    CALL ADMIN.UTILS.SP_LOG_INFO('Starting', proc_name);
    
    -- 1. Execute the dynamic SQL
    EXECUTE IMMEDIATE sql_text;
    qid := LAST_QUERY_ID();

    -- Get row count reliably (SQLROWCOUNT is NULL for SELECT statements)
    SELECT COUNT(*) INTO row_count FROM TABLE(RESULT_SCAN(qid));

    -- 2. Early return if no rows
    IF (row_count < 1) THEN
        RETURN OBJECT_CONSTRUCT(
            'SQLROWCOUNT', row_count,
            'HTML_OUTPUT', '<table border="1"><tr><td>No rows returned.</td></tr></table>'
        );
    END IF;

    -- 3. Get column names via DESCRIBE RESULT
    EXECUTE IMMEDIATE 'DESCRIBE RESULT ' || CHR(39) || qid || CHR(39);
    SELECT ARRAY_AGG("name") INTO col_names FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
    col_count := ARRAY_SIZE(col_names);

    -- 4. Build table header
    html := '<table border="1"><tr>';
    FOR i IN 0 TO col_count - 1 DO
        -- Fixed: Removed extra colons and spaces in type casting
        html := html || '<th>' || GET(col_names, i)::VARCHAR || '</th>';
    END FOR;
    html := html || '</tr>';

    -- 5. Build table rows via RESULTSET
    rs_query := 'SELECT OBJECT_CONSTRUCT(*) AS rdata FROM TABLE(RESULT_SCAN(' || CHR(39) || qid || CHR(39) || '))';
    res := (EXECUTE IMMEDIATE rs_query);
    
    DECLARE
        c1 CURSOR FOR res;
    BEGIN
        FOR rec IN c1 DO
            html := html || '<tr>';
            FOR i IN 0 TO col_count - 1 DO
                cname := GET(col_names, i)::VARCHAR;
                cval := GET(rec.rdata, cname)::VARCHAR;
                
                IF (cval IS NULL) THEN
                    html := html || '<td>NULL</td>';
                ELSE
                    -- Fixed: Fixed the &lt; typo and removed incorrect colon prefixes
                    escaped := REPLACE(REPLACE(REPLACE(cval, '&', '&amp;'), '<', '&lt;'), '>', '&gt;');
                    html := html || '<td>' || escaped || '</td>';
                END IF;
            END FOR;
            html := html || '</tr>';
        END FOR;
    END;

    html := html || '</table>';
    
    CALL ADMIN.UTILS.SP_LOG_INFO('Completed, SQLROWCOUNT: ' || row_count, proc_name);
    RETURN OBJECT_CONSTRUCT_KEEP_NULL('SQLROWCOUNT', row_count, 'HTML_OUTPUT', html);

EXCEPTION
    WHEN OTHER THEN
        -- Fixed: Reordered arguments to perfectly match your (SQLCODE, SQLSTATE, SQLERRM) UDF definition
        err_message := ADMIN.UTILS.FN_ERROR_CONSTRUCT(SQLCODE, SQLSTATE, SQLERRM);
        CALL ADMIN.UTILS.SP_LOG_ERROR(err_message, proc_name);
        
        RETURN OBJECT_CONSTRUCT_KEEP_NULL(
            'SQLROWCOUNT', -1, 
            'HTML_OUTPUT', '<table><tr><td>Error: ' || SQLERRM || '</td></tr></table>'
        );
END;
$$;

CREATE OR REPLACE PROCEDURE ADMIN.UTILS.SP_EXECUTE_SQL_AND_NOTIFY(
    SQL_DESC VARCHAR, 
    SQL_TEXT TEXT
)
RETURNS BOOLEAN
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    -- Fixed: Added names to all variables and removed internal typos
    v_proc_name VARCHAR DEFAULT 'ADMIN.UTILS.SP_EXECUTE_SQL_AND_NOTIFY';
    result_payload OBJECT;
    total_rows NUMBER;
    report_html VARCHAR;
    err_message VARCHAR;
BEGIN -- Fixed: Added the mandatory BEGIN wrapper
    CALL ADMIN.UTILS.SP_LOG_INFO('Starting ' || SQL_DESC, v_proc_name);
    
    -- Fixed: Removed unnecessary colons from the CALL statement
    CALL ADMIN.UTILS.SP_EXECUTE_SQL_TO_HTML(SQL_TEXT) INTO result_payload;
    
    -- Extract values from the object payload using standard variant dot notation
    total_rows := result_payload.SQLROWCOUNT;
    report_html := result_payload.HTML_OUTPUT;
    
    CALL ADMIN.UTILS.SP_LOG_INFO('Rows found: ' || total_rows, v_proc_name);
    
    -- Send email only if rows exist to report (Fixed: Removed colon)
    IF (total_rows > 0) THEN
        CALL ADMIN.UTILS.SP_SEND_MAIL(SQL_DESC || ' Notification', report_html);
    END IF;
    
    -- Fixed: Restructured the broken string concatenation operator bars
    CALL ADMIN.UTILS.SP_LOG_INFO('Completed ' || SQL_DESC, v_proc_name);
    RETURN TRUE;

EXCEPTION
    WHEN OTHER THEN
        -- Fixed: Reordered arguments to perfectly match your UDF: (SQLCODE, SQLSTATE, SQLERRM)
        err_message := ADMIN.UTILS.FN_ERROR_CONSTRUCT(SQLCODE, SQLSTATE, SQLERRM);
        
        -- Fixed: Fixed the concatenation bars and removed colons
        CALL ADMIN.UTILS.SP_LOG_ERROR('SQL_TEXT: ' || SQL_TEXT, v_proc_name);
        CALL ADMIN.UTILS.SP_LOG_ERROR(err_message, v_proc_name);
        RETURN FALSE;
END;
$$;

CREATE OR REPLACE PROCEDURE ADMIN.UTILS.SP_EXECUTE_SQL_FROM_KV_STORE_AND_NOTIFY(P_KEY VARCHAR)
RETURNS BOOLEAN
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    -- Fixed: Removed the colon prefix during string declaration
    v_proc_name VARCHAR DEFAULT 'ADMIN.UTILS.SP_EXECUTE_SQL_FROM_KV_STORE_AND_NOTIFY:' || P_KEY;
    sql_text TEXT;
    err_message VARCHAR;
BEGIN
    CALL ADMIN.UTILS.SP_LOG_INFO('Starting', v_proc_name);
    
    -- Fixed: Evaluated the scalar UDF directly without the SELECT wrapper
    sql_text := ADMIN.UTILS.FN_KV_GET(P_KEY);
    
    -- Fixed: Repaired the broken string concatenation operator bars
    CALL ADMIN.UTILS.SP_LOG_INFO('Executing: ' || sql_text, v_proc_name);
    
    -- Fixed: Removed colons from the procedure call parameters
    CALL ADMIN.UTILS.SP_EXECUTE_SQL_AND_NOTIFY(P_KEY, sql_text);
    
    CALL ADMIN.UTILS.SP_LOG_INFO('Completed', v_proc_name);
    RETURN TRUE;

EXCEPTION
    WHEN OTHER THEN
        -- Fixed: Reordered arguments to perfectly match your UDF: (SQLCODE, SQLSTATE, SQLERRM)
        err_message := ADMIN.UTILS.FN_ERROR_CONSTRUCT(SQLCODE, SQLSTATE, SQLERRM);
        
        CALL ADMIN.UTILS.SP_LOG_ERROR('sql_text: ' || sql_text, v_proc_name);
        CALL ADMIN.UTILS.SP_LOG_ERROR(err_message, v_proc_name);
        RETURN FALSE;
END;
$$;

-- #SCHEDULE TASKS
CREATE OR REPLACE TASK ADMIN.UTILS.SP_TEST1
WAREHOUSE = DEFAULT_WH
SCHEDULE = 'USING CRON */10 * * * * America/New_York'
SUSPEND_TASK_AFTER_NUM_FAILURES = 3
COMMENT = ''

DECLARE
task_name
sql_desc
sql_text
sp_rc
BEGIN
    -- # Make the following Changes for every task
    sql_desc := 'Error messages in ADMIN.UTILS.LOG Table';
    sql_text := 'SELECT *
    FROM ADMIN.UTILS.LOG
    WHERE SEVERITY = 'ERROR'' AND TS >= DATEADD(MINUTE, -10, CURRENT_TIMESTAMP())
    LIMIT 100';
    -- # End of Changes
    CALL ADMIN.UTILS.SP_LOG_INFO('Starting', :task_name);
    CALL ADMIN.UTILS.SP_EXECUTE_SQL_AND_NOTIFY(:sql_desc, :sql_text) INTO :sp_rc;
    IF (sp_rc = TRUE) THEN
    CALL ADMIN.UTILS.SP_LOG_INFO('Completed', :task_name );
    ELSE
    CALL ADMIN.UTILS.SP_LOG_ERROR('Failed', :task_name);
    END IF;
EXCEPTION
WHEN OTHER THEN
let message := ADMIN.UTILS.FN_ERROR_CONSTRUCT(SQLCODE, SQLERRM, SQLSTATE);
CALL ADMIN.UTILS.SP_LOG_ERROR(:message, :task_name);
END;
ALTER TASK ADMIN.UTILS.SP_TEST1 RESUME;

CREATE OR REPLACE TASK ADMIN.UTILS.SP_TEST2
WAREHOUSE = DEFAULT_WH
SCHEDULE = 'USING CRON 0 * * * * America/New_York'
SUSPEND_TASK_AFTER_NUM_FAILURES = 3
COMMENT = 'Tasks that run hourly via cron'
AS
$$
DECLARE
    task_name VARCHAR DEFAULT 'SQL-ERROR-LOG-CHECK';
    sp_rc     BOOLEAN DEFAULT FALSE; -- Fixed: Changed to BOOLEAN to match procedure return
BEGIN
    CALL ADMIN.UTILS.SP_LOG_INFO('Starting', task_name);
    
    -- Fixed: Replaced undefined variable with the literal KV-Store key string
    CALL ADMIN.UTILS.SP_EXECUTE_SQL_FROM_KV_STORE_AND_NOTIFY('SQL_ERROR_LOG_CHECK') INTO sp_rc;
    
    IF (sp_rc = TRUE) THEN
        CALL ADMIN.UTILS.SP_LOG_INFO('Completed', task_name);
    ELSE
        CALL ADMIN.UTILS.SP_LOG_ERROR('Failed', task_name);
    END IF;

EXCEPTION
    WHEN OTHER THEN
        -- Fixed: Reordered arguments to perfectly match your UDF: (SQLCODE, SQLSTATE, SQLERRM)
        LET message := ADMIN.UTILS.FN_ERROR_CONSTRUCT(SQLCODE, SQLSTATE, SQLERRM);
        CALL ADMIN.UTILS.SP_LOG_ERROR(message, task_name);
END; -- Fixed: Completed the execution block properly
$$;

ALTER TASK ADMIN.UTILS. SP_TEST2 RESUME;