-- =====================================================================================
-- Snowflake setup for the Copilot Cowork Snowflake plugin
-- Run by: a Snowflake ADMINISTRATOR (ACCOUNTADMIN, or a role that can create roles,
--         integrations and MCP servers). Run it in a Snowsight SQL worksheet.
--
-- HOW TO USE THIS FILE (read first):
--   1. Open this file in Notepad. Press Ctrl+H (Find and Replace).
--   2. Replace every <<PLACEHOLDER>> in the table below with your own value ("Replace All").
--      Use UPPERCASE letters, digits and underscores for object names (no spaces, no hyphens).
--   3. Copy the whole file into a Snowsight worksheet. Run the steps ONE AT A TIME,
--      top to bottom, reading the comment above each step.
--
--   PLACEHOLDER             WHAT TO PUT                                   EXAMPLE
--   <<MCP_DATABASE>>        database to hold the MCP server               MCP_DB
--   <<MCP_SCHEMA>>          schema to hold the MCP server                 MCP_SCHEMA
--   <<MCP_SERVER_NAME>>     name for the MCP server                       COWORK_MCP
--   <<AGENT_NAME>>          your Cortex Agent (see STEP 3, Option A)      SALES_AGENT
--   <<WAREHOUSE>>           warehouse that will run queries               COMPUTE_WH
--   <<ACCESS_ROLE>>         NEW role that users get for Cowork            COWORK_MCP_ROLE
--   <<INTEGRATION_NAME>>    name of the OAuth security integration        COWORK_OAUTH
--   <<USER_NAME>>           a Snowflake user to try it with first         JSMITH
--
-- SECURITY NOTE: do not give this role more than it needs. Never grant it to PUBLIC.
-- =====================================================================================

-- STEP 0: Find your account URL (you need it later).  Run this and copy the result.
-- The URL is   https://<result>
SELECT LOWER(CURRENT_ORGANIZATION_NAME() || '-' || REPLACE(CURRENT_ACCOUNT_NAME(), '_', '-'))
       || '.snowflakecomputing.com' AS account_host;

-- STEP 1: Role, warehouse and database access for Cowork users.
USE ROLE ACCOUNTADMIN;
CREATE ROLE IF NOT EXISTS <<ACCESS_ROLE>>;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE <<ACCESS_ROLE>>;
GRANT USAGE ON WAREHOUSE <<WAREHOUSE>> TO ROLE <<ACCESS_ROLE>>;
CREATE DATABASE IF NOT EXISTS <<MCP_DATABASE>>;
CREATE SCHEMA IF NOT EXISTS <<MCP_DATABASE>>.<<MCP_SCHEMA>>;
GRANT USAGE ON DATABASE <<MCP_DATABASE>> TO ROLE <<ACCESS_ROLE>>;
GRANT USAGE ON SCHEMA <<MCP_DATABASE>>.<<MCP_SCHEMA>> TO ROLE <<ACCESS_ROLE>>;

-- STEP 2: (Only if you use Option A below) allow the role to run Cortex Agents.
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE <<ACCESS_ROLE>>;

-- STEP 3: Create the MCP server. Choose ONE option and run only that block.

-- ---- OPTION A (recommended): expose one Cortex Agent --------------------------------
-- Prerequisite: the Cortex Agent <<AGENT_NAME>> already exists in <<MCP_DATABASE>>.<<MCP_SCHEMA>>
-- (or change the identifier below to its real location).
CREATE OR REPLACE MCP SERVER <<MCP_DATABASE>>.<<MCP_SCHEMA>>.<<MCP_SERVER_NAME>>
  FROM SPECIFICATION $$
  tools:
    - title: "Governed business data agent"
      name: "business_data_agent"
      type: "CORTEX_AGENT_RUN"
      identifier: "<<MCP_DATABASE>>.<<MCP_SCHEMA>>.<<AGENT_NAME>>"
      description: "Use this agent for governed business data questions."
  $$;
GRANT USAGE ON AGENT <<MCP_DATABASE>>.<<MCP_SCHEMA>>.<<AGENT_NAME>> TO ROLE <<ACCESS_ROLE>>;
-- The role ALSO needs access to whatever the agent uses. Add the lines that apply, e.g.:
-- GRANT SELECT ON SEMANTIC VIEW <db>.<schema>.<semantic_view> TO ROLE <<ACCESS_ROLE>>;
-- GRANT USAGE ON CORTEX SEARCH SERVICE <db>.<schema>.<service> TO ROLE <<ACCESS_ROLE>>;
-- GRANT SELECT ON TABLE <db>.<schema>.<table> TO ROLE <<ACCESS_ROLE>>;

-- ---- OPTION B: read-only SQL tool (no Cortex Agent needed) ---------------------------
-- Snowflake advises a SQL tool live on its OWN MCP server with a least-privileged role.
-- Only run this if you do not have a Cortex Agent. Then grant SELECT ONLY on the tables
-- you are happy for Cowork users to read.
-- CREATE OR REPLACE MCP SERVER <<MCP_DATABASE>>.<<MCP_SCHEMA>>.<<MCP_SERVER_NAME>>
--   FROM SPECIFICATION $$
--   tools:
--     - title: "Read-only SQL"
--       name: "sql_exec_tool"
--       type: "SYSTEM_EXECUTE_SQL"
--       description: "Run read-only SQL queries against the tables this role can read."
--       config:
--         read_only: true
--         query_timeout: 120
--         warehouse: "<<WAREHOUSE>>"
--   $$;
-- GRANT USAGE ON SCHEMA <your_db>.<your_schema> TO ROLE <<ACCESS_ROLE>>;
-- GRANT SELECT ON TABLE <your_db>.<your_schema>.<your_table> TO ROLE <<ACCESS_ROLE>>;

-- STEP 4: Let the role use the MCP server. (Access to the server does NOT give access to
-- its tools; each tool's objects need their own grants, as in STEP 3.)
GRANT USAGE ON MCP SERVER <<MCP_DATABASE>>.<<MCP_SCHEMA>>.<<MCP_SERVER_NAME>> TO ROLE <<ACCESS_ROLE>>;

-- STEP 5: Create the OAuth security integration that Copilot Cowork signs in through.
-- The redirect URI is fixed by Microsoft and must be exactly this.
CREATE OR REPLACE SECURITY INTEGRATION <<INTEGRATION_NAME>>
  TYPE = OAUTH
  OAUTH_CLIENT = CUSTOM
  ENABLED = TRUE
  OAUTH_CLIENT_TYPE = 'CONFIDENTIAL'
  OAUTH_REDIRECT_URI = 'https://teams.microsoft.com/api/platform/v1.0/oAuthRedirect'
  OAUTH_USE_SECONDARY_ROLES = NONE
  ALLOWED_ROLES_LIST = ('<<ACCESS_ROLE>>');

-- STEP 6: Get the Client ID and Client Secret you will paste into the Teams Developer Portal.
-- The integration name MUST be in UPPERCASE here. TREAT THE SECRET LIKE A PASSWORD.
SELECT SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('<<INTEGRATION_NAME>>');

-- STEP 7: Give users the role and the defaults that Cowork sessions need.
-- Cowork signs in with the user's DEFAULT_ROLE and DEFAULT_WAREHOUSE. If these are not set,
-- the connection fails. Repeat for every user (or use a Snowflake group/SCIM process).
GRANT ROLE <<ACCESS_ROLE>> TO USER <<USER_NAME>>;
ALTER USER <<USER_NAME>> SET DEFAULT_ROLE = '<<ACCESS_ROLE>>' DEFAULT_WAREHOUSE = '<<WAREHOUSE>>';
-- NOTE: this makes the MCP role the user's default role in ALL their Snowflake tools.
-- If that is a problem, see README "Troubleshooting: I do not want to change default roles".

-- STEP 8: Verify.
SHOW MCP SERVERS IN SCHEMA <<MCP_DATABASE>>.<<MCP_SCHEMA>>;
DESCRIBE MCP SERVER <<MCP_DATABASE>>.<<MCP_SCHEMA>>.<<MCP_SERVER_NAME>>;
SHOW SECURITY INTEGRATIONS LIKE '<<INTEGRATION_NAME>>';

-- Your MCP server URL is:
--   https://<account_host from STEP 0>/api/v2/databases/<<MCP_DATABASE>>/schemas/<<MCP_SCHEMA>>/mcp-servers/<<MCP_SERVER_NAME>>
-- (database, schema and server name in the URL: use the same names; the URL host must use hyphens, never underscores.)

-- =====================================================================================
-- OPTIONAL: Microsoft Entra ID (External OAuth) instead of Snowflake OAuth.
-- Only for customers who want Entra to issue the tokens (governance option, README Part 6).
-- Skip this for a standard install. Get your Entra values from your Azure administrator.
-- =====================================================================================
-- CREATE OR REPLACE SECURITY INTEGRATION ENTRA_EXTERNAL_OAUTH
--   TYPE = EXTERNAL_OAUTH
--   ENABLED = TRUE
--   EXTERNAL_OAUTH_TYPE = AZURE
--   EXTERNAL_OAUTH_ISSUER = 'https://sts.windows.net/<ENTRA_TENANT_ID>/'
--   EXTERNAL_OAUTH_JWS_KEYS_URL = 'https://login.microsoftonline.com/<ENTRA_TENANT_ID>/discovery/v2.0/keys'
--   EXTERNAL_OAUTH_AUDIENCE_LIST = ('<APPLICATION_ID_URI_OF_THE_SNOWFLAKE_RESOURCE_APP_IN_ENTRA>')
--   EXTERNAL_OAUTH_TOKEN_USER_MAPPING_CLAIM = 'upn'
--   EXTERNAL_OAUTH_SNOWFLAKE_USER_MAPPING_ATTRIBUTE = 'LOGIN_NAME';
-- ALTER SCHEMA <<MCP_DATABASE>>.<<MCP_SCHEMA>> SET OAUTH_AUTHORIZATION_SERVER = ENTRA_EXTERNAL_OAUTH;
