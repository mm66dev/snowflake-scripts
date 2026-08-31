WITH anonymous_output_message AS PROCEDURE ()
  RETURNS TABLE(role varchar, count int)
  LANGUAGE SQL
  AS
  $$
DECLARE
  rs_roles RESULTSET;
  rs_wh    RESULTSET;
  stmt VARCHAR;
  ret_result RESULTSET;
  v_role_name VARCHAR;
  v_wh_count  INT;
BEGIN
  CREATE OR REPLACE TEMPORARY TABLE temp_result (role varchar, count int);
  
  rs_roles := (SHOW ROLES);
  
  FOR role IN rs_roles DO
    -- Capture the role name into a scalar variable
    v_role_name := role."name";
    
    -- Format dynamic query
    stmt := 'SHOW GRANTS TO ROLE ##' || v_role_name || '## ->> SELECT count(*) as count from $1 WHERE ##granted_on## = #WAREHOUSE#';
    stmt := replace(replace(stmt,'##','"'),'#','''');
    rs_wh := (EXECUTE IMMEDIATE :stmt);
    
    FOR wh IN rs_wh DO
      v_wh_count := wh.count;
      -- Insert using scalar variables instead of cursor dot-notation
      INSERT INTO temp_result (role, count) VALUES (:v_role_name, :v_wh_count);
    END FOR;
    
  END FOR;

  ret_result := (SELECT * FROM temp_result);
  RETURN TABLE(ret_result);
END;
$$


call anonymous_output_message();