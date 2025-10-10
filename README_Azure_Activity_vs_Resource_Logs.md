# Azure Activity Logs vs Resource Logs

This document provides a detailed comparison between **Azure Activity Logs** and **Azure Resource Logs**, outlining their purpose, scope, and best-use scenarios for monitoring, compliance, and operations.

---

## 📘 Overview

| Category | Activity Logs | Resource Logs |
|-----------|----------------|----------------|
| **Scope** | Subscription-level (**control plane**) | Resource-level (**data plane**) |
| **Covers** | Management operations (create/update/delete resources) | Operations *within* a resource (read/write, telemetry, actions) |
| **Examples** | Create VM, Delete NSG, Assign Role | Read secret from Key Vault, Upload blob to Storage, Execute SQL query |
| **Enabled By** | Enabled by default for all subscriptions | Must be explicitly enabled via Diagnostic Settings |
| **Storage** | Retained for 90 days by default; can be sent to Event Hub, Log Analytics, or Storage | Stored only if Diagnostic Settings are configured (Log Analytics, Event Hub, Storage) |
| **Primary Use** | Auditing, compliance, change tracking, governance | Security monitoring, troubleshooting, performance analysis |
| **Where to View** | Azure Portal → Monitor → Activity Log | Azure Portal → Resource → Diagnostic Settings / Logs |
| **Retention** | 90 days (default) | Configurable based on destination |
| **Plane Type** | Control plane (management) | Data plane (inside resources) |

---

## 🔍 Key Difference in One Line

> **Activity Logs** = Who did what at the subscription/control plane level.  
> **Resource Logs** = What happened inside the resource at the data plane level.

---

## 🧩 Common Use Cases

- **Activity Logs**
  - Detect unauthorized changes or deletions.
  - Track configuration drift.
  - Provide compliance and audit evidence.

- **Resource Logs**
  - Diagnose app or data-level issues.
  - Identify suspicious access behavior (e.g., key reads, storage deletions).
  - Feed into SIEM systems like Azure Sentinel or Splunk for analytics.

---

## 🧠 Tip

For full observability, combine **Activity Logs**, **Resource Logs**, and **Metrics** within **Azure Monitor** or your centralized logging platform.

---

## 📂 Related Links

- [Azure Activity Log documentation](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/activity-log)
- [Azure Resource Logs (Diagnostic Logs) documentation](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/resource-logs)
- [Exporting logs to Log Analytics and Event Hub](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/resource-logs-stream-event-hub)

---
