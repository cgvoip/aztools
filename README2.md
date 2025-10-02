
# Enable **allLogs** to Azure Event Hub via Azure Policy (per-region design)

This repo documents how to implement the built‑in Azure Policy **initiative**:  
**“Enable allLogs category group resource logging for supported resources to Event Hub”** (policy set/initiative ID: `85175a36-2f12-419a-96b4-18d5b0096531`) to stream **resource logs** from all *supported* services into **dedicated Event Hub namespaces** in these regions:

- East US
- West US 2
- Southeast Asia
- Central India

Each region has its **own** Event Hubs namespace and hub, and each namespace **only** allows the CIDR ranges `10.0.0.1/23` and `172.1.1.3/23` (plus trusted Microsoft services so Diagnostic Settings can write).

> TL;DR: You will create Event Hubs in each region, lock them down with IP rules, and assign the built‑in initiative **once per region**. You’ll run a remediation per region so existing resources get a diagnostic setting deployed.

---

## What this does (and doesn’t)

**Does**
- Deploys a *diagnostic setting* to **resources that support resource logs**, using the `allLogs` **category group**, with destination **Event Hubs**.
- Uses **DeployIfNotExists** to configure missing diagnostic settings at scale.
- Sends logs to your region‑specific Event Hub namespace and hub.

**Does *not***
- Collect **platform metrics** (`AllMetrics`) — different policies cover metrics.
- Configure **Activity Log** (subscription-level). That’s a separate policy/setting.
- Cross‑region stream: **Event Hub destination must be in the same region** as the monitored resource (hard requirement).

---

## Design overview

### Per‑region Event Hub
You’ll provision an Event Hubs namespace **in each target region** and an event hub (e.g., `platform-logs`). The diagnostic settings must point to a **same‑region** Event Hub.

### Network rules
For each namespace, the firewall is set to **Selected networks** with:
- Allow **IP rules**: `10.0.0.1/23`, `172.1.1.3/23`
- Enable **Allow trusted Microsoft services** (required so Azure Monitor Diagnostic Settings can write when the namespace is firewalled).

### Policy assignments (one per region)
Assign the built‑in initiative **four times** — one for each region — each with parameters that point to that region’s Event Hub namespace authorization rule and hub name. Limit the blast radius via **scope** and **excluded scopes** to ensure assignments only target resources in the intended region(s). Then create **remediation** for each assignment with `--location-filters <region>`.

---

## Prerequisites

- **RBAC**: The policy assignment’s managed identity needs to create diagnostic settings on resources and reference your Event Hub **authorization rule**. The built‑ins use these roles during remediation:
  - **Azure Event Hubs Data Owner** on the destination EH namespace
  - (Some definitions also specify **Log Analytics Contributor** though we’re routing to Event Hubs)  
- **Event Hub namespaces** exist in each region with a **Send**‑capable auth rule (e.g., `RootManageSharedAccessKey`).
- You have a way to scope assignments to “only the resource groups in region X” (separate RGs per region, or use `--not-scopes` to exclude others).

---

## Naming (suggested)

| Region | Namespace | Event Hub |
|-------|-----------|-----------|
| East US | `evhns-platlogs-eus` | `platform-logs` |
| West US 2 | `evhns-platlogs-wus2` | `platform-logs` |
| Southeast Asia | `evhns-platlogs-sea` | `platform-logs` |
| Central India | `evhns-platlogs-cind` | `platform-logs` |

> Replace names as needed. Keep hub names consistent to simplify consumers.

---

## Step 1 — Create/lock down Event Hubs per region

```bash
# Variables
SUB="<subId>"
RG_EUS="rg-logging-eus";   NS_EUS="evhns-platlogs-eus";   HUB="platform-logs"
RG_WUS2="rg-logging-wus2"; NS_WUS2="evhns-platlogs-wus2"
RG_SEA="rg-logging-sea";   NS_SEA="evhns-platlogs-sea"
RG_CIND="rg-logging-cind"; NS_CIND="evhns-platlogs-cind"

# Example for East US (repeat for the other regions with correct -l)
az group create -n $RG_EUS -l eastus
az eventhubs namespace create -g $RG_EUS -n $NS_EUS -l eastus --sku Standard

# Create the event hub
az eventhubs eventhub create -g $RG_EUS --namespace-name $NS_EUS -n $HUB --message-retention 7 --partition-count 4

# Lock down networking: Selected networks + allow two CIDRs + trusted services
az eventhubs namespace network-rule-set update   -g $RG_EUS -n $NS_EUS   --default-action Deny   --enable-trusted-service-access true

az eventhubs namespace network-rule-set ip-rule add   -g $RG_EUS --namespace-name $NS_EUS --name allow-cidr-1   --ip-rule ip-address=10.0.0.1/23 action=Allow

az eventhubs namespace network-rule-set ip-rule add   -g $RG_EUS --namespace-name $NS_EUS --name allow-cidr-2   --ip-rule ip-address=172.1.1.3/23 action=Allow

# Capture the auth rule ARM ID (RootManageSharedAccessKey is created by default)
EH_RULE_EUS="/subscriptions/$SUB/resourceGroups/$RG_EUS/providers/Microsoft.EventHub/namespaces/$NS_EUS/AuthorizationRules/RootManageSharedAccessKey"
```

Repeat for **West US 2** (`-l westus2`, vars `RG_WUS2/NS_WUS2`), **Southeast Asia** (`-l southeastasia`), and **Central India** (`-l centralindia`).

---

## Step 2 — Assign the built‑in initiative (per region)

**Initiative ID**: `85175a36-2f12-419a-96b4-18d5b0096531`  
Parameters used by the included definitions include `eventHubAuthorizationRuleId`, `eventHubName`, `diagnosticSettingName`, `effect`.

> You **must** constrain each assignment to *only* the resource groups that host resources in that region (or use a per‑region management group). Otherwise, the policy will try to point cross‑region resources to the wrong Event Hub and **fail**.

Example — **East US** assignment at subscription scope, excluding RGs from other regions, with system‑assigned identity:

```bash
ASSIGN_NAME_EUS="set-alllogs-to-eh-eus"
SCOPE="/subscriptions/$SUB"

# Replace the list with your non-EastUS RGs (or scope to a management group/RG that only contains EastUS)
NOT_SCOPES="/subscriptions/$SUB/resourceGroups/rg-apps-wus2 /subscriptions/$SUB/resourceGroups/rg-data-sea /subscriptions/$SUB/resourceGroups/rg-infra-cind"

PARAMS_EUS="$(cat <<EOF
{
  "eventHubAuthorizationRuleId": { "value": "$EH_RULE_EUS" },
  "eventHubName": { "value": "$HUB" },
  "diagnosticSettingName": { "value": "setByPolicy-EventHub" },
  "effect": { "value": "DeployIfNotExists" }
}
EOF
)"

az policy assignment create   --name "$ASSIGN_NAME_EUS"   --display-name "Enable allLogs -> Event Hub (East US)"   --policy-set-definition "/providers/Microsoft.Authorization/policySetDefinitions/85175a36-2f12-419a-96b4-18d5b0096531"   --scope "$SCOPE"   --not-scopes $NOT_SCOPES   --params "$PARAMS_EUS"   --mi-system-assigned   --location eastus
```

> Do the same for **West US 2**, **Southeast Asia**, and **Central India**, swapping the Event Hub rule ID and assignment location. If you organize resources per‑region into RGs or per‑region management groups, scope the assignment there and skip `--not-scopes`.

---

## Step 3 — Remediate existing resources (per region)

New resources get evaluated on create/update, but **existing** ones need a remediation. Run **one remediation per assignment** and use a **location filter** so it only deploys to resources in that region.

```bash
# Example for East US (after creating the EastUS assignment)
az policy remediation create   --name remediate-alllogs-eus   --policy-assignment "$ASSIGN_NAME_EUS"   --location-filters eastus   --resource-discovery-mode ReEvaluateCompliance
```

Repeat with `westus2`, `southeastasia`, `centralindia` using the respective assignment names.

---

## Verification

- **Policy**: `az policy state summarize --query "value[0].results.nonCompliantResources"`  
- **Diagnostic settings on a given resource**:  
  `az monitor diagnostic-settings list --resource <ARM-ID-OF-RESOURCE>`  
- **Subscription Activity Log** (separate feature):  
  `az monitor diagnostic-settings subscription list`

---

## Costs

- Event Hubs ingress/throughput and retention (per namespace/hub).
- Azure Policy evaluation/remediation operations (no direct cost, but deployments create diagnostic settings).
- Downstream SIEM/consumer costs.

---

## Security hardening

- Prefer **Private Link** or **VNet service endpoints** over public IP allow‑lists where possible; keep the two IP rules as a fallback.
- Leave **Public network access** disabled if you only use private endpoints.
- Keep **Allow trusted Microsoft services** enabled — otherwise Diagnostic Settings writes will fail when the firewall is on.

---

## FAQs / gotchas

- **Why multiple assignments?** Because Diagnostic Settings → Event Hubs **must** be same‑region. A single assignment pointing to one EH namespace can’t serve multi‑region resources.
- **What about metrics?** This initiative is for **resource logs** (`allLogs`). If you want metrics, use separate built‑in policies for `AllMetrics`.
- **Activity Log?** Use the subscription‑level Activity Log diagnostic setting or a separate policy that targets Activity Log to Event Hubs.
- **Do I need special roles?** The initiative uses **DeployIfNotExists** and grants required roles during remediation; ensure the assignment identity can create role assignments at the necessary scopes.

---

## References

- Built‑in initiative: *Enable allLogs category group resource logging for supported resources to Event Hub* (ID `85175a36-2f12-419a-96b4-18d5b0096531`).
- Event Hubs firewall + trusted services, and same‑region requirement for Diagnostic Settings.
