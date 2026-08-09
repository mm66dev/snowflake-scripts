---------------------------------------------------------------
-- CONFIGURATION RECOVERY: Generate ALTER/CREATE statements
-- for all items in config.sql
---------------------------------------------------------------

BEGIN
  USE DATABASE USER$MM66SFFB;
  CREATE OR REPLACE TEMPORARY TABLE temp_config_recovery (
    scope VARCHAR,
    object_name VARCHAR,
    recovery_ddl TEXT
  );

  ---------------------------------------------------------------
  -- 1. Account parameters (non-default values)
  ---------------------------------------------------------------
  SHOW PARAMETERS IN ACCOUNT;
  INSERT INTO temp_config_recovery
  SELECT
    'ACCOUNT_PARAM',
    "key",
    'ALTER ACCOUNT SET ' || "key" || ' = ' ||
      CASE
        WHEN "type" IN ('Boolean', 'BOOLEAN') THEN "value"
        WHEN "type" IN ('Number', 'NUMBER', 'Integer', 'INT') THEN "value"
        ELSE '''' || REPLACE("value", '''', '''''') || ''''
      END || ';'
  FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
  WHERE "value" != "default";

  ---------------------------------------------------------------
  -- 2. Database-level parameters (non-default)
  ---------------------------------------------------------------
  SHOW DATABASES;
  LET db_cur CURSOR FOR
    SELECT "name" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "kind" = 'STANDARD';
  FOR db_rec IN db_cur DO
    BEGIN
      LET db_name VARCHAR := db_rec."name";
      EXECUTE IMMEDIATE 'SHOW PARAMETERS IN DATABASE "' || :db_name || '"';
      INSERT INTO temp_config_recovery
      SELECT
        'DATABASE_PARAM',
        :db_name || '.' || "key",
        'ALTER DATABASE "' || :db_name || '" SET ' || "key" || ' = ' ||
          CASE
            WHEN "type" IN ('Boolean', 'BOOLEAN') THEN "value"
            WHEN "type" IN ('Number', 'NUMBER', 'Integer', 'INT') THEN "value"
            ELSE '''' || REPLACE("value", '''', '''''') || ''''
          END || ';'
      FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
      WHERE "value" != "default";
    EXCEPTION WHEN OTHER THEN NULL;
    END;
  END FOR;

  ---------------------------------------------------------------
  -- 3. Schema-level parameters (non-default)
  ---------------------------------------------------------------
  SHOW DATABASES;
  LET db_cur2 CURSOR FOR
    SELECT "name" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "kind" = 'STANDARD';
  FOR db_rec IN db_cur2 DO
    BEGIN
      LET db_name VARCHAR := db_rec."name";
      EXECUTE IMMEDIATE 'SHOW SCHEMAS IN DATABASE "' || :db_name || '"';
      LET sch_cur CURSOR FOR
        SELECT "name" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "name" <> 'INFORMATION_SCHEMA';
      FOR sch_rec IN sch_cur DO
        BEGIN
          LET sch_name VARCHAR := sch_rec."name";
          EXECUTE IMMEDIATE 'SHOW PARAMETERS IN SCHEMA "' || :db_name || '"."' || :sch_name || '"';
          INSERT INTO temp_config_recovery
          SELECT
            'SCHEMA_PARAM',
            :db_name || '.' || :sch_name || '.' || "key",
            'ALTER SCHEMA "' || :db_name || '"."' || :sch_name || '" SET ' || "key" || ' = ' ||
              CASE
                WHEN "type" IN ('Boolean', 'BOOLEAN') THEN "value"
                WHEN "type" IN ('Number', 'NUMBER', 'Integer', 'INT') THEN "value"
                ELSE '''' || REPLACE("value", '''', '''''') || ''''
              END || ';'
          FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
          WHERE "value" != "default";
        EXCEPTION WHEN OTHER THEN NULL;
        END;
      END FOR;
    EXCEPTION WHEN OTHER THEN NULL;
    END;
  END FOR;

  ---------------------------------------------------------------
  -- 4. Network policies (GET_DDL)
  ---------------------------------------------------------------
  SHOW NETWORK POLICIES;
  LET np_cur CURSOR FOR SELECT "name" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
  FOR rec IN np_cur DO
    BEGIN
      LET obj_name VARCHAR := rec."name";
      LET ddl_text VARCHAR := (SELECT GET_DDL('NETWORK_POLICY', '"' || :obj_name || '"'));
      INSERT INTO temp_config_recovery VALUES ('NETWORK_POLICY', :obj_name, :ddl_text);
    EXCEPTION WHEN OTHER THEN NULL;
    END;
  END FOR;

  ---------------------------------------------------------------
  -- 5. Integrations (DESCRIBE for reconstruction)
  ---------------------------------------------------------------
  SHOW INTEGRATIONS;
  LET int_cur CURSOR FOR SELECT "name", "type", "category", "enabled" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
  FOR rec IN int_cur DO
    BEGIN
      LET obj_name VARCHAR := rec."name";
      LET i_type VARCHAR := rec."type";
      LET i_cat VARCHAR := rec."category";
      LET i_enabled VARCHAR := rec."enabled";
      LET ddl_text VARCHAR := '-- CREATE ' || :i_cat || ' INTEGRATION "' || :obj_name || '" TYPE = ' || :i_type || ' ENABLED = ' || :i_enabled || '; -- Run DESCRIBE INTEGRATION "' || :obj_name || '" for full properties';
      INSERT INTO temp_config_recovery VALUES ('INTEGRATION', :obj_name, :ddl_text);
    EXCEPTION WHEN OTHER THEN NULL;
    END;
  END FOR;

  ---------------------------------------------------------------
  -- 6. Warehouses (GET_DDL)
  ---------------------------------------------------------------
  SHOW WAREHOUSES;
  LET wh_cur CURSOR FOR SELECT "name" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
  FOR rec IN wh_cur DO
    BEGIN
      LET obj_name VARCHAR := rec."name";
      LET ddl_text VARCHAR := (SELECT GET_DDL('WAREHOUSE', '"' || :obj_name || '"'));
      INSERT INTO temp_config_recovery VALUES ('WAREHOUSE', :obj_name, :ddl_text);
    EXCEPTION WHEN OTHER THEN NULL;
    END;
  END FOR;

  ---------------------------------------------------------------
  -- 7. Replication groups
  ---------------------------------------------------------------
  BEGIN
    SHOW REPLICATION GROUPS;
    LET rg_cur CURSOR FOR SELECT "name", "replication_schedule", "object_types" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
    FOR rec IN rg_cur DO
      BEGIN
        LET obj_name VARCHAR := rec."name";
        LET rg_sched VARCHAR := rec."replication_schedule";
        LET rg_types VARCHAR := rec."object_types";
        LET ddl_text VARCHAR := '-- CREATE REPLICATION GROUP "' || :obj_name || '" OBJECT_TYPES = ' || :rg_types || ' REPLICATION_SCHEDULE = ''' || :rg_sched || ''';';
        INSERT INTO temp_config_recovery VALUES ('REPLICATION_GROUP', :obj_name, :ddl_text);
      EXCEPTION WHEN OTHER THEN NULL;
      END;
    END FOR;
  EXCEPTION WHEN OTHER THEN NULL;
  END;

  ---------------------------------------------------------------
  -- 8. Failover groups
  ---------------------------------------------------------------
  BEGIN
    SHOW FAILOVER GROUPS;
    LET fg_cur CURSOR FOR SELECT "name", "replication_schedule", "object_types" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
    FOR rec IN fg_cur DO
      BEGIN
        LET obj_name VARCHAR := rec."name";
        LET fg_sched VARCHAR := rec."replication_schedule";
        LET fg_types VARCHAR := rec."object_types";
        LET ddl_text VARCHAR := '-- CREATE FAILOVER GROUP "' || :obj_name || '" OBJECT_TYPES = ' || :fg_types || ' REPLICATION_SCHEDULE = ''' || :fg_sched || ''';';
        INSERT INTO temp_config_recovery VALUES ('FAILOVER_GROUP', :obj_name, :ddl_text);
      EXCEPTION WHEN OTHER THEN NULL;
      END;
    END FOR;
  EXCEPTION WHEN OTHER THEN NULL;
  END;

  ---------------------------------------------------------------
  -- RETURN ALL RECOVERY STATEMENTS
  ---------------------------------------------------------------
  LET result RESULTSET := (SELECT * FROM temp_config_recovery ORDER BY scope, object_name);
  RETURN TABLE(result);
END;
