# Snowflake Data Connector for Microsoft Copilot Cowork

Connects Microsoft 365 Copilot Cowork to your **Snowflake account (hosted on Azure)** using the
**Snowflake-managed MCP server**. Snowflake runs that server for you inside your account, so there is nothing
to deploy or host.

> **How to use this guide:** do the Parts in order (1, 2, 3, 4, 5). Each step says who does it, what to click or run, and what you should see
> when it worked. If a step does not match what you see, stop and go to [Part 7: Troubleshooting](#part-7-troubleshooting).
> Do not skip the "You should see" checks; they save hours later.

---

## Contents

- [What this plugin does and does not do](#what-this-plugin-does-and-does-not-do)
- [How it works (one minute)](#how-it-works-one-minute)
- [Part 1: Before you start](#part-1-before-you-start)
- [Part 2: Snowflake setup (Snowflake administrator)](#part-2-snowflake-setup-snowflake-administrator)
- [Part 3: Register the sign-in with Microsoft (Teams Developer Portal)](#part-3-register-the-sign-in-with-microsoft-teams-developer-portal)
- [Part 4: Build and upload the plugin](#part-4-build-and-upload-the-plugin)
- [Part 5: Test it](#part-5-test-it)
- [Part 6: Azure governance options and the "separate URL" question](#part-6-azure-governance-options-and-the-separate-url-question)
- [Part 7: Troubleshooting](#part-7-troubleshooting)
- [Part 8: Updating, rotating secrets, removing](#part-8-updating-rotating-secrets-removing)
- [Appendix: Values cheat sheet](#appendix-values-cheat-sheet)

---

## What this plugin does and does not do

**It gives Copilot Cowork access to whatever your Snowflake administrator chooses to expose through one MCP server.** The tool types Snowflake supports are:

| Tool type | What Cowork can do with it |
| --- | --- |
| Cortex Agent (`CORTEX_AGENT_RUN`) | Ask business questions; the agent picks the right Snowflake resources. **Recommended.** |
| Cortex Analyst (`CORTEX_ANALYST_MESSAGE`) | Turn a question into SQL over a *semantic view*. |
| Cortex Search (`CORTEX_SEARCH_SERVICE_QUERY`) | Search unstructured text and documents. |
| SQL execution (`SYSTEM_EXECUTE_SQL`) | Run SQL. Configured **read-only** in the provided script. |
| Custom tools (`GENERIC`) | Call specific stored procedures or functions. |

**It does not:**

- Bypass Snowflake security. Every call runs **as the signed-in user** with their Snowflake role. If the role cannot see a table, Cowork cannot see it.
- Write data (the provided setup is read-only).
- Work from Cowork on a phone (Microsoft does not support custom plugins in Cowork mobile).
- Expose more than 50 tools per MCP server, or return more than about 250 KB per tool response.

## How it works (one minute)

```
 User in Copilot Cowork
        |  (1) asks a data question
        v
 This plugin (skill + connector)  --(2) signs the user in via OAuth-->  Snowflake OAuth
        |                                                                   |
        |  (3) calls the Snowflake-managed MCP server with the user's token |
        v                                                                   v
 https://<your-account>.snowflakecomputing.com/api/v2/databases/<DB>/schemas/<SCHEMA>/mcp-servers/<NAME>
        |
        v
 Cortex Agent / Analyst / Search / SQL  -> runs as the user's role -> answer returns to Cowork
```

There are **three separate systems** to configure, which is why this guide has several Parts:

| System | What you configure | Part |
| --- | --- | --- |
| Snowflake | MCP server, a role, an OAuth "security integration" | 2 |
| Microsoft Teams Developer Portal | An "OAuth client registration" that stores the Snowflake client ID and secret safely | 3 |
| Microsoft 365 admin center | Upload the plugin ZIP | 4 |

---

## Part 1: Before you start

### 1.1 People you need

| Role | Needed for | Typical person |
| --- | --- | --- |
| **Snowflake administrator** (can use `ACCOUNTADMIN` or equivalent) | Part 2 | Data platform admin |
| **Person who can use the Teams Developer Portal** with the work account that will own the plugin | Part 3 | IT / developer |
| **Microsoft 365 administrator** (Global Admin or Teams/Apps admin who can upload custom apps) | Part 4 | M365 admin |
| **Windows PC** with PowerShell (built in on Windows 10/11) | Part 4 | Whoever does Part 4 |

One person can do all of it if they hold all the permissions.

### 1.2 Requirements checklist (tick each one)

- [ ] Your organization has **Microsoft 365 Copilot with Cowork** available, and custom plugins/apps may be uploaded by your admin.
- [ ] You have a Snowflake account on **Azure** and can sign in to **Snowsight** (the Snowflake web UI) as an administrator.
- [ ] You know which data Cowork users should reach (a Cortex Agent, a semantic view, a search service, or specific tables).
- [ ] You have downloaded this repository. On GitHub click the green **Code** button, then **Download ZIP**, then right-click the ZIP in Windows and choose **Extract All**. Do the work from the extracted `snowflake-plugin` folder.
- [ ] If your Snowflake account uses a **network policy**, you know who can change it (see [Part 7, problem 6](#part-7-troubleshooting)).

### 1.3 Time

About 45 minutes the first time, if all permissions are in hand.

---

## Part 2: Snowflake setup (Snowflake administrator)

**Goal:** create the MCP server and a Snowflake OAuth integration, and collect three values: the **MCP URL**, the **Client ID** and the **Client Secret**.

### Step 2.1: Fill in the setup script

1. Open `admin\snowflake-setup.sql` in **Notepad**.
2. Read the table at the top. Press **Ctrl + H** and replace each `<<PLACEHOLDER>>` with your values (click **Replace All** for each).
   Use **UPPERCASE letters, digits and underscores** only for names.
3. Decide **Option A** (Cortex Agent, recommended) or **Option B** (read-only SQL tool, no agent needed) in STEP 3 of the script. Leave the other one commented out.
4. Save the file.

> **You should see:** no `<<` characters left anywhere in the file. (Press Ctrl + F and search for `<<` to be sure.)

### Step 2.2: Run the script in Snowsight

1. Sign in to Snowsight. Click **Projects**, then **Worksheets**, then the **+** button to create a SQL worksheet.
2. Paste the contents of your edited script.
3. Run it **one step at a time**: select just the lines of one step and press **Ctrl + Enter** (or the blue Run button). Read the output after each step.

> **You should see:** each statement finishes with "Statement executed successfully" (or a result grid for the `SELECT`s).
> If a step errors, do not continue; see [Part 7](#part-7-troubleshooting).

### Step 2.3: Write down your MCP URL

STEP 0 of the script returned your account host, for example `myorg-myaccount.snowflakecomputing.com`.

Build the MCP URL from it:

```
https://<account_host>/api/v2/databases/<MCP_DATABASE>/schemas/<MCP_SCHEMA>/mcp-servers/<MCP_SERVER_NAME>
```

Example:

```
https://myorg-myaccount.snowflakecomputing.com/api/v2/databases/MCP_DB/schemas/MCP_SCHEMA/mcp-servers/COWORK_MCP
```

> **Hyphens, not underscores, in the host name.** Snowflake MCP servers fail to connect if the *host* contains an underscore. If your account name has
> an underscore (`MY_ACCOUNT`), the host uses a hyphen (`my-account`). The script's STEP 0 already converts this for you.
> Underscores in the *database, schema and server names* after `/databases/` are fine.

**Write this URL down. You need it in Part 3 and Part 4.**

### Step 2.4: Get the Client ID and Client Secret

STEP 6 of the script returns a JSON block. Copy these two values into a safe place (a password manager, **not** email or chat):

- `OAUTH_CLIENT_ID`
- `OAUTH_CLIENT_SECRET`

Also note your account host from Step 2.3. The Snowflake sign-in addresses are derived from it:

| Item | Value |
| --- | --- |
| Authorization endpoint | `https://<account_host>/oauth/authorize` |
| Token endpoint | `https://<account_host>/oauth/token-request` |

### Step 2.5: Check that every Cowork user is set up

Cowork signs each user in with their **default role** and **default warehouse** (STEP 7 of the script). For **each** person who will use the plugin:

- They must have been granted your access role (`GRANT ROLE ... TO USER ...`).
- Their `DEFAULT_ROLE` must be that role, and their `DEFAULT_WAREHOUSE` must not be empty.

> **Why this matters:** the most common reason a first sign-in "works" but every tool call fails is a missing default warehouse or a default role without
> access to the MCP server.

---

## Part 3: Register the sign-in with Microsoft (Teams Developer Portal)

**Goal:** give Microsoft the Snowflake client ID and secret so it can sign users in. Microsoft stores them safely and hands you back a short
**registration ID**. The plugin ZIP contains only that ID, never the secret.

### Step 3.1: Open the portal

1. Go to **https://dev.teams.microsoft.com/tools** and sign in with your work account.
2. Click **OAuth client registration** (under **Tools**).
3. Click **Register client** (or **New OAuth client registration** if you already have some).

### Step 3.2: Fill in the form exactly as below

| Field | What to enter |
| --- | --- |
| Registration name | `Snowflake MCP` |
| Base URL | Your **MCP URL** from Step 2.3 (the full address) |
| Restrict usage by org | **My organization only** (recommended for a customer install) |
| Restrict usage by app | **Any Teams app** |
| Client ID | `OAUTH_CLIENT_ID` from Step 2.4 |
| Client secret | `OAUTH_CLIENT_SECRET` from Step 2.4 |
| Authorization endpoint | `https://<account_host>/oauth/authorize` |
| Token endpoint | `https://<account_host>/oauth/token-request` |
| Refresh endpoint | `https://<account_host>/oauth/token-request` (same as the token endpoint) |
| Scope | `session:role:all` |
| Enable PKCE | Leave **on** (the default) |

> **Critical:** *Restrict usage by app* must be **Any Teams app**. If it is tied to one app ID, the sign-in appears to succeed and then every tool
> call fails with a **404**.

### Step 3.3: Save

Click **Save**.

### Step 3.4: Copy the registration ID

After saving, the portal shows an **OAuth client registration ID** (a code of letters and numbers). Copy it.

> **You should see:** a single code with no spaces. **This is not the client secret.** Write the registration ID down next to your MCP URL.

You now have the two values the plugin builder needs:

| Value | From |
| --- | --- |
| MCP URL | Step 2.3 |
| OAuth client registration ID | Step 3.4 |

> The redirect address `https://teams.microsoft.com/api/platform/v1.0/oAuthRedirect` is already set in Snowflake by STEP 5 of the script. It is the same for every
> customer and must match exactly, including the capital **A** in `oAuthRedirect`.

---

## Part 4: Build and upload the plugin

### Step 4.1: Build the ZIP

1. Open the extracted `snowflake-plugin` folder in File Explorer.
2. Click the address bar at the top, type `powershell`, press **Enter**. A blue PowerShell window opens in that folder.
3. Paste this and press **Enter**:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\build-plugin.ps1
   ```

   (The `-ExecutionPolicy Bypass` part avoids the "running scripts is disabled" error and only applies to this one command.)
4. When asked, paste your **MCP URL** (Step 2.3) and then your **OAuth client registration ID** (Step 3.4). Press **Enter** after each.

> **You should see:** a green `SUCCESS`, and a file at `snowflake-plugin\dist\snowflake-cowork-plugin.zip`.
> If you see a red `PROBLEM:` line, read the message; it says exactly what to fix. Nothing is built until all checks pass.

### Step 4.2: Upload to your organization

1. Sign in to the **Microsoft 365 admin center** (https://admin.microsoft.com) as an administrator.
2. Go to **Settings**, then **Integrated apps** (or **Manage apps**), and choose **Upload custom app**.
3. Choose the ZIP `snowflake-cowork-plugin.zip`.
4. Choose who gets it (a test group first is wise), then confirm.

> Menu names move around as Microsoft updates the admin center. Look for "Upload custom app" under Integrated apps / Manage apps.
> If you cannot find it, search the admin center for "custom app" or ask your Microsoft 365 administrator.

> **You should see:** the upload is accepted with no validation errors, and the plugin appears under **Discover** in Cowork for the people you chose
> (this can take a little while).
> If the upload is rejected, copy the exact error and see [Part 7, problem 1](#part-7-troubleshooting).

### Step 4.3 (alternative, for a quick test by one person)

Developers can sideload the ZIP for themselves with the Microsoft 365 Agents Toolkit CLI:

```powershell
npm install -g @microsoft/m365agentstoolkit-cli
atk auth login m365
atk install --file-path "C:\path\to\snowflake-cowork-plugin.zip" --scope Personal
```

---

## Part 5: Test it

Do this as a normal user who has been through Step 2.5.

1. Open **Copilot Cowork**.
2. Go to **Sources & Skills**, then **Plugins**, find **Snowflake Data Connector**, and make sure it is turned on.
3. In a Cowork chat type: `Use the Snowflake connector and list the tools you can use.`
   - **You should see:** a **sign-in window** for Snowflake the first time. Sign in with your normal Snowflake credentials and approve the consent screen.
   - **You should see:** Cowork lists the tools you exposed (for example `business_data_agent`).
4. Ask a real question, for example: `Using Snowflake, how many rows are in <a table the role can read>?`
   - **You should see:** an answer with the tool used and the SQL, if one was returned.
5. Ask something the user should **not** be allowed to see.
   - **You should see:** a permission error from Snowflake. That proves security is being enforced.

If any test fails, go to [Part 7](#part-7-troubleshooting).

---

## Part 6: Azure governance options and the "separate URL" question

This is the part that confuses people, so here is the short version:

> **Do I need a different URL because Snowflake is on Azure?**
> **No.** A Snowflake account on Azure still uses its normal `https://<account_host>.snowflakecomputing.com/...` MCP address. That is the only URL the standard
> install (Option A) uses.
>
> **You use a different URL only if you choose to add Azure in front of Snowflake for extra governance (Option B), or to switch sign-in to Microsoft Entra ID (Option C).**

| | Option A: Direct (standard) | Option B: Azure API Management in front | Option C: Microsoft Entra ID sign-in |
| --- | --- | --- | --- |
| URL Cowork calls | Snowflake MCP URL | **Your API Management (APIM) gateway URL** (a *separate URL*) | Snowflake MCP URL |
| Who signs users in | Snowflake OAuth | Snowflake OAuth (passed through APIM) | Microsoft Entra ID |
| Governance gained | Snowflake roles and grants | Central rate limits, IP filtering, logging, a single enterprise gateway | One corporate identity, Conditional Access, Entra audit |
| Effort | Lowest | Medium | Highest |
| Use when | Snowflake RBAC is enough | Your security team requires all AI traffic through an Azure gateway | Your security team requires Entra-issued tokens |

**Start with Option A.** It is the supported default, is the simplest, and Snowflake's role-based access control already limits what each user can do.
Move to B or C only if your security team requires it. You can do B and C together.

### Option B: Azure API Management (APIM) in front of Snowflake

APIM can expose and govern an existing remote MCP server. Requirements and limits from Microsoft: the backend must be MCP version 2025-06-18 or newer
(Snowflake supports 2025-11-25), and APIM supports tools but not MCP prompts (Snowflake supports tools only, so this is fine).

1. Do Parts 2 and 3 first so a direct connection works. **Test Option A before adding APIM** so you know the base setup is good.
2. In the **Azure portal**, open your APIM instance, then **APIs**, then **MCP servers**, then **+ Create MCP server**, then **Expose an existing MCP server**.
3. **MCP server base URL:** your Snowflake MCP URL from Step 2.3. **Transport type:** Streamable HTTP.
4. Give it a name and a **Base path**, then **Create**.
5. Copy the **Server URL** that APIM shows for the new MCP server. **This is the separate URL.**
6. Make sure the `Authorization` header from Cowork reaches Snowflake. APIM forwards headers by default; if you add a policy that removes it, Snowflake returns `401`.
7. Optional policy examples (MCP server, then **Policies**): rate limits and IP filtering. Cowork sends the header `User-Agent: copilot-cowork/1.0`, which you can use to identify its traffic in logs.

   ```xml
   <inbound>
       <base />
       <rate-limit-by-key calls="60" renewal-period="60" counter-key="@(context.Request.IpAddress)" />
   </inbound>
   ```

8. **Do not** read `context.Response.Body` in a policy, and set Application Insights "Number of payload bytes to log" for the response to **0** at the global scope.
   Either one breaks MCP streaming.
9. In the Teams Developer Portal registration (Step 3.2), change **Base URL** to the **APIM Server URL**. Leave the Snowflake authorization, token and refresh endpoints unchanged.
10. When you run the builder in Step 4.1, paste the **APIM Server URL**. The script will warn that the address is not `*.snowflakecomputing.com`; type `YES` to continue.

### Option C: Microsoft Entra ID instead of Snowflake OAuth

Snowflake supports binding MCP servers to an External OAuth provider such as Entra ID. Users then sign in with their normal Microsoft work account.
This needs your **Azure/Entra administrator**, because it involves two Entra app registrations:

1. In Entra, register a **resource app** that represents Snowflake and exposes the scopes your Snowflake roles map to, and a **client app** whose redirect URI is
   `https://teams.microsoft.com/api/platform/v1.0/oAuthRedirect`.
2. In Snowflake, create an `EXTERNAL_OAUTH` security integration for Entra and bind it with
   `ALTER SCHEMA <db>.<schema> SET OAUTH_AUTHORIZATION_SERVER = <integration>;`. See the commented section at the bottom of `admin\snowflake-setup.sql`.
3. In the Teams Developer Portal (Step 3.2) use the Entra endpoints instead:

   | Field | Value |
   | --- | --- |
   | Authorization endpoint | `https://login.microsoftonline.com/<TENANT_ID>/oauth2/v2.0/authorize` |
   | Token endpoint | `https://login.microsoftonline.com/<TENANT_ID>/oauth2/v2.0/token` |
   | Refresh endpoint | `https://login.microsoftonline.com/<TENANT_ID>/oauth2/v2.0/token` |
   | Scope | the scope(s) from your resource app, plus `offline_access` |

4. **Have an Entra administrator grant consent for the scope before you go live.** Microsoft's own guidance warns that a scope that cannot be consented to still
   saves successfully and later fails with "Need admin approval".
5. Microsoft Entra does not support dynamic client registration and the connector has no Entra-specific type, so the OAuth registration in Part 3 is always required.

Snowflake notes that when External OAuth is bound, **only** tokens from that integration are accepted for the MCP server; Snowflake OAuth tokens are rejected.

### PrivateLink and network restrictions (any option)

- **Copilot Cowork is a Microsoft cloud service.** It cannot reach a Snowflake **PrivateLink** address (`*.privatelink.snowflakecomputing.com`). Use the **public** MCP URL in the plugin.
  If your account uses PrivateLink, ask Snowflake support/your Snowflake team to set `USE_PRIVATELINK_FOR_AUTHORIZATION_ENDPOINT = TRUE` on the OAuth integration, so that
  user sign-in goes to the private address while token requests stay on the public one.
- If you have a Snowflake **network policy**, the token request and the MCP calls come from **Microsoft's servers**, not from the user's PC. Your policy must allow those
  source addresses. Ask your Microsoft contact for the current outbound addresses; they change over time, so do not hard-code a list from the internet.
  See [Part 7, problem 6](#part-7-troubleshooting).
- If Snowflake is replicated using failover groups, **MCP server objects are not replicated**. Recreate the MCP server on the secondary account.

---

## Part 7: Troubleshooting

Find your symptom, read the likely cause, do the fix.

| # | Symptom | Likely cause | Fix |
| --- | --- | --- | --- |
| 1 | M365 admin center **rejects the ZIP** | Package problem | Rebuild with `build-plugin.ps1` and do not hand-edit or re-zip the package (the files must sit at the top level of the ZIP, not inside a subfolder). Make sure you are uploading `snowflake-cowork-plugin.zip` from the `dist` folder. |
| 2 | Error mentioning `additionalProperties` or "has not been defined" | A field was added to `manifest.json` that Microsoft does not allow | Rebuild. Do not edit the manifest by hand. |
| 3 | Builder says the host contains an **underscore** | Snowflake MCP needs hyphens in the host | Use `my-account` not `my_account` in the host part of the URL. Re-run Step 2.3. |
| 4 | Sign-in window shows a Snowflake error such as **`Invalid redirect_uri`** or **`redirect URI mismatch`** | The integration's redirect does not exactly match | In Snowsight run `DESC SECURITY INTEGRATION <name>;` and confirm `OAUTH_REDIRECT_URI` is exactly `https://teams.microsoft.com/api/platform/v1.0/oAuthRedirect`. Re-run STEP 5 if not. |
| 5 | **`invalid_client`** after sign-in | Wrong client ID/secret in the Developer Portal, **or** a Snowflake network policy is blocking the token request | Re-copy the values from `SELECT SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('<INTEGRATION_NAME_IN_UPPERCASE>');` into the portal. If correct, see problem 6. |
| 6 | Works from your PC in a browser but not from Cowork; or `invalid_client` with correct credentials | **Network policy** blocks Microsoft's servers | Ask your Snowflake network admin to add a network rule that allows Microsoft's outbound addresses (get them from Microsoft) to the account network policy: `CREATE NETWORK RULE ... MODE=INGRESS TYPE=IPV4 VALUE_LIST=(...)` then `ALTER NETWORK POLICY ... ADD ALLOWED_NETWORK_RULE_LIST=(...)`. |
| 7 | Sign-in works but **every tool call returns 404** | The portal registration is tied to one Teams app | Edit the registration: **Restrict usage by app = Any Teams app** (Step 3.2). |
| 8 | Sign-in works but **tools fail / session will not start** | The user has **no default warehouse**, or their default role is not the access role | `ALTER USER <user> SET DEFAULT_ROLE='<ACCESS_ROLE>' DEFAULT_WAREHOUSE='<WAREHOUSE>';` (STEP 7). |
| 9 | **"Insufficient privileges"** / tool not found / object does not exist | Missing grants. Access to the MCP server does **not** give access to its tools | Check `USAGE ON MCP SERVER`, `USAGE ON AGENT`, and `SELECT`/`USAGE` on every table, semantic view or search service the tool uses (STEP 3 and 4). |
| 10 | Tools list is **empty** | The role cannot see the MCP server or tools | Run `SHOW MCP SERVERS IN SCHEMA <db>.<schema>;` while using the access role. Re-check grants. |
| 11 | **401 Unauthorized** | Token missing/expired, or the Authorization header was dropped (only if using APIM) | Sign out and in again (Cowork, **Chat settings**, **Agents**, sign out). With APIM, make sure no policy removes the `Authorization` header. |
| 12 | Users are asked to sign in **again and again** | Refresh tokens not being issued/accepted | Confirm the integration has `OAUTH_ISSUE_REFRESH_TOKENS = TRUE` (the default) and a sensible `OAUTH_REFRESH_TOKEN_VALIDITY` via `DESC SECURITY INTEGRATION`. |
| 13 | Consent screen says **"secondary roles = ALL"** | Cosmetic. The client asked for `session:role:all` | Safe to approve. The integration was created with `OAUTH_USE_SECONDARY_ROLES = NONE`, which Snowflake enforces. |
| 14 | **I do not want to change my users' default role** | Cowork uses the default role | Create a **separate MCP server** and role per audience, or have users keep the access role as default only if that is acceptable. Snowflake notes that some clients do not honor per-role scopes, so a dedicated MCP server per access level is the reliable pattern. |
| 15 | Answers are cut off / "response truncated" | Tool responses are limited to about 250 KB | Ask narrower questions (fewer columns, filters, `LIMIT`). |
| 16 | **Cannot connect at all** from a PrivateLink account | Cowork cannot reach private addresses | Use the public URL (Part 6, PrivateLink section). |
| 17 | `Tool not found` on a tool that used to work | The tool was removed or renamed in the MCP specification | `DESCRIBE MCP SERVER <name>;` to see the current tool names. |
| 18 | Error about **more than 50 tools** | Snowflake allows 50 tools per MCP server | Split into several MCP servers. |
| 19 | Costs are higher than expected | Cortex Agent or Analyst calls use Snowflake credits and warehouse time | Use a small dedicated warehouse, a resource monitor, and the least-privileged role. |
| 20 | Behaves strangely after replication/failover | MCP server objects are not replicated | Recreate the MCP server on the secondary account. |

### Still stuck? Collect this before asking for help

- The exact error text and a screenshot.
- The output of `DESCRIBE MCP SERVER <name>;` and `DESC SECURITY INTEGRATION <name>;` (**remove the client secret** before sharing).
- Which user, which role, and whether they have a default warehouse.
- The MCP URL you used (it contains no secret).
- Whether you are using Option A, B or C.

### Quick manual test of the MCP server (optional, technical)

You can test the server outside Cowork with the free **MCP Inspector** (`npx @modelcontextprotocol/inspector`). Choose **Streamable HTTP**, paste the MCP URL, and supply
the OAuth client ID and secret. If it works there but not in Cowork, the problem is in Parts 3 or 4 or in a network policy. If it fails there too, the problem is in Part 2.

---

## Part 8: Updating, rotating secrets, removing

- **Change the MCP server or add a tool:** edit the MCP server in Snowflake (`CREATE OR REPLACE MCP SERVER ...`). The plugin finds the new tools automatically; no rebuild is needed.
  Re-grant `USAGE ON MCP SERVER` if you replaced it.
- **Rotate the client secret:** in Snowflake, regenerate the integration's secret, then in the Teams Developer Portal edit the registration and paste the new secret.
- **New plugin version:** run `build-plugin.ps1 -PluginVersion 1.0.1` and upload the new ZIP in the admin center. The plugin ID stays the same, so it updates in place.
- **Move to another Snowflake account:** rebuild with the new URL and a new registration ID.
- **Remove:** delete the app in the Microsoft 365 admin center, delete the registration in the Teams Developer Portal, then in Snowflake run `DROP MCP SERVER ...;` and `DROP SECURITY INTEGRATION ...;`.
- **Users can sign out** of the connector from Cowork **Chat settings**, **Agents**; this clears their stored token.

---

## Appendix: Values cheat sheet

Print this and fill it in as you go.

| Value | Where it comes from | Used in | Your value |
| --- | --- | --- | --- |
| Account host | Script STEP 0 | MCP URL, endpoints | |
| MCP URL | Step 2.3 | Portal "Base URL"; builder | |
| Client ID | Step 2.4 | Portal | |
| Client secret | Step 2.4 | Portal only. **Never in email or the ZIP.** | |
| Authorization endpoint | `https://<account_host>/oauth/authorize` | Portal | |
| Token / refresh endpoint | `https://<account_host>/oauth/token-request` | Portal | |
| Scope | `session:role:all` | Portal | |
| Registration ID | Step 3.4 | Builder | |

### Sources

- Snowflake-managed MCP server: https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp
- Build plugins for Copilot Cowork: https://learn.microsoft.com/en-us/microsoft-365/copilot/cowork/cowork-plugin-development
- Configure OAuth 2.0 for plugins: https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/plugin-authentication-oauth
- Expose and govern an existing MCP server (Azure API Management): https://learn.microsoft.com/en-us/azure/api-management/expose-existing-mcp-server
