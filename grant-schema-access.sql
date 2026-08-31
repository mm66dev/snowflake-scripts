CREATE OR REPLACE TEMPORARY PROCEDURE GRANT_SCHEMA_ACCESS(DATABASE_NAME STRING, SCHEMA_NAME STRING)
  RETURNS STRING
  LANGUAGE SQL
  EXECUTE AS OWNER
AS
$$
DECLARE
  database_identifier STRING;
  schema_identifier STRING;
  write_role_identifier STRING;
  read_role_identifier STRING;
  write_database_role_identifier STRING;
  read_database_role_identifier STRING;
  database_write_role_identifier STRING;
  database_read_role_identifier STRING;
  statement_text STRING;
  grants_text STRING DEFAULT '';
  permission_rows RESULTSET;
BEGIN
  database_identifier := DATABASE_NAME;
  schema_identifier := SCHEMA_NAME;
  write_role_identifier := SCHEMA_NAME || '_RW';
  read_role_identifier := SCHEMA_NAME || '_R';
  write_database_role_identifier := database_identifier || '.' || write_role_identifier;
  read_database_role_identifier := database_identifier || '.' || read_role_identifier;
  database_write_role_identifier := database_identifier || '_RW';
  database_read_role_identifier := database_identifier || '_R';

  CREATE OR REPLACE TEMPORARY TABLE GRANT_SCHEMA_ACCESS_PERMISSION_MAP (
    object_type STRING,
    grant_scope STRING,
    privilege STRING,
    role_suffix STRING
  );

  INSERT INTO GRANT_SCHEMA_ACCESS_PERMISSION_MAP
    (object_type, grant_scope, privilege, role_suffix)
  VALUES
    ('TABLES', 'ALL', 'SELECT, INSERT, UPDATE, DELETE', '_RW'),
    ('TABLES', 'FUTURE', 'SELECT, INSERT, UPDATE, DELETE', '_RW'),
    ('TABLES', 'ALL', 'SELECT', '_R'),
    ('TABLES', 'FUTURE', 'SELECT', '_R'),
    ('VIEWS', 'ALL', 'SELECT', '_RW'),
    ('VIEWS', 'FUTURE', 'SELECT', '_RW'),
    ('VIEWS', 'ALL', 'SELECT', '_R'),
    ('VIEWS', 'FUTURE', 'SELECT', '_R'),
    ('PROCEDURES', 'ALL', 'USAGE', '_RW'),
    ('PROCEDURES', 'FUTURE', 'USAGE', '_RW'),
    ('PROCEDURES', 'ALL', 'USAGE', '_R'),
    ('PROCEDURES', 'FUTURE', 'USAGE', '_R'),
    ('FUNCTIONS', 'ALL', 'USAGE', '_RW'),
    ('FUNCTIONS', 'FUTURE', 'USAGE', '_RW'),
    ('FUNCTIONS', 'ALL', 'USAGE', '_R'),
    ('FUNCTIONS', 'FUTURE', 'USAGE', '_R'),
    ('STAGES', 'ALL', 'USAGE, READ, WRITE', '_RW'),
    ('STAGES', 'FUTURE', 'USAGE, READ, WRITE', '_RW'),
    ('STAGES', 'ALL', 'USAGE, READ', '_R'),
    ('STAGES', 'FUTURE', 'USAGE, READ', '_R');

  statement_text := 'CREATE DATABASE ROLE IF NOT EXISTS ' ||
                    write_database_role_identifier;
  grants_text := grants_text || statement_text || ';' || CHR(10);
  statement_text := 'CREATE DATABASE ROLE IF NOT EXISTS ' ||
                    read_database_role_identifier;
  grants_text := grants_text || statement_text || ';' || CHR(10);

  statement_text := 'GRANT USAGE ON SCHEMA ' || database_identifier || '.' ||
                    schema_identifier || ' TO DATABASE ROLE ' ||
                    write_database_role_identifier;
  grants_text := grants_text || statement_text || ';' || CHR(10);
  statement_text := 'GRANT USAGE ON SCHEMA ' || database_identifier || '.' ||
                    schema_identifier || ' TO DATABASE ROLE ' ||
                    read_database_role_identifier;
  grants_text := grants_text || statement_text || ';' || CHR(10);

  permission_rows := (SELECT object_type, grant_scope, privilege, role_suffix
                      FROM GRANT_SCHEMA_ACCESS_PERMISSION_MAP
                      ORDER BY object_type, grant_scope, role_suffix);

  FOR permission_row IN permission_rows DO
    statement_text := 'GRANT ' || permission_row.privilege || ' ON ' ||
                      permission_row.grant_scope || ' ' || permission_row.object_type ||
                      ' IN SCHEMA ' || database_identifier || '.' || schema_identifier ||
                      ' TO DATABASE ROLE ' || CASE permission_row.role_suffix
                        WHEN '_RW' THEN write_database_role_identifier
                        WHEN '_R' THEN read_database_role_identifier
                      END;
    grants_text := grants_text || statement_text || ';' || CHR(10);
  END FOR;

  statement_text := 'GRANT DATABASE ROLE ' || write_database_role_identifier ||
                    ' TO ROLE ' || database_write_role_identifier;
  grants_text := grants_text || statement_text || ';' || CHR(10);
  statement_text := 'GRANT DATABASE ROLE ' || read_database_role_identifier ||
                    ' TO ROLE ' || database_read_role_identifier;
  grants_text := grants_text || statement_text || ';' || CHR(10);

  RETURN grants_text;
END;
$$;

-- Example:
CALL GRANT_SCHEMA_ACCESS('SAMPLEDB', 'SCHEMA1');