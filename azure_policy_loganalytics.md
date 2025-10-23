# Azure Policy: Enable `allLogs` Resource Logging to Log Analytics (Manual Export to Event Hubs)

This document explains how to implement the Azure built-in policy that configures **resource diagnostic settings** to send the **`allLogs` category group** to **regional Log Analytics workspaces**. It also details the process for **manually exporting** Log Analytics data tables to **regional Event Hubs**, where each Event Hub represents a specific location.

---

## 1. Overview

The Azure built-in policy ensures that all supported resources have diagnostic settings configured to send **`allLogs`** to an assigned **Log Analytics workspace (LAW)**. Once applied, this policy automatically creates diagnostic settings for resources that do not have them configured, ensuring consistent log ingestion across the environment.

The policy does **not** handle exporting data from Log Analytics to Event Hubs — that step must be performed manually for each region.

---

## 2. Target Regions

The setup includes four primary regions, each with a dedicated Log Analytics workspace and Event Hub namespace:

| Region         | Log Analytics Workspace | Event Hub Namespace          |
|----------------|--------------------------|------------------------------|
| East US        | `law-eus-monitor`        | `ehn-eus-monitor`            |
| West US 2      | `law-wus2-monitor`       | `ehn-wus2-monitor`           |
| Central India  | `law-cin-monitor`        | `ehn-cin-monitor`            |
| Southeast Asia | `law-sea-monitor`        | `ehn-sea-monitor`            |

Each region’s Log Analytics workspace collects diagnostic logs from all supported resources in that location. The logs can then be exported manually to their corresponding Event Hub namespace for downstream processing or SIEM ingestion.

---

## 3. Azure Policy Purpose

The policy titled **“Enable allLogs category group resource logging for supported resources to Log Analytics”** ensures that all Azure services capable of emitting resource logs send them to a specified Log Analytics workspace. The policy enforces:

- **Category Group:** `allLogs`
- **Destination:** Regional Log Analytics workspace
- **Effect:** `DeployIfNotExists`

This ensures diagnostic settings are automatically configured on existing and newly created supported resources.

---

## 4. Implementation Steps

### Step 1: Identify the Built-In Policy
Search in Azure Policy Definitions for the built-in policy named:
> **"Enable allLogs category group resource logging for supported resources to Log Analytics"**

The policy can be assigned at the **management group**, **subscription**, or **resource group** scope. The preferred method is to assign it at the **management group** level for centralized governance.

### Step 2: Assign the Policy per Region
Assign the policy separately for each target region to ensure logs are routed to the appropriate regional Log Analytics workspace.

Each assignment will include:
- **Log Analytics Workspace Resource ID** for that region
- **Effect:** DeployIfNotExists

This guarantees that each region’s resources send logs to their corresponding workspace.

### Step 3: Validate Policy Compliance
After deployment, verify that:
- Diagnostic settings are automatically created on supported resources.
- The `allLogs` category group is enabled.
- Logs are flowing into the regional Log Analytics workspace.

---

## 5. Manual Export from Log Analytics to Event Hubs

Once the logs are being ingested into Log Analytics, they can be exported to Event Hubs manually. This process allows each region’s Log Analytics workspace to stream logs to its corresponding Event Hub.

### Manual Export Process:
1. In the **Azure portal**, navigate to the **Log Analytics workspace** for the target region (e.g., `law-eus-monitor`).
2. Go to **Tables** or **Logs** depending on which data you want to export.
3. Create or configure a **data export rule** to define which tables or log types should be streamed.
4. Choose **Destination type:** Event Hub.
5. Select the appropriate **Event Hub namespace** for that region (e.g., `ehn-eus-monitor`).
6. Assign an **Event Hub** (or create one) within that namespace.
7. Configure **data export frequency** and **filtering** (if applicable).
8. Save the configuration and confirm data flow by monitoring message counts in Event Hubs.

> **Note:** The data export configuration is done manually because the built-in policy only enforces diagnostic settings to Log Analytics — it does not automate export rules from Log Analytics to Event Hubs.

---

## 6. Validation Steps

To confirm successful configuration:
- Check that **diagnostic settings** exist on several resources and include `allLogs`.
- Review **Log Analytics ingestion metrics** to ensure logs are being received.
- Verify that data export rules exist under the **Log Analytics workspace** and are successfully streaming data to the **regional Event Hub**.
- Inspect the **Event Hub metrics** for message ingress to ensure export is active.

---

## 7. Governance Recommendations

- **Regional isolation:** Maintain separate Log Analytics and Event Hub resources per region to comply with data residency and performance best practices.
- **Access control:** Limit modification rights on diagnostic settings and export rules to the monitoring or platform operations team.
- **Retention:** Set workspace and Event Hub retention in accordance with compliance policies.
- **Monitoring:** Use Azure Monitor alerts to detect data export failures or Event Hub ingestion delays.

---

## 8. Summary

This configuration ensures:
- All supported Azure resources have diagnostic settings automatically configured to send `allLogs` to their designated regional Log Analytics workspace.
- Manual export rules from each Log Analytics workspace stream relevant log tables to the regional Event Hubs for further processing, analysis, or integration with SIEM platforms.

By separating automated policy enforcement (for diagnostic settings) and manual configuration (for data export), this model provides flexibility and compliance alignment while maintaining operational control over data routing.

