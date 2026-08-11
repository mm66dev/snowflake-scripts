SELECT 
    r.routineschema AS routine_schema, 
    r.routinename AS routine_name, 
    r.routinetype AS routine_type, -- 'P' for Procedure, 'F' for Function
    d.bname AS package_name
FROM 
    syscat.routines r
JOIN 
    syscat.routinedep d ON r.specificname = d.routinename
WHERE 
    d.bname = 'YOUR_PACKAGE_NAME' 
    AND d.btype = 'K'; -- 'K' indicates a Package dependency