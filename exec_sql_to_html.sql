CREATE OR REPLACE PROCEDURE EXECUTE_SQL_TO_HTML(SQL_TEXT STRING)
RETURNS STRING
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
        var safeColumnName = String(columnName)
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/\"/g, "&quot;")
            .replace(/'/g, "&#39;");
        html += `<th>${safeColumnName}</th>`;
    }
    
    html +=         `</tr>` +
                `</thead>` +
                `<tbody>`;

    var hasRows = false;

    // 4. Process data records dynamically via a column-agnostic iteration loop
    while (resultSet.next()) {
        hasRows = true;
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
    if (!hasRows) {
        html += `<tr><td colspan="${columnCount}" style="text-align:center;color:#666;font-style:italic;">Query executed successfully, but returned 0 rows.</td></tr>`;
    }

    html += `</tbody></table></div>`;
    return html;

} catch (err) {
    return `<div style="font-family:sans-serif;color:red;padding:10px;border:1px solid red;background:#fff5f5;">` +
           `<strong>SQL Execution Error:</strong> ${err.message}` +
           `</div>`;
}
$$;

CALL EXECUTE_SQL_TO_HTML('
    SELECT query_id, user_name, warehouse_name 
    FROM TABLE(SNOWFLAKE.INFORMATION_SCHEMA.QUERY_HISTORY()) 
    WHERE execution_status = \'RUNNING\'
');
