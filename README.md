## Overview
This repository contains reusable Snowflake scripts to help with:
- Maintenance DDL scripts
- configuration recovery and export,
- DDL generation for account objects and roles,
- DCL generation for grants and role assignments,
- Various sample anonymouse SQL block code.

## Scripts

## Maintenance DDL scripts

The following objects are defined in `snowflake-maintenance-scripts.ddl`, helps building maintenance scripts.

### Tables
- `ADMIN.UTILS.KV_STORE`: Stores named SQL statements and metadata used by the
  maintenance checks and runner procedures.
- `ADMIN.UTILS.LOG`: Stores timestamped maintenance log entries with a source,
  severity level, and message.

### Functions
- `ADMIN.UTILS.FN_KV_GET(P_KEY)`: Returns the SQL text associated with a key in
  `KV_STORE`.
- `ADMIN.UTILS.FN_ERROR_CONSTRUCT(SQLCODE, SQLSTATE, SQLERRM)`: Packages SQL
  error details into a text representation of an object.

### Stored Procedures
- `ADMIN.UTILS.SP_LOG`: Writes a log entry with a supplied level, message, and
  source.
- `ADMIN.UTILS.SP_LOG_INFO`: Writes an informational log entry through `SP_LOG`.
- `ADMIN.UTILS.SP_LOG_ERROR`: Writes an error log entry through `SP_LOG`.
- `ADMIN.UTILS.SP_LOG_DEBUG`: Writes a debug log entry through `SP_LOG`.
- `ADMIN.UTILS.SP_LOG_WARN`: Writes a warning-level log entry through `SP_LOG`.
- `ADMIN.UTILS.SP_SEND_MAIL`: Sends an HTML email and logs a failure if sending
  fails or required inputs are missing.
- `ADMIN.UTILS.SP_EXECUTE_SQL_TO_HTML`: Executes supplied SQL and returns an
  object containing the row count and an HTML table of the results.
- `ADMIN.UTILS.SP_EXECUTE_SQL_AND_NOTIFY`: Executes supplied SQL, emails an HTML
  report when rows are returned, and logs execution status.
- `ADMIN.UTILS.SP_EXECUTE_SQL_FROM_KV_STORE_AND_NOTIFY`: Looks up SQL by key in
  `KV_STORE` and passes it to the execute-and-notify procedure.

### Tasks
- `ADMIN.UTILS.TASK_LOG_WATCHER`: Sample ten-minute task intended to check recent
  error log entries and send a notification.
- `ADMIN.TASK_LOG_WATCHER`: Sample hourly task intended to run the error-log
  check by key through the `KV_STORE` runner procedure.

### Stored Monitoring Queries
These SQL statements are inserted into `KV_STORE`; inserting them does not
schedule or execute them automatically.
- `SQL-WAREHOUSE-IDLE-USAGE-CHECK`: Summarizes the previous week's warehouse
  credits and estimates idle usage. The script inserts this key twice with
  different credit thresholds.
- `SQL-ERROR-LOG-CHECK`: Selects recent error entries from the maintenance log.
- `SQL-LONG-RUNNING-QUERIES-CHECK`: Finds queries running longer than 30 minutes
  in the recent query history window.
- `SQL-TASKS-SUSPENDED-IN-ADMIN.UTILS-SCHEMA-CHECK`: Lists tasks in
  `ADMIN.UTILS` that are not started.
- `SQL-TABLE-TYPE-SUMMARY-REPORT`: Counts active Iceberg, dynamic, hybrid,
  transient, permanent, and total tables by database.

### Setup Notes
- The DDL contains account-specific notification integration names, recipient
  addresses, warehouse names, and email verification values; review these before
  running it.
- The task examples need validation before use: the SQL and KV key spellings do
  not consistently match the declared table columns and stored keys, and the
  task names being altered do not match the task names created above.
- `SP_LOG_WARN` writes level `WARN`, while the `LOG` table constraint allows
  `WARNING` (not `WARN`).

A collection of Snowflake SQL scripts for recovering configuration, generating DDL/DCL statements, and inspecting role grants.


### `anonymous-SPs.sql`
- Defines a temporary anonymous stored procedure that scans Snowflake roles,
  inspects warehouse-related grants, and returns a summary of role counts.
- Useful for quickly auditing role access patterns across warehouses.

### `backup-config.sql`
- Generates recovery statements for Snowflake account, database, and schema parameters.
- Includes recovery output for network policies and integration objects.
- Designed to create a restore-ready configuration script from an existing environment.

### `generate-dcl.sql`
- Builds DCL recovery statements from the `SNOWFLAKE.ACCOUNT_USAGE` views.
- Produces grant statements for role privileges, user role assignments, share grants,
  and caller grants.
- Useful for exporting current privilege state for audit or restore purposes.

#### DCL source view to CSV file mapping
- `GRANTS_TO_ROLES` → `grants_to_roles_YYYY-MM-DD.csv`
- `GRANTS_TO_USERS` → `grants_to_users_YYYY-MM-DD.csv`
- `GRANTS_TO_SHARES` → `grants_to_shares_YYYY-MM-DD.csv`
- `CALLER_GRANTS_TO_ROLES` → `caller_grants_YYYY-MM-DD.csv`

### `table-based-dcl-backup.sql`
- Maintains table-based backups of Snowflake DCL audit views.
- Creates and appends to backup tables for:
  - `GRANTS_TO_ROLES`
  - `GRANTS_TO_USERS`
  - `GRANTS_TO_SHARES`
  - `CALLER_GRANTS_TO_ROLES`
- Uses `CREATED_ON` delta logic so only new rows are added on each run.

### `find-dcl_ddl_change.sql`
- Detects recent DDL, DCL, and configuration-related query activity from
  `SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY`.
- Helps identify CREATE/ALTER/DROP and GRANT/REVOKE activity in the last 24 hours.
- Useful for triggering backups or change monitoring before recovery operations.

### `generate-ddl.sql`
- Generates DDL statements for account-level objects and identity objects.
- Includes support for warehouses, network policies, roles, role hierarchy, and users.
- Intended to help reconstruct object definitions in another Snowflake account.

### `snowflake-maintenance-scripts.ddl`
- Sets up shared maintenance utilities in `ADMIN.UTILS`, including a key-value store to store meta data 
  for reusable monitoring queries and a log table & procedure to handle messages/errors.
- Provides helper functions and procedures to read stored SQL, execute a query,
  format its results as an HTML table, and email the report when rows are returned.
- Includes stored query definitions for warehouse idle-credit usage, recent logged
  errors, long-running queries, suspended tasks, and table-type counts.
- Includes sample scheduled tasks to demonstrate running checks and recording
  task outcomes. The query definitions are stored in `KV_STORE`; they are not all
  automatically scheduled by this file.
- Before running, review account-specific values and dependencies, including the
  notification integration, recipients, warehouse, schema, and task definitions.
  Treat the task examples as templates and verify their SQL and `KV_STORE` keys
  before resuming them.

## Usage

1. Open your Snowflake worksheet or use `snowsql`.
2. Load the desired `.sql` file.
3. Update any placeholders such as database names, roles, or account-specific values.
4. Execute the script in the target Snowflake account.

## Requirements

- Snowflake account with sufficient privileges to run `SHOW` commands,
  `GET_DDL`, and `SNOWFLAKE.ACCOUNT_USAGE` queries.
- Access to account metadata and configuration information.

## Notes

- Review generated output carefully before applying it in another environment.
- Some scripts may use temporary tables and procedures; adjust naming or scope as needed.
- The `generate-ddl.sql` script may require customized database selection and additional object handling depending on your account.

