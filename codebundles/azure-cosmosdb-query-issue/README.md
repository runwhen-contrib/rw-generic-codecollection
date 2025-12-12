# Azure Cosmos DB Query with Issue Detection
A generic codebundle for executing user-provided SQL queries against Azure Cosmos DB and raising issues when results are found. Users configure queries that filter for error/problem conditions.

## TaskSet
Executes a user-provided Cosmos DB SQL query and raises an issue if results are returned (indicating problems were found).

## SLI
Executes a user-provided Cosmos DB SQL query and pushes a health metric: 1 (healthy) if no results, 0 (unhealthy) if results are found.

## Requirements
- **COSMOSDB_ENDPOINT** (user variable): The Cosmos DB account endpoint URL (e.g., `https://myaccount.documents.azure.com:443/`)
- **Authentication** (secret, one of):
  - **azure_credentials** (recommended): Service principal credentials with AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_CLIENT_SECRET
  - **cosmosdb_key** (fallback): The Cosmos DB account primary or secondary key
- **DATABASE_NAME** (user variable): The name of the Cosmos DB database
- **CONTAINER_NAME** (user variable): The name of the Cosmos DB container
- **COSMOSDB_QUERY** (user variable): The SQL query to execute
- **QUERY_PARAMETERS** (user variable, optional): JSON string of query parameters
- **TASK_TITLE** (user variable, optional): Custom name for the task
- **ISSUE_TITLE** (user variable, optional): Title for the issue if raised
- **ISSUE_SEVERITY** (user variable, optional): Severity level 1-4 (default: 3)
- **ISSUE_NEXT_STEPS** (user variable, optional): Next steps guidance
- **ISSUE_DETAILS** (user variable, optional): Issue details
- **ISSUE_ON** (user variable, optional): When to raise issue - see conditions below (default: "results_found")
- **ISSUE_THRESHOLD** (user variable, optional): Numeric threshold for count_above/count_below (default: 0)

## Authentication
This codebundle supports two authentication methods with automatic fallback:
1. **Azure AD / Service Principal** (recommended) - Uses `azure_credentials` secret
2. **Key-based authentication** (fallback) - Uses `cosmosdb_key` secret

The codebundle will automatically try service principal authentication first, and if that's not available, it will fall back to key-based authentication. You only need to configure one method.

### Service Principal Setup (Azure AD Authentication)
For service principal authentication, you need **Cosmos DB Data Plane RBAC** permissions (not Azure ARM control plane roles):

**Required Role:** `Cosmos DB Built-in Data Reader` (Role ID: `00000000-0000-0000-0000-000000000001`)

```bash
# Grant data plane RBAC permissions
az cosmosdb sql role assignment create \
  --account-name <cosmos-account-name> \
  --resource-group <resource-group> \
  --scope "/" \
  --principal-id <service-principal-object-id> \
  --role-definition-id 00000000-0000-0000-0000-000000000001
```

**Note:** These are **data plane** roles for accessing Cosmos DB data, not the Azure ARM control plane roles you see in the Azure Portal (like "Cosmos DB Account Reader" or "Cosmos DB Operator"). Data plane roles are managed separately via the Azure CLI.

## Issue Conditions

This codebundle supports **flexible issue detection** using the `ISSUE_ON` parameter:

### `results_found` (default)
Raise issue when query returns any results.
- **Use case:** Error detection - looking for problems
- **Healthy:** No results (SLI = 1)
- **Unhealthy:** Results found (SLI = 0, issue raised)

### `no_results`
Raise issue when query returns NO results.
- **Use case:** Validation - expecting data to exist
- **Healthy:** Results found (SLI = 1)
- **Unhealthy:** No results (SLI = 0, issue raised)

### `count_above`
Raise issue when result count exceeds a threshold.
- **Use case:** Volume monitoring - too many items
- **Requires:** `ISSUE_THRESHOLD` (e.g., 100)
- **Healthy:** Count ≤ threshold (SLI = 1)
- **Unhealthy:** Count > threshold (SLI = 0, issue raised)

### `count_below`
Raise issue when result count is below a threshold.
- **Use case:** Minimum requirements - too few items
- **Requires:** `ISSUE_THRESHOLD` (e.g., 10)
- **Healthy:** Count ≥ threshold (SLI = 1)
- **Unhealthy:** Count < threshold (SLI = 0, issue raised)

## Usage Examples

### Example 1: Detect Error Documents (results_found - default)
```bash
DATABASE_NAME="mydatabase"
CONTAINER_NAME="mycontainer"
COSMOSDB_QUERY="SELECT * FROM c WHERE c.status = 'error' ORDER BY c._ts DESC"
ISSUE_ON="results_found"  # Default - can be omitted
TASK_TITLE="Detect error documents"
ISSUE_TITLE="Found error documents in Cosmos DB"
ISSUE_SEVERITY=2
```
**Behavior:** Issue raised if ANY errors are found

---

### Example 2: Validate Expected Data Exists (no_results)
```bash
DATABASE_NAME="inventory"
CONTAINER_NAME="products"
COSMOSDB_QUERY="SELECT * FROM c WHERE c.category = 'featured' AND c.inStock = true"
ISSUE_ON="no_results"
TASK_TITLE="Validate featured products exist"
ISSUE_TITLE="No featured products in stock"
ISSUE_SEVERITY=2
ISSUE_NEXT_STEPS="Add featured products to inventory"
```
**Behavior:** Issue raised if NO featured products found (expecting data to exist)

---

### Example 3: Monitor High Volume (count_above)
```bash
DATABASE_NAME="logs"
CONTAINER_NAME="events"
COSMOSDB_QUERY="SELECT VALUE COUNT(1) FROM c WHERE c.severity = 'error' AND c._ts > GetCurrentTimestamp() - 3600000"
ISSUE_ON="count_above"
ISSUE_THRESHOLD=100
TASK_TITLE="Monitor error volume"
ISSUE_TITLE="High error rate detected"
ISSUE_SEVERITY=1
ISSUE_DETAILS="Error count exceeded threshold in the last hour"
```
**Behavior:** Issue raised if more than 100 errors in last hour

---

### Example 4: Monitor Minimum Capacity (count_below)
```bash
DATABASE_NAME="inventory"
CONTAINER_NAME="products"
COSMOSDB_QUERY="SELECT VALUE COUNT(1) FROM c WHERE c.inStock = true"
ISSUE_ON="count_below"
ISSUE_THRESHOLD=10
TASK_TITLE="Monitor minimum inventory"
ISSUE_TITLE="Low inventory alert"
ISSUE_SEVERITY=3
ISSUE_NEXT_STEPS="Reorder products to maintain minimum stock levels"
```
**Behavior:** Issue raised if fewer than 10 items in stock

---

### Example 5: Parameterized High-Value Errors
```bash
DATABASE_NAME="transactions"
CONTAINER_NAME="orders"
COSMOSDB_QUERY="SELECT * FROM c WHERE c.status = @status AND c.amount > @threshold"
QUERY_PARAMETERS='{"@status": "failed", "@threshold": 1000}'
ISSUE_ON="results_found"
TASK_TITLE="Detect high-value failed transactions"
ISSUE_TITLE="High-value transaction failures detected"
ISSUE_SEVERITY=1
```
**Behavior:** Issue raised if any high-value failures found

## Query Guidelines

### Error Detection Queries
- Query should filter for error/problem conditions only
- Examples:
  - `SELECT * FROM c WHERE c.status = 'error'`
  - `SELECT * FROM c WHERE c.failed = true`
  - `SELECT * FROM c WHERE c.retryCount > 5`

### Parameterized Queries (Recommended)
- Use parameters for security and performance:
  - Query: `SELECT * FROM c WHERE c.status = @status`
  - Parameters: `{"@status": "error"}`

### Time-Based Filtering
- Filter for recent errors:
  - `SELECT * FROM c WHERE c.status = 'error' AND c._ts > @startTime`
  - `SELECT * FROM c WHERE c.lastUpdated < @threshold`

## Behavior

### TaskSet
- Query executes and returns results
- If count > 0:
  - ✅ Issue is raised with configurable title/severity
  - ✅ Results are included in the issue details
  - ✅ Results are added to the report
- If count = 0:
  - ✅ No issue raised
  - ✅ "No results found" message added to report

### SLI
- Query executes and counts results
- If count > 0: Push metric **0** (unhealthy)
- If count = 0: Push metric **1** (healthy)

## Features
- Execute any SQL query against Cosmos DB containers
- Automatic issue raising when problems are detected
- Support for parameterized queries
- Configurable issue title, severity, and next steps
- Health metrics for monitoring
- Cross-partition query support
- Automatic error handling with severity 3 issue creation on connection or query failures

## Notes
- Uses the Azure Cosmos DB Python SDK (`azure-cosmos`)
- Design your queries to return results **only when problems exist**
- Empty results = healthy state
- Use parameterized queries to prevent injection attacks
- Queries run with cross-partition support enabled

