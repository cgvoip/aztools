# Azure Landing Zone Onboarding Guide

This document walks through the **onboarding process for a Landing Zone contract in Azure**. It covers the initial governance requirements, tenant/subscription setup, and the deployment process using Infrastructure-as-Code (IaC) with Terraform and Jenkins CI/CD pipelines.

---

## 1. Initial Engagement and Requirements

Before onboarding begins, you must engage with the following stakeholders:

- **Cloud Architecture Team** – Defines high-level design standards, security requirements, and governance guardrails.
- **Engineering Design Authority (EDA)** – Reviews and approves architectural decisions, validates alignment with enterprise patterns, and ensures compliance with corporate/regulatory standards.

**Key Pre-Onboarding Deliverables:**
- Architecture review sign-off.
- Security and compliance requirements documented.
- Approved network topology and connectivity requirements.
- Tenant and subscription provisioning plan.

---

## 2. Tenant Structure and Subscription Model

The landing zone contract uses a **two-tenant model**:

### Sandbox Tenant
- **Purpose**: Used for experimentation, prototyping, and early-stage development.
- **Subscriptions**:  
  - Each new project is assigned its own subscription.  
  - Resources must remain isolated from corporate and AWS-connected networks.
- **Restrictions**:  
  - No access to the corporate network.  
  - No access to AWS.  
  - No production data permitted.

### Production Tenant
- **Purpose**: Hosts Lab, Development (Dev), and Production (Prod) workloads.  
- **Subscriptions**:  
  - **Lab** – Used for testing deployments and validating IaC.  
  - **Dev** – Mirrors production-like environment for development teams.  
  - **Prod** – Hosts live production workloads and business-critical services.
- **Network Access**:  
  - Full connectivity to **corporate network**.  
  - Direct connectivity to **AWS environments** (hybrid/multi-cloud).  

---

## 3. Subscription Onboarding Requirements

Each new subscription must include:

- **Resource Group Structure** aligned to enterprise standards.  
- **Networking**:  
  - VNets, subnets, NSGs, firewalls, and routing aligned with approved patterns.  
  - ExpressRoute/VPN as defined by architecture.  
- **Identity & Access Management**:  
  - Role-Based Access Control (RBAC) with custom roles where needed.  
  - Enforcement of least privilege principles.  
- **Security & Compliance**:  
  - Azure Policy assignments (CIS, PCI-DSS, or enterprise baseline).  
  - Diagnostic settings for logging into Log Analytics/Event Hub/SIEM.  
- **Monitoring**:  
  - Azure Monitor, Alerts, and metrics enabled.  
- **Cost Management**:  
  - Tags applied to all resources for chargeback/showback.  
  - Budgets and alerts configured.

---

## 4. Deployment Requirements (Terraform + Jenkins)

All **infrastructure deployed into the Production tenant** (Lab, Dev, Prod subscriptions) must follow **Infrastructure-as-Code (IaC) principles** and **CI/CD governance**.

### Rules:
1. **Terraform Only**  
   - All deployments must use **Terraform IaC modules** stored in the central Git repository.  
   - No manual deployments via Azure Portal, CLI, or PowerShell are permitted.

2. **Jenkins CI/CD Pipeline**  
   - Terraform code must be deployed using approved **Jenkins pipelines**.  
   - Pipelines enforce:  
     - Code validation (linting, formatting).  
     - Terraform plan & policy checks.  
     - Security compliance validation.  
     - Deployment approvals (via Engineering Design Authority gates).  
   - Changes are deployed only after pipeline success and approval.

3. **State Management**  
   - Terraform remote state must be stored in **secure Azure Storage Accounts** with **Azure AD authentication** enabled.  
   - State locking and versioning are enforced.

---

## 5. Onboarding Steps (High-Level Workflow)

1. **Engagement** – Meet with Cloud Architecture and Engineering Design Authority for design review.  
2. **Request Subscription** – Submit request for new subscription in Sandbox or Prod tenant.  
3. **Provision Subscription** – Cloud engineering provisions subscription per standards.  
4. **Configure Baseline** – Networking, RBAC, policy, monitoring, and tagging are deployed.  
5. **Develop Terraform Modules** – Application/infra teams build reusable Terraform code.  
6. **Integrate with Jenkins** – Code is onboarded into the central pipeline.  
7. **Deploy via CI/CD** – Jenkins pipeline runs Terraform apply into Lab/Dev/Prod subscriptions.  
8. **Ongoing Governance** – Continuous compliance and monitoring are enforced through Azure Policy, logging, and security tooling.

---

## 6. Key Notes

- **Sandbox Tenant**: Freedom to experiment, but limited connectivity and no production workloads.  
- **Production Tenant**: Strict IaC + CI/CD governance; full corporate and AWS connectivity.  
- **Terraform & Jenkins**: The only allowed method for provisioning infrastructure in Lab, Dev, and Prod subscriptions.  
- **Compliance First**: All subscriptions must align with enterprise policies, tagging standards, and monitoring requirements.  

---

## 7. References

- [Azure Well-Architected Framework](https://learn.microsoft.com/azure/architecture/framework/)  
- [Terraform on Azure](https://learn.microsoft.com/azure/developer/terraform/)  
- [Jenkins CI/CD Pipelines](https://www.jenkins.io/doc/book/pipeline/)  
- [Azure Landing Zones](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/)  

---

**End of Guide**
