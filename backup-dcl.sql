---------------------------------------------------------------
-- DCL BACKUP TO USER STAGE (ALL 4 GRANT VIEWS)
-- Saves grants as CSV with date-stamped filenames
-- Keeps 30 rolling copies per view (by file count)
--
-- Source view                  | Output filename
-- -----------------------------|-------------------------------
-- GRANTS_TO_ROLES              | grants_to_roles_YYYY-MM-DD.csv
-- GRANTS_TO_USERS              | grants_to_users_YYYY-MM-DD.csv
-- GRANTS_TO_SHARES             | grants_to_shares_YYYY-MM-DD.csv
-- CALLER_GRANTS_TO_ROLES       | caller_grants_YYYY-MM-DD.csv
---------------------------------------------------------------

BEGIN
  LET today VARCHAR := TO_CHAR(CURRENT_DATE(), 'YYYY-MM-DD');

  ---------------------------------------------------------------
  -- 1. GRANTS_TO_ROLES
  ---------------------------------------------------------------
  EXECUTE IMMEDIATE '
    COPY INTO @~/grants_backup/grants_to_roles_' || :today || '.csv
    FROM (
      SELECT
        ''GRANT_TO_ROLE'' AS category,
        GRANTEE_NAME AS grantee,
        CREATED_ON AS granted_on,
        CASE
          WHEN GRANTED_ON = ''ACCOUNT'' THEN
            ''GRANT '' || PRIVILEGE || '' ON ACCOUNT TO ROLE "'' || GRANTEE_NAME || ''"''
            || CASE WHEN GRANT_OPTION = ''TRUE'' THEN '' WITH GRANT OPTION'' ELSE '''' END || '';''
          WHEN GRANTED_ON = ''ROLE'' THEN
            ''GRANT ROLE "'' || NAME || ''" TO ROLE "'' || GRANTEE_NAME || ''";''
          WHEN GRANTED_ON = ''DATABASE_ROLE'' THEN
            ''GRANT DATABASE ROLE '' || NAME || '' TO ROLE "'' || GRANTEE_NAME || ''";''
          WHEN GRANTED_ON IN (''DATABASE'', ''SCHEMA'', ''TABLE'', ''VIEW'', ''WAREHOUSE'', ''INTEGRATION'', ''STAGE'', ''FUNCTION'', ''PROCEDURE'', ''TASK'', ''NETWORK POLICY'', ''USER'', ''INSTANCE_ROLE'', ''SEQUENCE'', ''PIPE'', ''FILE_FORMAT'', ''STREAM'', ''EXTERNAL TABLE'', ''MATERIALIZED VIEW'') THEN
            ''GRANT '' || PRIVILEGE || '' ON '' || GRANTED_ON || '' '' ||
            CASE
              WHEN TABLE_CATALOG IS NOT NULL AND TABLE_SCHEMA IS NOT NULL AND TABLE_SCHEMA <> ''None'' THEN
                ''"'' || TABLE_CATALOG || ''"."'' || TABLE_SCHEMA || ''"."'' || NAME || ''"''
              WHEN TABLE_CATALOG IS NOT NULL AND (TABLE_SCHEMA IS NULL OR TABLE_SCHEMA = ''None'') THEN
                ''"'' || TABLE_CATALOG || ''"."'' || NAME || ''"''
              ELSE ''"'' || NAME || ''"''
            END
            || '' TO ROLE "'' || GRANTEE_NAME || ''"''
            || CASE WHEN GRANT_OPTION = ''TRUE'' THEN '' WITH GRANT OPTION'' ELSE '''' END || '';''
          ELSE
            ''-- UNSUPPORTED: GRANT '' || PRIVILEGE || '' ON '' || GRANTED_ON || '' '' || NAME || '' TO ROLE "'' || GRANTEE_NAME || ''";''
        END AS dcl
      FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES
      WHERE DELETED_ON IS NULL
    )
    FILE_FORMAT = (TYPE = CSV FIELD_OPTIONALLY_ENCLOSED_BY = ''"'')
    HEADER = TRUE
    OVERWRITE = TRUE
    SINGLE = TRUE
  ';

  ---------------------------------------------------------------
  -- 2. GRANTS_TO_USERS
  ---------------------------------------------------------------
  EXECUTE IMMEDIATE '
    COPY INTO @~/grants_backup/grants_to_users_' || :today || '.csv
    FROM (
      SELECT
        ''ROLE_TO_USER'' AS category,
        "GRANTEE_NAME" AS grantee,
        "CREATED_ON" AS granted_on,
        ''GRANT ROLE "'' || "ROLE" || ''" TO USER "'' || "GRANTEE_NAME" || ''";'' AS dcl
      FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_USERS
      WHERE "DELETED_ON" IS NULL
    )
    FILE_FORMAT = (TYPE = CSV FIELD_OPTIONALLY_ENCLOSED_BY = ''"'')
    HEADER = TRUE
    OVERWRITE = TRUE
    SINGLE = TRUE
  ';

  ---------------------------------------------------------------
  -- 3. GRANTS_TO_SHARES
  ---------------------------------------------------------------
  EXECUTE IMMEDIATE '
    COPY INTO @~/grants_backup/grants_to_shares_' || :today || '.csv
    FROM (
      SELECT
        ''GRANT_TO_SHARE'' AS category,
        SHARE_NAME AS grantee,
        CREATED_ON AS granted_on,
        ''GRANT '' || PRIVILEGE || '' ON '' || GRANTED_ON || '' '' ||
        CASE
          WHEN OBJECT_DATABASE IS NOT NULL AND OBJECT_SCHEMA IS NOT NULL THEN
            ''"'' || OBJECT_DATABASE || ''"."'' || OBJECT_SCHEMA || ''"."'' || OBJECT_NAME || ''"''
          WHEN OBJECT_DATABASE IS NOT NULL THEN
            ''"'' || OBJECT_DATABASE || ''"."'' || OBJECT_NAME || ''"''
          ELSE ''"'' || OBJECT_NAME || ''"''
        END
        || '' TO SHARE "'' || SHARE_NAME || ''";'' AS dcl
      FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_SHARES
      WHERE DELETED_ON IS NULL
    )
    FILE_FORMAT = (TYPE = CSV FIELD_OPTIONALLY_ENCLOSED_BY = ''"'')
    HEADER = TRUE
    OVERWRITE = TRUE
    SINGLE = TRUE
  ';

  ---------------------------------------------------------------
  -- 4. CALLER_GRANTS_TO_ROLES
  ---------------------------------------------------------------
  EXECUTE IMMEDIATE '
    COPY INTO @~/grants_backup/caller_grants_' || :today || '.csv
    FROM (
      SELECT
        ''CALLER_GRANT'' AS category,
        GRANTEE_NAME AS grantee,
        CREATED_ON AS granted_on,
        ''GRANT CALLER '' || PRIVILEGE || '' ON '' || GRANTED_ON || '' '' || NAME || '' TO ROLE "'' || GRANTEE_NAME || ''";'' AS dcl
      FROM SNOWFLAKE.ACCOUNT_USAGE.CALLER_GRANTS_TO_ROLES
      WHERE DELETED_ON IS NULL
    )
    FILE_FORMAT = (TYPE = CSV FIELD_OPTIONALLY_ENCLOSED_BY = ''"'')
    HEADER = TRUE
    OVERWRITE = TRUE
    SINGLE = TRUE
  ';

  ---------------------------------------------------------------
  -- Purge: keep only the newest 30 files per view
  ---------------------------------------------------------------
  LET purge_patterns CURSOR FOR
    SELECT * FROM (VALUES
      ('grants_to_roles_'),
      ('grants_to_users_'),
      ('grants_to_shares_'),
      ('caller_grants_')
    ) AS t(prefix);

  FOR p_rec IN purge_patterns DO
    BEGIN
      LET prefix VARCHAR := p_rec.prefix;
      LIST @~/grants_backup/;
      LET purge_cur CURSOR FOR
        SELECT "name" FROM (
          SELECT "name", ROW_NUMBER() OVER (ORDER BY "name" DESC) AS rn
          FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
          WHERE "name" LIKE '%' || :prefix || '%'
        ) WHERE rn > 30;
      FOR rec IN purge_cur DO
        LET file_name VARCHAR := rec."name";
        EXECUTE IMMEDIATE 'REMOVE @~/' || :file_name;
      END FOR;
    EXCEPTION WHEN OTHER THEN NULL;
    END;
  END FOR;

END;

---------------------------------------------------------------
-- VERIFY: List all backup files
---------------------------------------------------------------
LIST @~/grants_backup/;
remove @~/grants_backup/grants_2026-08-09.csv
