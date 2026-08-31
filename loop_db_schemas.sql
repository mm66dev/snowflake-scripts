/*
Example to iterate thru databases,schemas and grants
 */
DECLARE
    rs_dbs RESULTSET;
    rs_schemas RESULTSET;
    rs_grants RESULTSET;
    rs_output RESULTSET;
    schema_query STRING; 
    grants_query STRING;
    read_role STRING;
    write_role STRING;
    dbname text;
    schemaname text;
    grantscount INT;
BEGIN
    create temp table if not exists temp_rs(id int identity,dcl_text text);
    rs_dbs := (SHOW DATABASES ->> SELECT "name" AS name FROM $1 WHERE "kind" = 'STANDARD');
    FOR dbrow IN rs_dbs DO
    dbname := dbrow.name;
        schema_query := 'SHOW SCHEMAS IN DATABASE "' || dbrow.name || '" ->> SELECT "name" AS name FROM $1';
        rs_schemas := (EXECUTE IMMEDIATE :schema_query);
        FOR schemarow IN rs_schemas DO
        schemaname :=schemarow.name;
        grants_query := replace('SHOW GRANTS ON SCHEMA ' || dbrow.name || '.' || schemarow.name || ' ->> SELECT count(*) as count FROM $1 WHERE "grantee_name" = #' || schemarow.name || '#','#','''');
            rs_grants := (EXECUTE IMMEDIATE  :grants_query);
            FOR grantsrow IN rs_grants DO
                grantscount := grantsrow.count;
                insert into temp_rs(dcl_text) values ( :dbname || '.' || :schemaname || '=' || :grantscount);
            END FOR;
        END FOR;
    END FOR;
    rs_output := (select * from temp_rs order by id);
    return table(rs_output);
END;

