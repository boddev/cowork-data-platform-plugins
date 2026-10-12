---
name: databricks-data-assistant
description: |
  Answers business and data questions using the customer's Azure Databricks workspace through the Databricks connectors.
  Use when the user asks to "ask Genie", "query Databricks", "look up data in Databricks", "run this SQL on Databricks",
  "pull numbers from the lakehouse", or asks a data question that names Databricks, Genie, Unity Catalog, or a Databricks table.
license: MIT
metadata:
  author: boddev
  version: "1.0"
---

# Azure Databricks Data Assistant

## What This Skill Does

Uses the tools provided by the **Azure Databricks** connectors (Databricks-provided managed MCP servers) to answer
questions from governed Unity Catalog data. Every call runs as the signed-in user, so the user only sees data they
are already allowed to see.

## Workflow

1. **Discover the tools first.** Look at the tools the Databricks connectors expose. Do not assume a tool exists.
2. **Choose the right connector.**
   - **Azure Databricks Genie** (`system.ai.genie_one_mcp`): the default for business questions in plain language.
     Genie resolves business terms and metric definitions and writes the SQL. Use `genie_ask` to start a question,
     and pass the returned `conversation_id` on follow-up questions so Genie keeps the context.
   - **Azure Databricks SQL** (`system.ai.dbsql`, only present if the administrator enabled it): use only when the user
     supplies an exact query to run, or asks to validate SQL. Do not use it to guess at raw table names.
3. **Ask when the request is ambiguous.** If the time period, metric, or entity is unclear, ask one short question first.
4. **Run read-only work.** Do not attempt to create, change, or delete data, tables, or permissions.
5. **Genie answers can take time.** If a response is still in progress, poll for it using the polling tool the connector
   provides rather than re-asking the question.
6. **Present the answer clearly.** Give the answer first, then a short table or bullets, then how it was obtained
   (Genie or SQL, and the SQL if returned) and any source links. State the time range and filters used.
7. **Be honest about failures.** Report the error text, say what it likely means (see below), and do not invent numbers.

## Common errors and what to tell the user

| Symptom | Likely meaning | Suggest |
| --- | --- | --- |
| 401 / sign-in prompt | The user has not signed in to Databricks from Cowork, or the session expired | Sign in again when prompted |
| 403 / permission denied on the MCP | The user lacks `EXECUTE` on the MCP or access to the workspace | Ask the Databricks administrator |
| Data not found / no access to table | Unity Catalog permissions | Ask the data owner for access |
| Timeout or no response | SQL warehouse is starting or busy | Retry in a minute |

## Rules

- Never print, store, or ask for tokens or client secrets.
- Never present guessed data as fact.
- Treat all returned data as confidential company data.
