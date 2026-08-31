CREATE OR REPLACE PROCEDURE EXECUTE_SQL_TO_HTML(SQL_TEXT STRING)
RETURNS OBJECT -- Modified to return a unified JSON payload container
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
try {
    // 1. Compile and execute the dynamic SQL query passed as a parameter
    var statement = snowflake.createStatement({sqlText: SQL_TEXT});
    var resultSet = statement.execute();
    
    // 2. Fetch structural metadata to build table columns dynamically
    var columnCount = statement.getColumnCount();
    
    var html =  `<div style="font-family:sans-serif;padding:20px;background:#f8f9fa;">` +
                `<table border="1" cellpadding="10" cellspacing="0" style="border-collapse:collapse;background:white;width:100%;border:1px solid #dee2e6;text-align:left;font-size:13px;">` +
                `<thead style="background:#1d3557;color:white;">` +
                    `<tr>`;
    
    // 3. Construct Table Headers (<th>) dynamically from query metadata
    for (var i = 1; i <= columnCount; i++) {
        var columnName = statement.getColumnName(i);
        html += `<th>${columnName}</th>`;
    }
    
    html +=         `</tr>` +
                `</thead>` +
                `<tbody>`;

    var rowCount = 0; // Tracks the SQLROWCOUNT metric explicitly

    // 4. Process data records dynamically via a column-agnostic iteration loop
    while (resultSet.next()) {
        rowCount++;
        html += `<tr>`;
        
        for (var colIndex = 1; colIndex <= columnCount; colIndex++) {
            var rawValue = resultSet.getColumnValue(colIndex);
            var safeValue = "";
            
            if (rawValue !== null && rawValue !== undefined) {
                // Safely handle special characters to prevent broken layout or HTML breaking
                safeValue = String(rawValue)
                    .replace(/&/g, "&amp;")
                    .replace(/</g, "&lt;")
                    .replace(/>/g, "&gt;");
            } else {
                safeValue = `<span style="color:#aaa;font-style:italic;">NULL</span>`;
            }
            
            html += `<td>${safeValue}</td>`;
        }
        
        html += `</tr>`;
    }

    // 5. Append a descriptive fallback row if the query returns an empty dataset
    if (rowCount === 0) {
        html += `<tr><td colspan="${columnCount}" style="text-align:center;color:#666;font-style:italic;">Query executed successfully, but returned 0 rows.</td></tr>`;
    }

    html += `</tbody></table></div>`;
    
    // 6. Pack and return both metrics together as properties inside a single object
    return {
        "SQLROWCOUNT": rowCount,
        "HTML_OUTPUT": html
    };

} catch (err) {
    // Return structured exception details matching the schema shape
    return {
        "SQLROWCOUNT": -1,
        "HTML_OUTPUT": `<div style="font-family:sans-serif;color:red;padding:10px;border:1px solid red;background:#fff5f5;"><strong>SQL Execution Error:</strong> ${err.message}</div>`
    };
}
$$;

EXECUTE IMMEDIATE $$
DECLARE
    result_payload OBJECT;
    total_rows     NUMBER;
    report_html    STRING;
    select_sql     STRING;
BEGIN
    -- 1. Invoke the multi-return procedure
    select_sql := 'SELECT query_id, user_name FROM TABLE(SNOWFLAKE.INFORMATION_SCHEMA.QUERY_HISTORY()) WHERE execution_status = \'RUNNING\' LIMIT 5';
    CALL EXECUTE_SQL_TO_HTML_V2(select_sql)  INTO :result_payload;
    
    -- 2. Extract properties cleanly into variables
    total_rows  := :result_payload.['SQLROWCOUNT'];
    report_html := :result_payload.['HTML_OUTPUT'];
    
    -- 3. Use your variables independently (Example: Check row count logic)
    IF (total_rows > 0) THEN
        RETURN 'Found ' || total_rows || ' running queries. Content: ' || report_html;
    ELSE
        RETURN 'No active queries to process.';
    END IF;
END;
$$;
