# Azure Databricks Data Connector for Microsoft Copilot Cowork

Connects Microsoft 365 Copilot Cowork to your **Azure Databricks workspace** using the **Databricks-provided (managed) MCP servers**.
Databricks hosts these servers inside your workspace, so there is nothing to deploy or host yourself.

> **How to use this guide:** do the Parts in order (1 to 4, then 6; Part 5 is optional). Each step says who does it, what to click, and what you should
> see when it worked. If a step does not match what you see, stop and go to [Part 7: Troubleshooting](#part-7-troubleshooting).
> Do not skip the "You should see" checks.

---

## Contents

- [What this plugin does and does not do](#what-this-plugin-does-and-does-not-do)
- [How it works (one minute)](#how-it-works-one-minute)
- [Part 1: Before you start and gather your details](#part-1-before-you-start-and-gather-your-details)
- [Part 2: Check access in Databricks (Databricks administrator)](#part-2-check-access-in-databricks-databricks-administrator)
- [Part 3: Create the sign-in (Databricks account admin and Teams Developer Portal)](#part-3-create-the-sign-in-databricks-account-admin-and-teams-developer-portal)
- [Part 4: Build and upload the plugin](#part-4-build-and-upload-the-plugin)
- [Part 5: Optional, add the Databricks SQL connector](#part-5-optional-add-the-databricks-sql-connector)
- [Part 6: Test it](#part-6-test-it)
- [Part 7: Troubleshooting](#part-7-troubleshooting)
- [Part 8: Updating, rotating secrets, removing](#part-8-updating-rotating-secrets-removing)
- [Appendix: Values cheat sheet](#appendix-values-cheat-sheet)

---

## What this plugin does and does not do

| Connector | Databricks MCP | What Cowork can do | Included |
| --- | --- | --- | --- |
| **Azure Databricks Genie** | `system.ai.genie_one_mcp` (generally available) | Ask business questions in plain language. Genie finds the data, writes the SQL, and answers using your governed semantic layer (Genie Ontology), with links back to sources. **This is the recommended connector.** | Always |
| **Azure Databricks SQL** | `system.ai.dbsql` (Unity Gateway **beta**) | Run a specific SQL query you already wrote on a SQL warehouse, using the caller's permissions. | Only if you do Part 5 |

**It does not:**

- Bypass Databricks security. Calls run **as the signed-in user**, and **Unity Catalog permissions are always enforced**. If the user cannot read a table, Cowork cannot read it.
- Give access to the external-service MCPs Databricks also provides (Slack, GitHub, Jira, Gmail, and so on). Those are not part of this plugin.
- Work from Cowork on a phone (Microsoft does not support custom plugins in Cowork mobile).

## How it works (one minute)

```
 User in Copilot Cowork
        |  (1) asks a data question
        v
 This plugin (skill + connector) --(2) signs the user in via OAuth--> Azure Databricks sign-in
        |                                                                     |
        |  (3) calls the Databricks managed MCP server with the user's token  |
        v                                                                     v
 https://<workspace-host>/ai-gateway/mcp-services/system.ai.genie_one_mcp   (Unity Gateway)
        |
        v
 Genie One -> runs as the user -> Unity Catalog checks permissions -> answer returns to Cowork
```

Three systems are involved:

| System | What you configure | Part |
| --- | --- | --- |
| Azure Databricks | Check the MCP is available and who may call it; create an **OAuth app connection** | 2 and 3 |
| Microsoft Teams Developer Portal | An "OAuth client registration" that stores the Databricks client ID and secret safely | 3 |
| Microsoft 365 admin center | Upload the plugin ZIP | 4 |

---

## Part 1: Before you start and gather your details

### 1.1 People you need

| Role | Needed for | Typical person |
| --- | --- | --- |
| **Databricks workspace admin / metastore admin** | Part 2 (permissions) | Data platform admin |
| **Databricks account admin** (account console at accounts.azuredatabricks.net) | Part 3.1 and 3.2 (create the OAuth app connection) | Cloud / platform admin |
| **Person who can use the Teams Developer Portal** with a work account | Part 3.3 to 3.5 | IT / developer |
| **Microsoft 365 administrator** who can upload custom apps | Part 4 | M365 admin |
| **Windows PC** with PowerShell (built in to Windows 10/11) | Part 4 | Whoever does Part 4 |

One person can do all of it if they hold all of the permissions.

### 1.2 Find your workspace host name

1. Open your Azure Databricks workspace in a browser and sign in.
2. Look at the address bar. It looks like `https://adb-1234567890123456.7.azuredatabricks.net/?o=1234567890123456#...`
3. Copy **only** the part between `https://` and the first `/`:

   ```
   adb-1234567890123456.7.azuredatabricks.net
   ```

> **You should see:** a host name with no `https://`, no slash, no `?o=...`. This is your **workspace host name**. Write it down. (The build script also cleans
> up a pasted full URL for you.)

### 1.3 Requirements checklist (tick each one)

- [ ] Your organization has **Microsoft 365 Copilot with Cowork**, and your admin may upload custom apps.
- [ ] You can sign in to the Azure Databricks workspace, and the workspace uses **Unity Catalog**.
- [ ] You have a Databricks **account admin** available (Part 3).
- [ ] The data users need is in **Unity Catalog** and those users already have access to it. (Cowork never grants new data access.)
- [ ] You have downloaded this repository. On GitHub click the green **Code** button, **Download ZIP**, then right-click the ZIP in Windows and **Extract All**.
  Do the work from the extracted `databricks-plugin` folder.
- [ ] If the workspace has **IP access lists** or is **private-link only**, you read [Part 7, problem 6](#part-7-troubleshooting) first.

### 1.4 Time

About 45 minutes the first time, longer if the OAuth app connection must wait for approval (Databricks says new connections can take up to **30 minutes** to take effect).

---

## Part 2: Check access in Databricks (Databricks administrator)

**Goal:** make sure the Genie One MCP exists in your workspace and the right people may call it. No SQL scripts are needed.

### Step 2.1: Confirm the MCP is there

1. In your Databricks workspace, open **Unity Gateway** in the left menu, then click **MCPs**.
2. Look for **`system.ai.genie_one_mcp`**.

> **You should see:** `system.ai.genie_one_mcp` in the list, with a URL that ends in `/ai-gateway/mcp-services/system.ai.genie_one_mcp`.
> If **Unity Gateway** is missing from the menu, or the MCP is not listed, stop and ask your Databricks account team/administrator to enable it for the workspace. Do not continue.

### Step 2.2: Check who may call it

A person can use the MCP only if they have **all** of these:

| Requirement | Detail |
| --- | --- |
| `EXECUTE` on the MCP | On `system.ai.genie_one_mcp` |
| `USE CATALOG` and `USE SCHEMA` | On `system` and `system.ai` |
| Workspace assignment | They are assigned to this workspace |
| Data permissions | Whatever the questions touch (Unity Catalog tables and so on) |

Databricks-provided MCPs often inherit a **default `EXECUTE` grant on `system.ai`**, so users may already have access. To **restrict** it:

1. A metastore admin must first grant themselves `MANAGE` on the `system.ai` schema.
2. Open **Unity Gateway**, **MCPs**, click `system.ai.genie_one_mcp`, open the **Permissions** tab, click **Grant**, pick the group (for example `data-team`), tick **EXECUTE**, then **Grant**.
3. Review the broad default grants on `system.ai` if you want only that group to have access.

> **You should see:** the group listed with `EXECUTE` on the Permissions tab.

> **Good to know:** Databricks can also apply **policies** to this MCP (for example blocking sensitive data such as SSNs in questions and answers). That uses the
> Unity Gateway beta; see "Govern an MCP" in the Databricks docs. It is optional.

---

## Part 3: Create the sign-in (Databricks account admin and Teams Developer Portal)

**Goal:** create an OAuth "app connection" in Databricks, give its client ID and secret to Microsoft's Teams Developer Portal, and get back a short
**registration ID** to build into the plugin. The plugin ZIP contains only that ID, never the secret.

> **Important:** Azure Databricks MCP endpoints do **not** support dynamic client registration. That is why this manual step exists. It cannot be skipped.

### Step 3.1: Create the OAuth app connection in Databricks (account admin)

1. Go to **https://accounts.azuredatabricks.net** and sign in as an **account admin**.
2. Click **Settings**, then **App connections**, then **Add connection**.
3. Fill it in:

   | Field | Value |
   | --- | --- |
   | Name | `Copilot Cowork` |
   | Redirect URL | `https://teams.microsoft.com/api/platform/v1.0/oAuthRedirect` (copy exactly; note the capital **A** in `oAuthRedirect`) |
   | Scopes | `ai-gateway` (the scope for the `system.ai` MCPs) |
   | Generate a client secret | **Leave ticked** (the Teams portal stores the secret securely) |

4. Click **Save**.

### Step 3.2: Copy the Client ID and Client Secret

Databricks shows a **Client ID** and a **Client secret** once. Copy both into a safe place (a password manager, **not** email or chat).

> **You should see:** a Client ID (looks like a GUID) and a secret. The secret may not be shown again; if you lose it, generate a new one.

> **Wait up to 30 minutes** before testing. Databricks states that app connection changes can take up to 30 minutes to take effect.

### Step 3.3: Open the Teams Developer Portal

1. Go to **https://dev.teams.microsoft.com/tools** and sign in with your work account.
2. Click **OAuth client registration** (under **Tools**).
3. Click **Register client** (or **New OAuth client registration** if you already have some).

### Step 3.4: Fill in the form exactly as below

| Field | What to enter |
| --- | --- |
| Registration name | `Databricks Genie MCP` |
| Base URL | `https://<workspace-host>/ai-gateway/mcp-services/system.ai.genie_one_mcp` (use your host from Step 1.2) |
| Restrict usage by org | **My organization only** (recommended for a customer install) |
| Restrict usage by app | **Any Teams app** |
| Client ID | Client ID from Step 3.2 |
| Client secret | Client secret from Step 3.2 |
| Authorization endpoint | `https://<workspace-host>/oidc/v1/authorize` |
| Token endpoint | `https://<workspace-host>/oidc/v1/token` |
| Refresh endpoint | `https://<workspace-host>/oidc/v1/token` (same as the token endpoint) |
| Scope | `ai-gateway offline_access` (`offline_access` makes sign-in last instead of asking every hour) |
| Enable PKCE | Leave **on** (the default) |

> **Critical:** *Restrict usage by app* must be **Any Teams app**. If it is tied to one app ID, sign-in appears to work and then every tool call fails with **404**.

Click **Save**.

### Step 3.5: Copy the registration ID

After saving, the portal shows an **OAuth client registration ID** (a code of letters and numbers). Copy it.

> **You should see:** a single code with no spaces. **This is not the client secret.** Write it down next to your workspace host name.

You now have the values the plugin builder needs:

| Value | From |
| --- | --- |
| Workspace host name | Step 1.2 |
| Genie OAuth registration ID | Step 3.5 |

---

## Part 4: Build and upload the plugin

### Step 4.1: Build the ZIP

1. Open the extracted `databricks-plugin` folder in File Explorer.
2. Click the address bar at the top, type `powershell`, press **Enter**. A blue PowerShell window opens in that folder.
3. Paste this and press **Enter**:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\build-plugin.ps1
   ```

   (`-ExecutionPolicy Bypass` avoids the "running scripts is disabled" error and applies to this one command only.)
4. When asked, paste the **workspace host name** (Step 1.2) and the **Genie registration ID** (Step 3.5), pressing **Enter** after each.
5. When asked for the **SQL registration ID**, just press **Enter** to skip it. You can add it later (Part 5).

> **You should see:** a green `SUCCESS`, `Connectors included: Genie`, and a file at `databricks-plugin\dist\databricks-cowork-plugin.zip`.
> A red `PROBLEM:` line says exactly what to fix. Nothing is built until all checks pass.

### Step 4.2: Upload to your organization

1. Sign in to the **Microsoft 365 admin center** (https://admin.microsoft.com) as an administrator.
2. Go to **Settings**, then **Integrated apps** (or **Manage apps**), and choose **Upload custom app**.
3. Choose `databricks-cowork-plugin.zip`.
4. Choose who gets it (a test group first is wise), then confirm.

> Menu names move around as Microsoft updates the admin center. Look for "Upload custom app" under Integrated apps / Manage apps. If you cannot find it,
> search the admin center for "custom app" or ask your Microsoft 365 administrator.

> **You should see:** the upload is accepted with no validation errors, and after a short while the plugin appears under **Discover** in Cowork for the people you chose.
> If rejected, copy the exact error and see [Part 7, problem 1](#part-7-troubleshooting).

### Step 4.3 (alternative, for a quick test by one person)

Developers can sideload the ZIP for themselves with the Microsoft 365 Agents Toolkit CLI:

```powershell
npm install -g @microsoft/m365agentstoolkit-cli
atk auth login m365
atk install --file-path "C:\path\to\databricks-cowork-plugin.zip" --scope Personal
```

---

## Part 5: Optional, add the Databricks SQL connector

Skip this unless people need to run exact SQL. Genie covers most business questions.

> `system.ai.dbsql` needs the **Unity Gateway beta**. A Databricks **account admin** must enable it on the account console **Previews** page first.
> Beta features can change; confirm with your Databricks team that it is appropriate for your customers.

1. **Check the MCP:** in the workspace open **Unity Gateway**, **MCPs**, and confirm `system.ai.dbsql` exists. Grant `EXECUTE` to the right group as in Step 2.2.
2. **Reuse the same Databricks app connection** from Step 3.1. You do **not** need a new one (its scope `ai-gateway` covers all `system.ai` MCPs).
3. In the **Teams Developer Portal** (Step 3.3), create a **second** registration with the same settings as Step 3.4, but:

   | Field | Value |
   | --- | --- |
   | Registration name | `Databricks SQL MCP` |
   | Base URL | `https://<workspace-host>/ai-gateway/mcp-services/system.ai.dbsql` |

   Use the **same** client ID, client secret, endpoints and scope. Save, and copy the new **registration ID**.
4. Re-run the builder (Step 4.1). When it asks for the SQL registration ID, paste this second ID. It must be **different** from the Genie one.
   You should see `Connectors included: Genie + Databricks SQL`.
5. Upload the new ZIP in the admin center (Part 8, "New plugin version").

---

## Part 6: Test it

Do this as a normal user with `EXECUTE` on the MCP (Step 2.2).

1. Open **Copilot Cowork**.
2. Go to **Sources & Skills**, then **Plugins**, find **Databricks Data Connector**, and make sure it is turned on.
3. In a Cowork chat type: `Use the Databricks Genie connector and list the tools you can use.`
   - **You should see:** a **sign-in window** for Azure Databricks the first time. Sign in and approve the consent screen.
   - **You should see:** Cowork lists the Genie tools (for example `genie_ask`).
4. Ask a real question about data you know, for example: `Ask Genie: what were total sales last month?`
   - **You should see:** an answer, usually with the SQL Genie ran and links to sources. Genie can take a little while for the first answer.
5. Ask for data this user should **not** see.
   - **You should see:** a permission message from Databricks. That proves Unity Catalog security is enforced.

If any test fails, go to [Part 7](#part-7-troubleshooting).

---

## Part 7: Troubleshooting

| # | Symptom | Likely cause | Fix |
| --- | --- | --- | --- |
| 1 | M365 admin center **rejects the ZIP** | Package problem | Rebuild with `build-plugin.ps1`; do not hand-edit or re-zip the package (files must be at the top level of the ZIP, not inside a folder). Upload the file from the `dist` folder. |
| 2 | Error mentioning `additionalProperties` or "has not been defined" | A field not allowed by Microsoft's schema was added | Rebuild. Do not edit `manifest.json` by hand. |
| 3 | Builder rejects the **host name** | Pasted a placeholder, space or underscore | Re-copy it from the browser address bar (Step 1.2): `adb-....azuredatabricks.net`. |
| 4 | Sign-in window shows **redirect URI mismatch / invalid redirect** | The Redirect URL in the Databricks app connection is not exact | In the account console, **Settings**, **App connections**, edit the connection. The redirect URL must be exactly `https://teams.microsoft.com/api/platform/v1.0/oAuthRedirect`. Wait up to 30 minutes after changes. |
| 5 | **`invalid_client`** or "client not found" | Wrong client ID/secret in the Teams portal, or the app connection is still propagating | Re-copy the ID and secret (Step 3.2) into the portal. If you just created the connection, wait 30 minutes. |
| 6 | Sign-in works but **calls time out / are blocked** | Workspace **IP access list** or private-only networking blocks Microsoft's servers | Calls come from **Microsoft's cloud service**, not the user's PC. If workspace IP access lists are on, an admin must allow Microsoft's outbound addresses (ask your Microsoft contact for the current list). Signing in from your own network does not prove Cowork can reach the workspace. A workspace reachable only over private link cannot be reached by Cowork. |
| 7 | Sign-in works but **every tool call returns 404** | The Teams registration is tied to one app | Edit the registration: **Restrict usage by app = Any Teams app** (Step 3.4). |
| 8 | **403 / permission denied on the MCP** | The user lacks `EXECUTE` on `system.ai.genie_one_mcp` or on its parent catalog/schema | Part 2, Step 2.2. |
| 9 | Genie answers "I can't find that" or has no data | The user cannot read the tables, or Genie Ontology / Genie spaces are not set up for that data | Check Unity Catalog grants for that user; ask the data owner. |
| 10 | `system.ai.genie_one_mcp` **not listed** in Unity Gateway | Feature not enabled for the workspace/region | Ask your Databricks administrator or account team. |
| 11 | `system.ai.dbsql` missing, or "Unity Gateway beta" error | The beta is not enabled | Account admin: account console, **Previews**, enable **Unity Gateway** (Part 5). |
| 12 | **401 Unauthorized** | Token expired or missing | Sign out and in again (Cowork **Chat settings**, **Agents**, sign out). Confirm the registration scope includes `offline_access`. |
| 13 | Asked to sign in **again and again** | Refresh tokens are not issued | Add `offline_access` to the scope in the Teams registration (Step 3.4). |
| 14 | Slow first answer or timeout | SQL warehouse is starting up | Wait a minute and ask again; consider keeping a serverless warehouse available for Genie. |
| 15 | **Account console** is unreachable for the admin | Account IP access list | Add the admin's IP in the account IP access list. |
| 16 | I see the old endpoint `/api/2.0/mcp/genie` in other documents | Deprecated Genie beta endpoint (sunset Oct 31, 2026) | Do not use it. This plugin uses `system.ai.genie_one_mcp`. |
| 17 | Costs are higher than expected | Genie and SQL use Databricks SQL compute | Use a right-sized warehouse and budget alerts. |
| 18 | The Databricks tool answers but results look cut off | Large result sets | Ask narrower questions (filters, date ranges, fewer columns). |

### Still stuck? Collect this before asking for help

- The exact error text and a screenshot.
- The user, the workspace host name, and whether the Databricks sign-in succeeded.
- Which connector (Genie or SQL) failed.
- Whether the Databricks app connection was created more than 30 minutes ago.
- Your **registration IDs** are safe to share. **Never share the client secret.**

### Quick manual test of the MCP (optional, technical)

Use the **MCP Inspector** (`npx @modelcontextprotocol/inspector`): choose **Streamable HTTP**, paste the MCP URL, and supply the client ID and secret (or, for local-only testing, a
Databricks personal access token in the `Authorization` header; keep tokens out of source control). If it works there but not in Cowork, the problem is in Part 3 or 4 or a
network restriction. If it fails there too, the problem is in Part 2 or the Databricks app connection.

---

## Part 8: Updating, rotating secrets, removing

- **Add or remove the SQL connector / new version:** run `build-plugin.ps1 -PluginVersion 1.0.1` and upload the new ZIP. The plugin ID is stable, so it updates in place.
- **Rotate the client secret:** in the Databricks account console generate a new secret for the app connection, then edit the Teams Developer Portal registration(s) and paste it.
- **Move to another workspace:** rebuild with the new host name and new registration IDs (and a new app connection if it is a different account).
- **Remove:** delete the app in the Microsoft 365 admin center, delete the registration(s) in the Teams Developer Portal, and delete the **App connection** in the Databricks account console.
- **Users can sign out** from Cowork **Chat settings**, **Agents**; this clears their stored token.

---

## Appendix: Values cheat sheet

| Value | Where it comes from | Used in | Your value |
| --- | --- | --- | --- |
| Workspace host name | Step 1.2 | Builder; portal URLs | |
| Genie MCP URL | `https://<host>/ai-gateway/mcp-services/system.ai.genie_one_mcp` | Portal "Base URL" | |
| Redirect URL | `https://teams.microsoft.com/api/platform/v1.0/oAuthRedirect` | Databricks app connection | |
| Client ID | Step 3.2 | Portal | |
| Client secret | Step 3.2 | Portal only. **Never in email or the ZIP.** | |
| Authorization endpoint | `https://<host>/oidc/v1/authorize` | Portal | |
| Token / refresh endpoint | `https://<host>/oidc/v1/token` | Portal | |
| Scope | `ai-gateway offline_access` | Portal | |
| Genie registration ID | Step 3.5 | Builder | |
| SQL registration ID (optional) | Part 5 | Builder | |

### Sources

- Databricks-provided MCPs: https://learn.microsoft.com/en-us/azure/databricks/agents/mcp-tools/built-in-mcp-services
- MCP authentication and networking: https://learn.microsoft.com/en-us/azure/databricks/agents/mcp-tools/authentication-networking
- Genie One MCP server: https://learn.microsoft.com/en-us/azure/databricks/agents/mcp-tools/genie-mcp
- Govern an MCP: https://learn.microsoft.com/en-us/azure/databricks/ai-gateway/govern-mcp-service
- Build plugins for Copilot Cowork: https://learn.microsoft.com/en-us/microsoft-365/copilot/cowork/cowork-plugin-development
- Configure OAuth 2.0 for plugins: https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/plugin-authentication-oauth
