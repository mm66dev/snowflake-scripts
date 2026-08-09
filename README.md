# snowflake-scripts

A collection of Snowflake SQL scripts for recovering configuration, generating DDL/DCL statements, and inspecting role grants.

## Overview

This repository contains reusable Snowflake scripts to help with:
- configuration recovery and export,
- DDL generation for account objects and roles,
- DCL generation for grants and role assignments,
- role-level analysis using anonymous procedures.

## Scripts

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

### `generate-ddl.sql`
- Generates DDL statements for account-level objects and identity objects.
- Includes support for warehouses, network policies, roles, role hierarchy, and users.
- Intended to help reconstruct object definitions in another Snowflake account.

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

