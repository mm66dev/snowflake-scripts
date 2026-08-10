-- Maintain backups of DCL account usage views in permanent tables.
-- Creates the target table once and then appends only new rows.
CREATE TABLE IF NOT EXISTS SECURITY_DEMO_DB.PUBLIC.QUERY_HISTORY (
  end_time TIMESTAMP_LTZ,
  query_text TEXT
);

-- Append new query history rows since the last stored end_time.
INSERT INTO SECURITY_DEMO_DB.PUBLIC.QUERY_HISTORY (end_time, query_text)
SELECT END_TIME, QUERY_TEXT
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE END_TIME > COALESCE(
  (SELECT MAX(end_time) FROM SECURITY_DEMO_DB.PUBLIC.QUERY_HISTORY),
  (SELECT MIN(END_TIME) FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY)
);


BEGIN
  LET views CURSOR FOR
    SELECT * FROM (VALUES
      ('GRANTS_TO_ROLES'),
      ('GRANTS_TO_USERS'),
      ('GRANTS_TO_SHARES'),
      ('CALLER_GRANTS_TO_ROLES')
    ) AS t(view_name);

  FOR rec IN views DO
    LET vname VARCHAR := rec.view_name;

    -- Create backup table if missing using source view structure.
    EXECUTE IMMEDIATE '
      CREATE TABLE IF NOT EXISTS SECURITY_DEMO_DB.PUBLIC.' || :vname || ' AS
      SELECT * FROM SNOWFLAKE.ACCOUNT_USAGE.' || :vname || ' LIMIT 0
    ';

    -- Append only rows newer than the latest stored CREATED_ON.
    EXECUTE IMMEDIATE '
      INSERT INTO SECURITY_DEMO_DB.PUBLIC.' || :vname || '
      SELECT *
      FROM SNOWFLAKE.ACCOUNT_USAGE.' || :vname || '
      WHERE CREATED_ON > COALESCE(
        (SELECT MAX(CREATED_ON) FROM SECURITY_DEMO_DB.PUBLIC.' || :vname || '),
        (SELECT MIN(CREATED_ON) FROM SNOWFLAKE.ACCOUNT_USAGE.' || :vname || ')
      )
    ';

  END FOR;
END;
