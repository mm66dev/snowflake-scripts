BEGIN
  LET ts VARCHAR := TO_CHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS');

  SHOW DATABASES;
  LET db_cur CURSOR FOR
    SELECT "name" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "kind" = 'STANDARD';

  FOR rec IN db_cur DO
    BEGIN
      LET db_name VARCHAR := rec."name";

      -- Generate full database DDL (recursive - includes all objects)
      EXECUTE IMMEDIATE '
        CREATE OR REPLACE TEMPORARY TABLE temp_ddl AS
        SELECT GET_DDL(''DATABASE'', ''"' || :db_name || '"'', TRUE) AS ddl
      ';

      -- Export to user stage with timestamp
      EXECUTE IMMEDIATE '
        COPY INTO @~/ddl_export/' || :db_name || '_' || :ts || '.sql
        FROM (SELECT ddl FROM temp_ddl)
        FILE_FORMAT = (TYPE = CSV FIELD_DELIMITER = NONE COMPRESSION = NONE)
        OVERWRITE = TRUE
        SINGLE = TRUE
      ';

    EXCEPTION WHEN OTHER THEN NULL;
    END;
  END FOR;

  RETURN 'DDL export completed. Files at @~/ddl_export/';
END;

-- Verify exported files
LIST @~/ddl_export/;

-- List all exports
LIST @~/ddl_export/;

-- Download a specific one
GET @~/ddl_export/SECURITY_DEMO_DB_20260811_143022.sql file:///tmp/;