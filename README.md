# Azure Support Menu (PowerShell)

A fast, menu-driven PowerShell **launcher** for running support scripts by “service” folder. It:

- Auto-discovers services under `./services/*`
- Reads an optional `actions.json` per service for friendly names, default args, **RBAC gating**, and scope
- Falls back to listing `*.ps1` if no manifest exists
- Handles **tenant-first** Azure login, then subscription selection (works with older Az module versions)
- Provides a full-screen **arrow-key UI**
- Runs actions in the **same session** (shares Az context) or a **new window**
- Logs runs to `./logs/run-YYYYMMDD.log`

---

## Features

- **Tenant-first auth**: pick `TenantId` (or set in `config.json`) then pick a subscription from that tenant. Device-code fallback for MFA/CA policies.
- **RBAC gating**: require roles (e.g., `Reader`, `Contributor`) at a declared scope; parent-scope inheritance supported (RG → subscription).
- **Curses-style UI**: Up/Down/Home/End/Enter/Esc, **F** to filter, **I** for details, and a toggle to hide locked items.
- **Resilient JSON**: loader tolerates `//` comments and trailing commas.
- **Safe by default**: hardened against PowerShell single-item unwrapping and StrictMode pitfalls.

---

## Requirements

- **PowerShell**: 7.x recommended (Windows PowerShell 5.1 is supported).
- **Modules**:
  - `Az.Accounts`
  - `Az.Resources`
  - (Or install the roll-up: `Az`)

Install (no admin needed):
```powershell
Install-Module Az -Scope CurrentUser -Repository PSGallery -Force
```

---

## Folder layout

```
AzureSupportTool\
├─ menu.ps1
├─ config.json                # optional
├─ services\
│  ├─ aviatrix\
│  │  ├─ actions.json
│  │  ├─ Show-Context.ps1
│  │  ├─ List-ResourceGroups.ps1
│  │  ├─ WhoAmI-AtScope.ps1
│  │  ├─ Create-TestResourceGroup.ps1
│  │  └─ Remove-TestResourceGroup.ps1
│  └─ <your-service>\
│     ├─ actions.json        # optional
│     └─ *.ps1               # action scripts
└─ logs\
   └─ run-YYYYMMDD.log
```

> The launcher discovers services by the directory names under `./services`.

---

## Configuration (`config.json`)

Place next to `menu.ps1`. Comments and trailing commas are allowed.

```jsonc
{
  // Log in and pick context automatically
  "AzLogin": true,

  // Prefer this tenant; otherwise you'll get an interactive picker
  "DefaultTenantId": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",

  // Optional: auto-select this subscription inside that tenant
  "DefaultSubscriptionId": "ffffffff-1111-2222-3333-444444444444",

  // Launch actions in a new console window (overrides per-action setting)
  "NewWindowForScripts": false,

  // Hide actions you can't run (toggle inside the UI)
  "HideLockedActions": true
}
```

If `config.json` is missing or invalid, safe defaults are used.

---

## Actions manifest (`services/<service>/actions.json`)

Defines what shows in the service’s submenu and how each action runs.

```json
{
  "title": "My Service Tools",
  "actions": [
    {
      "name": "Show Context",
      "script": "Show-Context.ps1",
      "args": [],
      "scope": { "type": "subscription" },
      "sameProcess": true
    },
    {
      "name": "List RGs (Reader)",
      "script": "List-ResourceGroups.ps1",
      "args": ["-NameLike", "*prod*"],
      "requiredRoles": ["Reader"],
      "scope": { "type": "subscription" },
      "sameProcess": true
    },
    {
      "name": "Create RG (WhatIf) — Contributor",
      "script": "Create-TestResourceGroup.ps1",
      "args": ["-ResourceGroupName", "rg-demo", "-Location", "westeurope", "-WhatIf"],
      "requiredRoles": ["Contributor"],
      "scope": { "type": "resourceGroup", "name": "rg-demo" },
      "sameProcess": true
    }
  ]
}
```

**Fields**

- `name` (string): Menu label.
- `script` (string): Relative `*.ps1` path within the service folder.
- `args` (string[]): Passed as-is to the script.
- `sameProcess` (bool): Run inside the launcher (shares Az context) vs new window.
- `requiredRoles` (string[], optional): Azure role definition names. Empty/omitted = **no gating**.
- `scope` (optional): Where to enforce roles:
  - `{ "type": "subscription" }`
  - `{ "type": "resourceGroup", "name": "<rg-name>" }`
  - A full resource ID string, e.g. `"/subscriptions/<subId>/resourceGroups/<rg>"`
  - If omitted or `null`, defaults to the active subscription.

**Fallback**: If `actions.json` is missing/invalid, the launcher lists all `*.ps1` in that folder (no RBAC gating).

---

## RBAC gating — how it works

- The launcher resolves a **scope resource ID** per action from `scope`.
- It computes your **effective roles** with `Get-AzRoleAssignment` at that scope **and its parents**:
  - RG scope → also checks subscription scope.
- If **all** `requiredRoles` are present → **Enabled**.
- If any are missing:
  - the action shows with a lock (🔒)
  - **Details** pane shows:
    - required roles
    - roles it detected
    - a ready-to-copy example:
      ```bash
      az role assignment create --assignee <your-upn-or-objectId> --role "Reader" --scope "/subscriptions/<id>/resourceGroups/<rg>"
      ```

> If your org uses custom roles, specify their **role definition names** in `requiredRoles`.

---

## Running the launcher

```powershell
cd <path>\AzureSupportTool
.\menu.ps1
```

Flow:
1. Pick **tenant** (or it uses `DefaultTenantId`).
2. Pick **subscription** in that tenant (or it's auto-selected if configured).
3. Pick a **service**, then an **action**.

---

## UI cheatsheet

- **↑ / ↓**: Move
- **Home / End**: Jump to top/bottom
- **Enter**: Select
- **Esc**: Back
- **F**: Filter items by text
- **I**: Show details for the highlighted item
- Toggle *Hide locked* via the dedicated row in the action menu

---

## Logging

- Logs go to `./logs/run-YYYYMMDD.log`.
- Includes timestamps, tenant/subscription selections, and executed commands (avoid secrets in `args`).

---

## Sample service: `aviatrix` (test pack)

Use these to validate both **read** and **write** paths without touching vendor APIs.

`services\aviatrix\actions.json`
```json
{
  "title": "Aviatrix - Test Actions",
  "actions": [
    { "name": "Show Azure Context", "script": "Show-Context.ps1", "args": [], "scope": { "type": "subscription" }, "sameProcess": true },
    { "name": "List Resource Groups (Reader required)", "script": "List-ResourceGroups.ps1", "args": [], "requiredRoles": ["Reader"], "scope": { "type": "subscription" }, "sameProcess": true },
    { "name": "WhoAmI Roles at RG Scope (Reader required)", "script": "WhoAmI-AtScope.ps1", "args": ["-ResourceGroupName","rg-aviatrix-lab"], "requiredRoles": ["Reader"], "scope": { "type": "resourceGroup", "name": "rg-aviatrix-lab" }, "sameProcess": true },
    { "name": "Create/Update Test RG (WhatIf) - Contributor", "script": "Create-TestResourceGroup.ps1", "args": ["-ResourceGroupName","rg-aviatrix-lab","-Location","westeurope","-WhatIf"], "requiredRoles": ["Contributor"], "scope": { "type": "resourceGroup", "name": "rg-aviatrix-lab" }, "sameProcess": true },
    { "name": "Delete Test RG (WhatIf) - Owner", "script": "Remove-TestResourceGroup.ps1", "args": ["-ResourceGroupName","rg-aviatrix-lab","-WhatIf"], "requiredRoles": ["Owner"], "scope": { "type": "resourceGroup", "name": "rg-aviatrix-lab" }, "sameProcess": true }
  ]
}
```

Scripts to include in `services\aviatrix\`:
- `Show-Context.ps1`: prints current Az context (tenant, subscription, account).
- `List-ResourceGroups.ps1`: lists RGs; accepts `-NameLike` wildcard.
- `WhoAmI-AtScope.ps1`: shows your principal ObjectId and role assignments at a scope (and parent).
- `Create-TestResourceGroup.ps1`: idempotent RG create/update; **simulated by `-WhatIf`**.
- `Remove-TestResourceGroup.ps1`: RG delete; **simulated by `-WhatIf`**.

Remove `-WhatIf` in `actions.json` to perform real changes after validating RBAC.

---

## Troubleshooting

**“Wrong tenant ID”**
- Ensure `config.json` has `"DefaultTenantId": "<your-tenant-guid>"` next to `menu.ps1`.  
- To pick interactively, leave it `null`.

**“A parameter cannot be found that matches parameter name 'TenantId'”**
- Older `Az.Accounts` version. The provided script avoids `-TenantId` on `Select-AzSubscription`; ensure you're using the latest `menu.ps1`.

**“Failed to parse actions.json …”**
- The loader accepts comments/trailing commas—but smart quotes or stray characters can still break JSON. Validate quickly:
  ```powershell
  Get-Content .\services\<service>\actions.json -Raw | ConvertFrom-Json | Out-Null
  ```

**“The property 'Count' cannot be found …”**
- Happens when an enumeration returns a single object and code uses `.Count` on a scalar. The provided `menu.ps1` wraps results in arrays (`@(...)`) everywhere.

**“You lack required roles… (No RBAC requirement declared)”**
- Fixed: actions with no `requiredRoles` aren’t gated. Ensure your launcher is the updated one.

**`$rawActions` not set / StrictMode errors**  
- The main loop initializes variables before use and guards cancel paths. Update to the latest `menu.ps1`.

---

## Security notes

- The launcher doesn’t store credentials or secrets.
- Logs include action names and arguments; avoid embedding secrets in `args`.

---

## Compatibility notes

- Works with PowerShell 5.1 and 7+.
- Compatible with a range of Az module versions (device-code fallback for Conditional Access/MFA).

---

## Add a new service quickly

1. Create a folder: `./services/<serviceName>`  
2. Add your scripts: `*.ps1`  
3. (Optional) add `actions.json` to define friendly names, default args, RBAC, and scopes.  
4. Run `.\menu.ps1` and select your service.

Minimal template:
```json
{
  "title": "Tools",
  "actions": [
    { "name": "Do Thing", "script": "Do-Thing.ps1", "args": [], "sameProcess": true }
  ]
}
```

---

## FAQ

**Do actions share variables/Az context?**  
Only when `"sameProcess": true`. Otherwise they spawn in a new console.

**Can I scope to a specific resource (not just RG/sub)?**  
Yes—set `scope` to the full resource ID string.

**Do custom roles work?**  
Yes. Use their **role definition names** in `requiredRoles`.

**Can the scope come from an action argument (e.g., RG name)?**  
Not yet. Easiest is to duplicate actions for common scopes, or hardcode the RG name in both `args` and `scope`.
