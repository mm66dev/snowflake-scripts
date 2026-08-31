---------------------------------------------------------------
-- DCL RECOVERY SCRIPT
-- Sources: SNOWFLAKE.ACCOUNT_USAGE views
--   1. GRANTS_TO_ROLES   - privilege grants on objects to roles
--   2. GRANTS_TO_USERS   - role grants to users
--   3. GRANTS_TO_SHARES  - grants to outbound shares
--   4. CALLER_GRANTS_TO_ROLES - caller grants (restricted callers rights)
---------------------------------------------------------------

BEGIN
  USE DATABASE USER$xxx;
  CREATE OR REPLACE TEMPORARY TABLE temp_dcl_result (
    category VARCHAR,
    grantee VARCHAR,
    granted_on TIMESTAMP_LTZ,
    dcl TEXT
  );

  ---------------------------------------------------------------
  -- 1. GRANTS_TO_ROLES: Privilege grants on objects
  ---------------------------------------------------------------
  INSERT INTO temp_dcl_result
  SELECT
    'GRANT_TO_ROLE',
    GRANTEE_NAME,
    CREATED_ON,
    CASE
      WHEN GRANTED_ON = 'ACCOUNT' THEN
        'GRANT ' || PRIVILEGE || ' ON ACCOUNT TO ROLE "' || GRANTEE_NAME || '"'
        || CASE WHEN GRANT_OPTION = 'TRUE' THEN ' WITH GRANT OPTION' ELSE '' END || ';'
      WHEN GRANTED_ON = 'ROLE' THEN
        'GRANT ROLE "' || NAME || '" TO ROLE "' || GRANTEE_NAME || '";'
      WHEN GRANTED_ON = 'DATABASE_ROLE' THEN
        'GRANT DATABASE ROLE ' || NAME || ' TO ROLE "' || GRANTEE_NAME || '";'
      WHEN GRANTED_ON IN ('DATABASE', 'SCHEMA', 'TABLE', 'VIEW', 'WAREHOUSE', 'INTEGRATION', 'STAGE', 'FUNCTION', 'PROCEDURE', 'TASK', 'NETWORK POLICY', 'USER', 'INSTANCE_ROLE', 'SEQUENCE', 'PIPE', 'FILE_FORMAT', 'STREAM', 'EXTERNAL TABLE', 'MATERIALIZED VIEW') THEN
        'GRANT ' || PRIVILEGE || ' ON ' || GRANTED_ON || ' ' ||
        CASE
          WHEN TABLE_CATALOG IS NOT NULL AND TABLE_SCHEMA IS NOT NULL AND TABLE_SCHEMA <> 'None' THEN
            '"' || TABLE_CATALOG || '"."' || TABLE_SCHEMA || '"."' || NAME || '"'
          WHEN TABLE_CATALOG IS NOT NULL AND (TABLE_SCHEMA IS NULL OR TABLE_SCHEMA = 'None') THEN
            '"' || TABLE_CATALOG || '"."' || NAME || '"'
          ELSE '"' || NAME || '"'
        END
        || ' TO ROLE "' || GRANTEE_NAME || '"'
        || CASE WHEN GRANT_OPTION = 'TRUE' THEN ' WITH GRANT OPTION' ELSE '' END || ';'
      ELSE
        '-- UNSUPPORTED: GRANT ' || PRIVILEGE || ' ON ' || GRANTED_ON || ' ' || NAME || ' TO ROLE "' || GRANTEE_NAME || '";'
    END
  FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES
  WHERE DELETED_ON IS NULL
    AND GRANTEE_NAME NOT IN ('ACCOUNTADMIN', 'SECURITYADMIN', 'SYSADMIN', 'USERADMIN', 'PUBLIC');

  ---------------------------------------------------------------
  -- 2. GRANTS_TO_USERS: Role assignments to users
  ---------------------------------------------------------------
  INSERT INTO temp_dcl_result
  SELECT
    'ROLE_TO_USER',
    "GRANTEE_NAME",
    "CREATED_ON",
    'GRANT ROLE "' || "ROLE" || '" TO USER "' || "GRANTEE_NAME" || '";'
  FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_USERS
  WHERE "DELETED_ON" IS NULL;

  ---------------------------------------------------------------
  -- 3. GRANTS_TO_SHARES: Grants on objects to outbound shares
  ---------------------------------------------------------------
  INSERT INTO temp_dcl_result
  SELECT
    'GRANT_TO_SHARE',
    SHARE_NAME,
    CREATED_ON,
    'GRANT ' || PRIVILEGE || ' ON ' || GRANTED_ON || ' ' ||
    CASE
      WHEN OBJECT_DATABASE IS NOT NULL AND OBJECT_SCHEMA IS NOT NULL THEN
        '"' || OBJECT_DATABASE || '"."' || OBJECT_SCHEMA || '"."' || OBJECT_NAME || '"'
      WHEN OBJECT_DATABASE IS NOT NULL THEN
        '"' || OBJECT_DATABASE || '"."' || OBJECT_NAME || '"'
      ELSE '"' || OBJECT_NAME || '"'
    END
    || ' TO SHARE "' || SHARE_NAME || '";'
  FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_SHARES
  WHERE DELETED_ON IS NULL;

  ---------------------------------------------------------------
  -- 4. CALLER_GRANTS_TO_ROLES: Restricted caller grants
  ---------------------------------------------------------------
  INSERT INTO temp_dcl_result
  SELECT
    'CALLER_GRANT',
    GRANTEE_NAME,
    CREATED_ON,
    'GRANT CALLER ' || PRIVILEGE || ' ON ' || GRANTED_ON || ' ' || NAME || ' TO ROLE "' || GRANTEE_NAME || '";'
  FROM SNOWFLAKE.ACCOUNT_USAGE.CALLER_GRANTS_TO_ROLES
  WHERE DELETED_ON IS NULL;

  ---------------------------------------------------------------
  -- RETURN ORDERED RESULTS
  ---------------------------------------------------------------
  LET result RESULTSET := (SELECT * FROM temp_dcl_result ORDER BY granted_on);
  RETURN TABLE(result);
END;



