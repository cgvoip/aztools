# Enable allLogs Category Group Resource Logging for Supported Resources to Log Analytics

## Overview

The "Enable allLogs category group resource logging for supported resources to Log Analytics" is a built-in Azure Policy initiative provided by Microsoft. This initiative consists of a collection of policies that automatically deploy diagnostic settings for supported Azure resources. It configures these settings to send all available resource logs (using the `allLogs` category group) to a specified Log Analytics workspace in Azure Monitor.

This initiative uses the `DeployIfNotExists` policy effect, which means it evaluates resources within the assigned scope (e.g., management group, subscription, or resource group) and deploys the diagnostic settings if they are missing. It applies to new resources automatically and can be remediated for existing ones. The `allLogs` category group ensures comprehensive logging, capturing all log categories (beyond just audit logs) for deeper insights into resource operations.

This setup centralizes logs in Log Analytics, enabling advanced querying, alerting, and integration with other monitoring tools.

## Benefits

Implementing this initiative provides several key advantages for monitoring, security, compliance, and operational efficiency in Azure environments:

- **Centralized Logging at Scale**: Automatically enables logging for hundreds of supported resource types across your Azure estate without manual configuration per resource. This reduces administrative overhead and ensures consistent log collection.
  
- **Comprehensive Visibility**: By using the `allLogs` category group, you capture all available log data (e.g., operational, performance, and error logs), providing a complete view of resource activities. This is more thorough than the `audit` category, which only covers security and compliance-related events.

- **Improved Troubleshooting and Analysis**: Logs in Log Analytics can be queried using Kusto Query Language (KQL), allowing for quick identification of issues, performance bottlenecks, and anomalies. Features like schema discoverability, faster queries on time-series data, and multi-table analysis enhance diagnostic capabilities.

- **Enhanced Security and Compliance**: Enables proactive monitoring for security threats, audit trails for regulatory requirements (e.g., GDPR, HIPAA), and alerting on suspicious activities. Centralized logs support forensic investigations and compliance reporting.

- **Cost-Effective Monitoring**: Integrates with Azure Monitor's retention policies (free for the first 31 days), allowing you to archive data cost-effectively while retaining access for analysis.

- **Automation and Remediation**: Policies can be assigned to broad scopes and include remediation tasks for existing resources, ensuring ongoing compliance. This is ideal for enterprise-scale deployments.

- **Better Performance and Insights**: Resource logs in Log Analytics offer structured data with improved query performance on columns like timestamps, easier schema exploration, and the ability to correlate logs across resources for holistic insights.

Overall, this initiative simplifies enabling enterprise-wide monitoring, helping organizations achieve better observability, faster incident response, and optimized resource management.

## Supported Resources

The initiative includes built-in policies for the following Azure resource types that support the `allLogs` category group. Note that not all resources support every log category, but the policy will enable all available ones:

| Resource Type | Example Use Case |
|---------------|------------------|
| microsoft.aad/domainservices | Azure Active Directory Domain Services |
| microsoft.agfoodplatform/farmbeats | Azure FarmBeats |
| microsoft.analysisservices/servers | Azure Analysis Services |
| microsoft.apimanagement/service | API Management services |
| microsoft.app/managedenvironments | Azure Container Apps environments |
| microsoft.appconfiguration/configurationstores | App Configuration |
| microsoft.appplatform/spring | Azure Spring Apps |
| microsoft.attestation/attestationproviders | Azure Attestation |
| microsoft.automation/automationaccounts | Automation accounts |
| microsoft.autonomousdevelopmentplatform/workspaces | Autonomous Development Platform |
| microsoft.avs/privateclouds | Azure VMware Solution |
| microsoft.azureplaywrightservice/accounts | Azure Playwright Service |
| microsoft.azuresphere/catalogs | Azure Sphere |
| microsoft.batch/batchaccounts | Batch accounts |
| microsoft.botservice/botservices | Bot Services |
| microsoft.cache/redis | Azure Cache for Redis |
| microsoft.cache/redisenterprise/databases | Redis Enterprise databases |
| microsoft.cdn/cdnwebapplicationfirewallpolicies | CDN Web Application Firewall policies |
| microsoft.cdn/profiles | CDN profiles |
| microsoft.cdn/profiles/endpoints | CDN endpoints |
| microsoft.chaos/experiments | Azure Chaos Engineering |
| microsoft.classicnetwork/networksecuritygroups | Classic network security groups |
| microsoft.cloudtest/hostedpools | CloudTest hosted pools |
| microsoft.codesigning/codesigningaccounts | Code Signing accounts |
| microsoft.cognitiveservices/accounts | Cognitive Services |
| microsoft.communication/communicationservices | Communication Services |
| microsoft.community/communitytrainings | Community Trainings |
| microsoft.confidentialledger/managedccfs | Confidential Ledger |
| microsoft.connectedcache/enterprisemcccustomers | Connected Cache for enterprises |
| microsoft.connectedcache/ispcustomers | Connected Cache for ISPs |
| microsoft.containerinstance/containergroups | Container instances |
| microsoft.containerregistry/registries | Container Registry |
| microsoft.customproviders/resourceproviders | Custom resource providers |
| microsoft.d365customerinsights/instances | Dynamics 365 Customer Insights |
| microsoft.dashboard/grafana | Azure Managed Grafana |
| microsoft.databricks/workspaces | Azure Databricks |
| microsoft.datafactory/factories | Data Factory |
| microsoft.datalakeanalytics/accounts | Data Lake Analytics |
| microsoft.datalakestore/accounts | Data Lake Store |
| microsoft.dataprotection/backupvaults | Backup vaults |
| microsoft.datashare/accounts | Data Share |
| microsoft.dbformariadb/servers | Azure Database for MariaDB |
| microsoft.dbformysql/flexibleservers | Flexible Server for MySQL |
| microsoft.dbformysql/servers | Azure Database for MySQL |
| microsoft.dbforpostgresql/flexibleservers | Flexible Server for PostgreSQL |
| microsoft.dbforpostgresql/servergroupsv2 | PostgreSQL server groups |
| microsoft.dbforpostgresql/servers | Azure Database for PostgreSQL |
| microsoft.desktopvirtualization/applicationgroups | Application groups |
| microsoft.desktopvirtualization/hostpools | Host pools |
| microsoft.desktopvirtualization/scalingplans | Scaling plans |
| microsoft.desktopvirtualization/workspaces | Workspaces |
| microsoft.devcenter/devcenters | Dev Centers |
| microsoft.devices/iothubs | IoT Hubs |
| microsoft.devices/provisioningservices | Device Provisioning Services |
| microsoft.digitaltwins/digitaltwinsinstances | Digital Twins |
| microsoft.documentdb/cassandraclusters | Cassandra clusters |
| microsoft.documentdb/databaseaccounts | Cosmos DB accounts |
| microsoft.documentdb/mongoclusters | MongoDB clusters |
| microsoft.eventgrid/domains | Event Grid domains |
| microsoft.eventgrid/partnernamespaces | Partner namespaces |
| microsoft.eventgrid/partnertopics | Partner topics |
| microsoft.eventgrid/systemtopics | System topics |
| microsoft.eventgrid/topics | Event Grid topics |
| microsoft.eventhub/namespaces | Event Hubs namespaces |
| microsoft.experimentation/experimentworkspaces | Experimentation workspaces |
| microsoft.healthcareapis/services | Healthcare APIs |
| microsoft.healthcareapis/workspaces/dicomservices | DICOM services |
| microsoft.healthcareapis/workspaces/fhirservices | FHIR services |
| microsoft.healthcareapis/workspaces/iotconnectors | IoT connectors |
| microsoft.insights/autoscalesettings | Autoscale settings |
| microsoft.insights/components | Application Insights components |
| microsoft.insights/datacollectionrules | Data collection rules |
| microsoft.keyvault/managedhsms | Managed HSMs |
| microsoft.keyvault/vaults | Key Vaults |
| microsoft.kusto/clusters | Azure Data Explorer clusters |
| microsoft.loadtestservice/loadtests | Load Test services |
| microsoft.logic/integrationaccounts | Logic Apps integration accounts |
| microsoft.logic/workflows | Logic Apps workflows |
| microsoft.machinelearningservices/registries | Machine Learning registries |
| microsoft.machinelearningservices/workspaces | Machine Learning workspaces |
| microsoft.machinelearningservices/workspaces/onlineendpoints | Online endpoints |
| microsoft.managednetworkfabric/networkdevices | Managed Network Fabric devices |
| microsoft.media/mediaservices | Media Services |
| microsoft.media/mediaservices/liveevents | Live events |
| microsoft.media/mediaservices/streamingendpoints | Streaming endpoints |
| microsoft.netapp/netappaccounts/capacitypools/volumes | NetApp volumes |
| microsoft.network/applicationgateways | Application Gateways |
| microsoft.network/azurefirewalls | Azure Firewalls |
| microsoft.network/bastionhosts | Bastion hosts |
| microsoft.network/dnsresolverpolicies | DNS resolver policies |
| microsoft.network/expressroutecircuits | ExpressRoute circuits |
| microsoft.network/frontdoors | Front Door |
| microsoft.network/loadbalancers | Load Balancers |
| microsoft.network/networkmanagers | Network Managers |
| microsoft.network/networkmanagers/ipampools | IPAM pools |
| microsoft.network/networksecuritygroups | Network Security Groups |
| microsoft.network/networksecurityperimeters | Network Security Perimeters |
| microsoft.network/p2svpngateways | P2S VPN Gateways |
| microsoft.network/publicipaddresses | Public IP addresses |
| microsoft.network/publicipprefixes | Public IP prefixes |
| microsoft.network/trafficmanagerprofiles | Traffic Manager profiles |
| microsoft.network/virtualnetworkgateways | Virtual Network Gateways |
| microsoft.network/virtualnetworks | Virtual Networks |
| microsoft.network/vpngateways | VPN Gateways |
| microsoft.networkanalytics/dataproducts | Network Analytics data products |
| microsoft.networkcloud/baremetalmachines | Bare Metal machines |
| microsoft.networkcloud/clusters | Network Cloud clusters |
| microsoft.networkcloud/storageappliances | Storage appliances |
| microsoft.networkfunction/azuretrafficcollectors | Azure Traffic Collectors |
| microsoft.notificationhubs/namespaces | Notification Hubs namespaces |
| microsoft.notificationhubs/namespaces/notificationhubs | Notification Hubs |
| microsoft.openenergyplatform/energyservices | Open Energy Platform |
| microsoft.operationalinsights/workspaces | Log Analytics workspaces |
| microsoft.powerbi/tenants/workspaces | Power BI workspaces |
| microsoft.powerbidedicated/capacities | Power BI Dedicated capacities |
| microsoft.purview/accounts | Microsoft Purview accounts |
| microsoft.recoveryservices/vaults | Recovery Services vaults |
| microsoft.relay/namespaces | Relay namespaces |
| microsoft.search/searchservices | Search services |
| microsoft.servicebus/namespaces | Service Bus namespaces |
| microsoft.servicenetworking/trafficcontrollers | Traffic controllers |
| microsoft.signalrservice/signalr | SignalR |
| microsoft.signalrservice/webpubsub | Web PubSub |
| microsoft.sql/managedinstances | SQL Managed Instances |
| microsoft.sql/managedinstances/databases | Managed Instance databases |
| microsoft.sql/servers/databases | SQL databases |
| microsoft.storagecache/caches | HPC Cache |
| microsoft.storagemover/storagemovers | Storage Movers |
| microsoft.streamanalytics/streamingjobs | Stream Analytics jobs |
| microsoft.synapse/workspaces | Synapse workspaces |
| microsoft.synapse/workspaces/bigdatapools | Big Data pools |
| microsoft.synapse/workspaces/kustopools | Kusto pools |
| microsoft.synapse/workspaces/scopepools | Scope pools |
| microsoft.synapse/workspaces/sqlpools | SQL pools |
| microsoft.timeseriesinsights/environments | Time Series Insights environments |
| microsoft.timeseriesinsights/environments/eventsources | Event sources |
| microsoft.videoindexer/accounts | Video Indexer accounts |
| microsoft.web/hostingenvironments | App Service Environments |
| microsoft.workloads/sapvirtualinstances | SAP Virtual Instances |

## Implementation Steps

1. **Navigate to Azure Policy**: In the Azure portal, go to the Policy service.
2. **Search for the Initiative**: Filter for initiatives under the "Monitoring" category. Look for "Enable allLogs category group resource logging for supported resources to Log Analytics".
3. **Assign the Initiative**:
   - Select the initiative and click "Assign".
   - Choose the scope (e.g., subscription).
   - Set parameters: Provide the Log Analytics workspace ID, diagnostic setting name (default: "setByPolicy-LogAnalytics"), and ensure `categoryGroup` is set to `allLogs`.
   - Enable remediation by creating a managed identity.
4. **Remediate Existing Resources**: After assignment, go to the Remediation tab and create tasks for non-compliant resources.
5. **Monitor Compliance**: View policy compliance in the Azure Policy dashboard.

## Exporting Events from Log Analytics to Event Hub

Once logs are in Log Analytics, you can configure continuous data export to an Azure Event Hub for further processing or integration with external systems like Splunk. Data export sends new log data (from the time of configuration) in JSON format without filtering, though transformations can be applied.

### Requirements
- Log Analytics workspace and Event Hub namespace in the same region.
- Permissions: Log Analytics Contributor, Azure Event Hubs Data Owner, and Log Analytics Reader.
- Register the `Microsoft.Insights` resource provider in your subscription.
- Use a dedicated Event Hub namespace (Standard, Premium, or Dedicated tier) with Auto-inflate enabled.
- Maximum 10 export rules per workspace; supported tables must be in Analytics or Basic plans.

### Steps
1. **Prepare Event Hub**:
   - Create an Event Hubs namespace in the same region as your Log Analytics workspace.
   - Optionally, create specific Event Hubs (e.g., named `am-<table-name>` for each table like `SecurityEvent`).
   - Enable firewall exceptions for trusted Azure services if using virtual networks.

2. **Register Resource Provider** (if not already done):
   - In Azure portal: Subscriptions > Your Subscription > Resource providers > Register `Microsoft.Insights`.
   - Or via Azure CLI: `az provider register --namespace 'Microsoft.Insights'`.

3. **Configure Data Export Rule**:
   - In Azure portal, go to your Log Analytics workspace > Settings > Data Export.
   - Click "New export rule".
   - **Source tab**: Select tables to export (e.g., `AzureDiagnostics`, `SecurityEvent`).
   - **Destination tab**: Choose "Event Hubs" as destination.
     - Select the Event Hubs namespace.
     - Optionally, specify an Event Hub name (default creates `am-<table-name>` per table).
   - Click "Create". Export starts after ~30 minutes.

4. **Monitor Export**:
   - Use metrics like Bytes Exported, Export Failures, and Records Exported in Log Analytics.
   - Set alerts in Event Hubs for incoming bytes, requests, and quota errors.

5. **Manage Rules**:
   - View, disable, update, or delete rules from the Data Export page.
   - Note: Exported data may have duplicates in rare failure scenarios; retries last up to 12 hours.

### Limitations
- Exports only new data; no historical backfill.
- Not all tables are supported (e.g., custom logs via HTTP API aren't exportable).
- Data charged based on exported bytes; monitor for costs.

## Exporting Events from Event Hub to Splunk

To ingest logs from Azure Event Hub into Splunk, use one of the following methods. The recommended approach is Splunk's Data Manager or Add-ons for seamless integration.

### Method 1: Splunk Data Manager (Recommended for Splunk Cloud)
Splunk Data Manager simplifies ingesting Azure Event Hubs data into Splunk Cloud.

1. **Set Up Data Manager**:
   - In Splunk Cloud, navigate to Data Manager > Create New Input > Azure Event Hubs.
   - Provide Azure credentials: Subscription ID, Tenant ID, Client ID, and Client Secret (from an App Registration with Event Hubs Data Receiver role).
   - Select the Event Hubs namespace and specific Event Hub.

2. **Configure Input**:
   - Specify the index, sourcetype (e.g., `mscs:azure:eventhub`), and any filters.
   - Enable the input to start pulling data.

3. **Migration (if using older methods)**:
   - If migrating from add-ons or Azure Functions, disable old inputs, recreate in Data Manager, and verify data flow.

4. **Verify**:
   - In Splunk, go to Search > Data Summary > Sourcetypes > `mscs:azure:eventhub` to confirm ingestion.

### Method 2: Microsoft Azure Add-on for Splunk
Install the add-on from Splunkbase (https://splunkbase.splunk.com/app/3536/).

1. **Install Add-on**:
   - Download and install on a Splunk Heavy Forwarder or Indexer.

2. **Configure Input**:
   - Go to the add-on configuration > Inputs > Create New Input > Azure Event Hub.
   - Enter Event Hub connection details: Namespace, Event Hub name, Consumer Group (default: `$Default`), and Azure credentials.

3. **Start Ingestion**:
   - Enable the input. The add-on pulls events and parses them into Splunk.

### Method 3: Azure Logic Apps or Functions to Splunk HEC
For push-based ingestion:

1. **Set Up Splunk HEC**:
   - In Splunk, enable HTTP Event Collector (HEC) and generate a token.

2. **Create Azure Logic App**:
   - Trigger: When a message is received from Event Hub.
   - Action: Send event to Splunk HEC endpoint via HTTP POST with the token.

3. **Alternative: Azure Function**:
   - Use an Event Hub-triggered Function to forward messages to Splunk HEC.

### Best Practices
- Use a dedicated consumer group in Event Hub for Splunk to avoid conflicts.
- Monitor for throttling: Scale Event Hub throughput units if needed.
- Parse JSON logs in Splunk for better searchability.
- Test with sample data to ensure end-to-end flow.

For more details, refer to Splunk documentation on Azure integrations or Microsoft Learn for Azure Monitor.