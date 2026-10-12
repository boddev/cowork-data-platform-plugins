---
name: snowflake-data-assistant
description: |
  Answers business and data questions using the customer's Snowflake account through the Snowflake connector.
  Use when the user asks to "query Snowflake", "look up data in Snowflake", "ask the data warehouse",
  "pull numbers from Snowflake", "search our Snowflake documents", or asks a data question that
  names Snowflake, Cortex, a Snowflake table, or a Snowflake semantic view.
license: MIT
metadata:
  author: boddev
  version: "1.0"
---

# Snowflake Data Assistant

## What This Skill Does

Uses the tools provided by the **Snowflake** connector (the Snowflake-managed MCP server) to answer
questions from governed Snowflake data. The connector runs every call as the signed-in user's Snowflake
role, so the user only sees data they are already allowed to see.

## Workflow

1. **Discover the tools first.** Look at the tools the Snowflake connector exposes. The set is chosen by the
   customer's Snowflake administrator and can include a Cortex Agent, Cortex Analyst (semantic views),
   Cortex Search, a SQL execution tool, or custom procedures. Do not assume a tool exists; use the names you see.
2. **Pick the most governed tool.** Prefer, in this order:
   - a Cortex Agent tool (it orchestrates the other governed tools),
   - a Cortex Analyst tool (natural language to SQL over a semantic view),
   - a Cortex Search tool (for unstructured text and documents),
   - a SQL execution tool only when the user gives an exact query or no other tool fits.
3. **Ask when the request is ambiguous.** If the time period, metric, or entity is unclear, ask one short
   clarifying question before running anything.
4. **Run read-only work.** Never attempt INSERT, UPDATE, DELETE, DROP, ALTER, GRANT, or other changes. If the
   user asks for a change, explain that this connector is for reading data and suggest they use Snowflake directly.
5. **Keep results small.** Tool responses are truncated at about 250 KB. Use narrower queries (specific columns,
   filters, `LIMIT`, aggregations) instead of pulling whole tables.
6. **Present the answer clearly.** Give the answer first, then a short table or bullets, then how it was
   obtained (which tool, and the SQL if one was returned). State the time range and any filters used.
7. **Be honest about failures.** If a call fails, report the error text, say what it likely means (see below),
   and do not invent numbers.

## Common errors and what to tell the user

| Symptom | Likely meaning | Suggest |
| --- | --- | --- |
| 401 / sign-in prompt | The user has not signed in to Snowflake from Cowork, or the session expired | Sign in again when prompted |
| "Insufficient privileges" or tool not found | The user's default Snowflake role lacks access | Ask the Snowflake administrator to grant the MCP access role |
| "No active warehouse" or session fails to start | The user has no `DEFAULT_WAREHOUSE` | Ask the Snowflake administrator to set one |
| Empty or truncated result | Query too broad or result over size limit | Narrow the question |

## Rules

- Never print, store, or ask for passwords, tokens, or client secrets.
- Never present guessed data as fact.
- Treat all returned data as confidential company data; do not copy it to places the user did not ask for.
