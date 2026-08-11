--# This script generates DDL statements for all objects in the account, including databases, schemas, tables, views, roles, users, and more.

BEGIN
  USE DATABASE USER$xxxx;
  CREATE OR REPLACE TEMPORARY TABLE temp_ddl_result (
    scope VARCHAR,
    database_name VARCHAR,
    schema_name VARCHAR,
    object_type VARCHAR,
    object_name VARCHAR,
    ddl TEXT
  );

  ---------------------------------------------------------------
  -- ACCOUNT-LEVEL OBJECTS (GET_DDL-compatible)
  ---------------------------------------------------------------
  LET acct_cur CURSOR FOR
    SELECT * FROM (VALUES
      ('SHOW WAREHOUSES', 'WAREHOUSE', 'WAREHOUSE'),
      ('SHOW NETWORK POLICIES', 'NETWORK_POLICY', 'NETWORK_POLICY')
    ) AS t(show_cmd, ddl_type, label);

  FOR acct_rec IN acct_cur DO
    BEGIN
      LET show_cmd VARCHAR := acct_rec.show_cmd;
      LET ddl_type VARCHAR := acct_rec.ddl_type;
      LET label VARCHAR := acct_rec.label;

      EXECUTE IMMEDIATE :show_cmd;
      LET obj_cur CURSOR FOR SELECT "name" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
      FOR rec IN obj_cur DO
        BEGIN
          LET obj_name VARCHAR := rec."name";
          LET ddl_text VARCHAR := (SELECT GET_DDL(:ddl_type, '"' || :obj_name || '"'));
          INSERT INTO temp_ddl_result VALUES ('ACCOUNT', NULL, NULL, :label, :obj_name, :ddl_text);
        EXCEPTION WHEN OTHER THEN NULL;
        END;
      END FOR;
    EXCEPTION WHEN OTHER THEN NULL;
    END;
  END FOR;

  ---------------------------------------------------------------
  -- ACCOUNT-LEVEL: Roles
  ---------------------------------------------------------------
  SHOW ROLES;
  LET role_cur CURSOR FOR SELECT "name", "comment" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "owner" <> '';
  FOR rec IN role_cur DO
    BEGIN
      LET obj_name VARCHAR := rec."name";
      LET role_comment VARCHAR := rec."comment";
      LET ddl_text VARCHAR := 'CREATE ROLE IF NOT EXISTS "' || :obj_name || '"';
      IF (:role_comment IS NOT NULL AND :role_comment <> '') THEN
        ddl_text := :ddl_text || ' COMMENT = ''' || REPLACE(:role_comment, '''', '''''') || '''';
      END IF;
      ddl_text := :ddl_text || ';';
      INSERT INTO temp_ddl_result VALUES ('ACCOUNT', NULL, NULL, 'ROLE', :obj_name, :ddl_text);
    EXCEPTION WHEN OTHER THEN NULL;
    END;
  END FOR;

  -- Role hierarchy (GRANT ROLE x TO ROLE/USER y)
  SHOW ROLES;
  LET rh_cur CURSOR FOR SELECT "name" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "owner" <> '';
  FOR rec IN rh_cur DO
    BEGIN
      LET obj_name VARCHAR := rec."name";
      EXECUTE IMMEDIATE 'SHOW GRANTS OF ROLE "' || :obj_name || '"';
      LET gh_cur CURSOR FOR SELECT "role", "grantee_name", "granted_to" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
      FOR g_rec IN gh_cur DO
        LET g_role VARCHAR := g_rec."role";
        LET g_grantee VARCHAR := g_rec."grantee_name";
        LET g_type VARCHAR := g_rec."granted_to";
        LET ddl_text VARCHAR := 'GRANT ROLE "' || :g_role || '" TO ' || :g_type || ' "' || :g_grantee || '";';
        INSERT INTO temp_ddl_result VALUES ('ACCOUNT', NULL, NULL, 'ROLE_GRANT', :g_role || ' -> ' || :g_grantee, :ddl_text);
      END FOR;
    EXCEPTION WHEN OTHER THEN NULL;
    END;
  END FOR;

  ---------------------------------------------------------------
  -- ACCOUNT-LEVEL: Users
  ---------------------------------------------------------------
  SHOW USERS;
  LET usr_cur CURSOR FOR SELECT "name", "login_name", "display_name", "email", "default_role", "default_warehouse", "comment" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
  FOR rec IN usr_cur DO
    BEGIN
      LET obj_name VARCHAR := rec."name";
      LET ddl_text VARCHAR := 'CREATE USER IF NOT EXISTS "' || :obj_name || '"';
      LET u_login VARCHAR := rec."login_name";
      LET u_display VARCHAR := rec."display_name";
      LET u_email VARCHAR := rec."email";
      LET u_role VARCHAR := rec."default_role";
      LET u_wh VARCHAR := rec."default_warehouse";
      LET u_comment VARCHAR := rec."comment";
      IF (:u_login IS NOT NULL AND :u_login <> '') THEN
        ddl_text := :ddl_text || ' LOGIN_NAME = ''' || :u_login || '''';
      END IF;
      IF (:u_display IS NOT NULL AND :u_display <> '') THEN
        ddl_text := :ddl_text || ' DISPLAY_NAME = ''' || :u_display || '''';
      END IF;
      IF (:u_email IS NOT NULL AND :u_email <> '') THEN
        ddl_text := :ddl_text || ' EMAIL = ''' || :u_email || '''';
      END IF;
      IF (:u_role IS NOT NULL AND :u_role <> '') THEN
        ddl_text := :ddl_text || ' DEFAULT_ROLE = "' || :u_role || '"';
      END IF;
      IF (:u_wh IS NOT NULL AND :u_wh <> '') THEN
        ddl_text := :ddl_text || ' DEFAULT_WAREHOUSE = "' || :u_wh || '"';
      END IF;
      IF (:u_comment IS NOT NULL AND :u_comment <> '') THEN
        ddl_text := :ddl_text || ' COMMENT = ''' || REPLACE(:u_comment, '''', '''''') || '''';
      END IF;
      ddl_text := :ddl_text || ';';
      INSERT INTO temp_ddl_result VALUES ('ACCOUNT', NULL, NULL, 'USER', :obj_name, :ddl_text);
    EXCEPTION WHEN OTHER THEN NULL;
    END;
  END FOR;

  ---------------------------------------------------------------
  -- ACCOUNT-LEVEL: Resource Monitors
  ---------------------------------------------------------------
  SHOW RESOURCE MONITORS;
  LET rm_cur CURSOR FOR SELECT "name", "credit_quota", "frequency", "start_time" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
  FOR rec IN rm_cur DO
    BEGIN
      LET obj_name VARCHAR := rec."name";
      LET r_quota VARCHAR := rec."credit_quota";
      LET r_freq VARCHAR := rec."frequency";
      LET r_start VARCHAR := rec."start_time";
      LET ddl_text VARCHAR := 'CREATE RESOURCE MONITOR IF NOT EXISTS "' || :obj_name || '" WITH CREDIT_QUOTA = ' || :r_quota || ' FREQUENCY = ' || :r_freq || ' START_TIMESTAMP = ''' || :r_start || ''';';
      INSERT INTO temp_ddl_result VALUES ('ACCOUNT', NULL, NULL, 'RESOURCE_MONITOR', :obj_name, :ddl_text);
    EXCEPTION WHEN OTHER THEN NULL;
    END;
  END FOR;

  ---------------------------------------------------------------
  -- ACCOUNT-LEVEL: Integrations (reconstruct from DESCRIBE)
  ---------------------------------------------------------------
  SHOW INTEGRATIONS;
  LET int_cur CURSOR FOR SELECT "name", "type", "category" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
  FOR rec IN int_cur DO
    BEGIN
      LET obj_name VARCHAR := rec."name";
      LET i_type VARCHAR := rec."type";
      LET i_cat VARCHAR := rec."category";
      LET ddl_text VARCHAR := '-- INTEGRATION: "' || :obj_name || '" TYPE=' || :i_type || ' CATEGORY=' || :i_cat || ' (run: DESCRIBE INTEGRATION "' || :obj_name || '";)';
      INSERT INTO temp_ddl_result VALUES ('ACCOUNT', NULL, NULL, 'INTEGRATION', :obj_name, :ddl_text);
    EXCEPTION WHEN OTHER THEN NULL;
    END;
  END FOR;

  ---------------------------------------------------------------
  -- ACCOUNT-LEVEL: Shares (outbound)
  ---------------------------------------------------------------
  SHOW SHARES;
  LET share_cur CURSOR FOR SELECT "name", "database_name", "kind" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "kind" = 'OUTBOUND';
  FOR rec IN share_cur DO
    BEGIN
      LET obj_name VARCHAR := rec."name";
      LET s_db VARCHAR := rec."database_name";
      LET ddl_text VARCHAR := 'CREATE SHARE IF NOT EXISTS "' || :obj_name || '";';
      IF (:s_db IS NOT NULL AND :s_db <> '') THEN
        ddl_text := :ddl_text || CHR(10) || 'GRANT USAGE ON DATABASE "' || :s_db || '" TO SHARE "' || :obj_name || '";';
      END IF;
      INSERT INTO temp_ddl_result VALUES ('ACCOUNT', NULL, NULL, 'SHARE', :obj_name, :ddl_text);
    EXCEPTION WHEN OTHER THEN NULL;
    END;
  END FOR;

  ---------------------------------------------------------------
  -- ACCOUNT-LEVEL: Compute Pools
  ---------------------------------------------------------------
  BEGIN
    SHOW COMPUTE POOLS;
    LET cp_cur CURSOR FOR SELECT "name", "min_nodes", "max_nodes", "instance_family" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
    FOR rec IN cp_cur DO
      BEGIN
        LET obj_name VARCHAR := rec."name";
        LET cp_min VARCHAR := rec."min_nodes";
        LET cp_max VARCHAR := rec."max_nodes";
        LET cp_family VARCHAR := rec."instance_family";
        LET ddl_text VARCHAR := 'CREATE COMPUTE POOL IF NOT EXISTS "' || :obj_name || '" MIN_NODES = ' || :cp_min || ' MAX_NODES = ' || :cp_max || ' INSTANCE_FAMILY = ' || :cp_family || ';';
        INSERT INTO temp_ddl_result VALUES ('ACCOUNT', NULL, NULL, 'COMPUTE_POOL', :obj_name, :ddl_text);
      EXCEPTION WHEN OTHER THEN NULL;
      END;
    END FOR;
  EXCEPTION WHEN OTHER THEN NULL;
  END;

  ---------------------------------------------------------------
  -- ACCOUNT-LEVEL: External Volumes
  ---------------------------------------------------------------
  BEGIN
    SHOW EXTERNAL VOLUMES;
    LET ev_cur CURSOR FOR SELECT "name" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
    FOR rec IN ev_cur DO
      BEGIN
        LET obj_name VARCHAR := rec."name";
        LET ddl_text VARCHAR := '-- EXTERNAL VOLUME: "' || :obj_name || '" (run: DESCRIBE EXTERNAL VOLUME "' || :obj_name || '";)';
        INSERT INTO temp_ddl_result VALUES ('ACCOUNT', NULL, NULL, 'EXTERNAL_VOLUME', :obj_name, :ddl_text);
      EXCEPTION WHEN OTHER THEN NULL;
      END;
    END FOR;
  EXCEPTION WHEN OTHER THEN NULL;
  END;

  ---------------------------------------------------------------
  -- DCL: GRANTS ON ALL OBJECTS TO ROLES
  ---------------------------------------------------------------
  SHOW ROLES;
  LET grant_role_cur CURSOR FOR SELECT "name" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "owner" <> '';
  FOR rec IN grant_role_cur DO
    BEGIN
      LET role_name VARCHAR := rec."name";
      EXECUTE IMMEDIATE 'SHOW GRANTS TO ROLE "' || :role_name || '"';
      LET g_cur CURSOR FOR
        SELECT "privilege", "granted_on", "name" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "granted_on" <> 'ROLE';
      FOR g_rec IN g_cur DO
        BEGIN
          LET g_priv VARCHAR := g_rec."privilege";
          LET g_on VARCHAR := g_rec."granted_on";
          LET g_obj VARCHAR := g_rec."name";
          LET ddl_text VARCHAR := 'GRANT ' || :g_priv || ' ON ' || :g_on || ' ' || :g_obj || ' TO ROLE "' || :role_name || '";';
          INSERT INTO temp_ddl_result VALUES ('DCL', NULL, NULL, 'GRANT', :role_name || ': ' || :g_priv || ' ON ' || :g_obj, :ddl_text);
        EXCEPTION WHEN OTHER THEN NULL;
        END;
      END FOR;
    EXCEPTION WHEN OTHER THEN NULL;
    END;
  END FOR;

  ---------------------------------------------------------------
  -- DATABASE-LEVEL DDL
  ---------------------------------------------------------------
  SHOW DATABASES;
  LET ddb_cur CURSOR FOR SELECT "name" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "kind" = 'STANDARD';
  FOR rec IN ddb_cur DO
    BEGIN
      LET obj_name VARCHAR := rec."name";
      LET ddl_text VARCHAR := (SELECT GET_DDL('DATABASE', '"' || :obj_name || '"', TRUE));
      INSERT INTO temp_ddl_result VALUES ('DATABASE', :obj_name, NULL, 'DATABASE', :obj_name, :ddl_text);
    EXCEPTION WHEN OTHER THEN NULL;
    END;
  END FOR;

  ---------------------------------------------------------------
  -- SCHEMA-LEVEL OBJECTS (per database, per schema)
  ---------------------------------------------------------------
  SHOW DATABASES;
  LET db_cur CURSOR FOR SELECT "name" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "kind" = 'STANDARD';

  FOR db_rec IN db_cur DO
    LET db_name VARCHAR := db_rec."name";

    EXECUTE IMMEDIATE 'SHOW SCHEMAS IN DATABASE "' || :db_name || '"';
    LET sch_cur CURSOR FOR
      SELECT "name" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "name" <> 'INFORMATION_SCHEMA';

    FOR sch_rec IN sch_cur DO
      LET sch_name VARCHAR := sch_rec."name";
      LET full_schema VARCHAR := '"' || :db_name || '"."' || :sch_name || '"';
      LET fqn_prefix VARCHAR := '"' || :db_name || '"."' || :sch_name || '".';

      LET type_cur CURSOR FOR
        SELECT * FROM (VALUES
          ('SHOW TABLES IN SCHEMA ', 'TABLE', 'TABLE'),
          ('SHOW VIEWS IN SCHEMA ', 'VIEW', 'VIEW'),
          ('SHOW DYNAMIC TABLES IN SCHEMA ', 'DYNAMIC_TABLE', 'DYNAMIC_TABLE'),
          ('SHOW PROCEDURES IN SCHEMA ', 'PROCEDURE', 'PROCEDURE'),
          ('SHOW USER FUNCTIONS IN SCHEMA ', 'FUNCTION', 'FUNCTION'),
          ('SHOW SEQUENCES IN SCHEMA ', 'SEQUENCE', 'SEQUENCE'),
          ('SHOW STREAMS IN SCHEMA ', 'STREAM', 'STREAM'),
          ('SHOW TASKS IN SCHEMA ', 'TASK', 'TASK'),
          ('SHOW PIPES IN SCHEMA ', 'PIPE', 'PIPE'),
          ('SHOW FILE FORMATS IN SCHEMA ', 'FILE_FORMAT', 'FILE_FORMAT'),
          ('SHOW STAGES IN SCHEMA ', 'STAGE', 'STAGE'),
          ('SHOW TAGS IN SCHEMA ', 'TAG', 'TAG'),
          ('SHOW MASKING POLICIES IN SCHEMA ', 'POLICY', 'MASKING_POLICY'),
          ('SHOW ROW ACCESS POLICIES IN SCHEMA ', 'POLICY', 'ROW_ACCESS_POLICY'),
          ('SHOW AGGREGATION POLICIES IN SCHEMA ', 'POLICY', 'AGGREGATION_POLICY'),
          ('SHOW PROJECTION POLICIES IN SCHEMA ', 'POLICY', 'PROJECTION_POLICY'),
          ('SHOW PASSWORD POLICIES IN SCHEMA ', 'POLICY', 'PASSWORD_POLICY'),
          ('SHOW SESSION POLICIES IN SCHEMA ', 'POLICY', 'SESSION_POLICY'),
          ('SHOW EVENT TABLES IN SCHEMA ', 'EVENT_TABLE', 'EVENT_TABLE'),
          ('SHOW NETWORK RULES IN SCHEMA ', 'NETWORK_RULE', 'NETWORK_RULE'),
          ('SHOW ALERTS IN SCHEMA ', 'ALERT', 'ALERT'),
          ('SHOW SECRETS IN SCHEMA ', 'SECRET', 'SECRET')
        ) AS t(show_cmd, ddl_type, label);

      FOR type_rec IN type_cur DO
        LET show_cmd VARCHAR := type_rec.show_cmd;
        LET ddl_type VARCHAR := type_rec.ddl_type;
        LET label VARCHAR := type_rec.label;

        BEGIN
          EXECUTE IMMEDIATE :show_cmd || :full_schema;

          LET obj_cur CURSOR FOR SELECT "name" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
          FOR obj_rec IN obj_cur DO
            BEGIN
              LET obj_name VARCHAR := obj_rec."name";
              LET ddl_text VARCHAR := (SELECT GET_DDL(:ddl_type, :fqn_prefix || '"' || :obj_name || '"'));
              INSERT INTO temp_ddl_result VALUES ('SCHEMA', :db_name, :sch_name, :label, :obj_name, :ddl_text);
            EXCEPTION WHEN OTHER THEN NULL;
            END;
          END FOR;
        EXCEPTION WHEN OTHER THEN NULL;
        END;
      END FOR; -- object types

    END FOR; -- schemas
  END FOR; -- databases


  ---------------------------------------------------------------
  -- RETURN ALL RESULTS
  ---------------------------------------------------------------
  LET result RESULTSET := (SELECT * FROM temp_ddl_result ORDER BY scope, database_name, schema_name, object_type, object_name);
  RETURN TABLE(result);
END;

