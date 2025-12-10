# Azure Cosmos DB Query with Issue Detection
A generic codebundle for executing user-provided SQL queries against Azure Cosmos DB and raising issues when results are found. Users configure queries that filter for error/problem conditions.

## TaskSet
Executes a user-provided Cosmos DB SQL query and raises an issue if results are returned (indicating problems were found).

## SLI
Executes a user-provided Cosmos DB SQL query and pushes a health metric: 1 (healthy) if no results, 0 (unhealthy) if results are found.

## Requirements
- **cosmosdb_endpoint** (secret): The Cosmos DB account endpoint URL (e.g., `https://myaccount.documents.azure.com:443/`)
- **cosmosdb_key** (secret): The Cosmos DB account key
- **DATABASE_NAME** (user variable): The name of the Cosmos DB database
- **CONTAINER_NAME** (user variable): The name of the Cosmos DB container
- **COSMOSDB_QUERY** (user variable): The SQL query to execute (should filter for errors/problems)
- **QUERY_PARAMETERS** (user variable, optional): JSON string of query parameters
- **TASK_TITLE** (user variable, optional): Custom name for the task
- **ISSUE_TITLE** (user variable, optional): Title for the issue if raised
- **ISSUE_SEVERITY** (user variable, optional): Severity level 1-4 (default: 3)
- **ISSUE_NEXT_STEPS** (user variable, optional): Next steps guidance
- **ISSUE_DETAILS** (user variable, optional): Issue details

## Usage Philosophy
This codebundle is designed for **error detection**:
- Your query should filter for **problematic conditions only**
- **No results** = healthy state (SLI pushes 1)
- **Results found** = unhealthy state (SLI pushes 0, TaskSet raises issue)

## Usage Examples

### TaskSet: Detect Error Documents
```
DATABASE_NAME="mydatabase"
CONTAINER_NAME="mycontainer"
COSMOSDB_QUERY="SELECT * FROM c WHERE c.status = 'error' ORDER BY c._ts DESC"
TASK_TITLE="Detect error documents in Cosmos DB"
ISSUE_TITLE="Found error documents in Cosmos DB"
ISSUE_SEVERITY=2
ISSUE_NEXT_STEPS="Review the error documents and investigate the root cause."
```

### TaskSet: Detect Failed Transactions
```
DATABASE_NAME="transactions"
CONTAINER_NAME="orders"
COSMOSDB_QUERY="SELECT c.id, c.customerId, c.errorMessage FROM c WHERE c.failed = true AND c._ts > @startTime"
QUERY_PARAMETERS='{"@startTime": 1704067200}'
TASK_TITLE="Detect failed transactions in last hour"
ISSUE_TITLE="Found failed transactions"
ISSUE_SEVERITY=1
```

### SLI: Monitor for Errors
```
DATABASE_NAME="mydatabase"
CONTAINER_NAME="mycontainer"
COSMOSDB_QUERY="SELECT * FROM c WHERE c.status = 'error'"
TASK_TITLE="Monitor for error documents"
```

### SLI: Monitor Stale Records
```
DATABASE_NAME="mydatabase"
CONTAINER_NAME="mycontainer"
COSMOSDB_QUERY="SELECT * FROM c WHERE c.lastUpdated < @threshold"
QUERY_PARAMETERS='{"@threshold": "2024-01-01T00:00:00Z"}'
TASK_TITLE="Monitor for stale records"
```

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

## Notes
- Uses the Azure Cosmos DB Python SDK (`azure-cosmos`)
- Design your queries to return results **only when problems exist**
- Empty results = healthy state
- Use parameterized queries to prevent injection attacks
- Queries run with cross-partition support enabled

