# Azure Cosmos DB Query Generic
A generic codebundle for executing user-provided SQL queries against Azure Cosmos DB using the Python SDK. Users configure their own queries, database, and container names.

## TaskSet
Executes a user-provided Cosmos DB SQL query and adds the results to the report.

Example: Query for error documents
```sql
SELECT * FROM c WHERE c.status = 'error' ORDER BY c._ts DESC
```

## SLI
Executes a user-provided Cosmos DB SQL query and pushes the count of results as a metric.

Example: Count error documents
```sql
SELECT COUNT(1) FROM c WHERE c.status = 'error'
```

## Requirements
- **cosmosdb_endpoint** (secret): The Cosmos DB account endpoint URL (e.g., `https://myaccount.documents.azure.com:443/`)
- **cosmosdb_key** (secret): The Cosmos DB account key
- **DATABASE_NAME** (user variable): The name of the Cosmos DB database
- **CONTAINER_NAME** (user variable): The name of the Cosmos DB container
- **COSMOSDB_QUERY** (user variable): The SQL query to execute
- **QUERY_PARAMETERS** (user variable, optional): JSON string of query parameters for parameterized queries
- **TASK_TITLE** (user variable, optional): Custom name for the task

## Usage Examples

### TaskSet: Find Error Documents
```
DATABASE_NAME="mydatabase"
CONTAINER_NAME="mycontainer"
COSMOSDB_QUERY="SELECT * FROM c WHERE c.status = 'error' ORDER BY c._ts DESC OFFSET 0 LIMIT 100"
TASK_TITLE="Find error documents in Cosmos DB"
```

### TaskSet: Query with Parameters
```
DATABASE_NAME="mydatabase"
CONTAINER_NAME="mycontainer"
COSMOSDB_QUERY="SELECT * FROM c WHERE c.status = @status AND c.timestamp > @startTime"
QUERY_PARAMETERS='{"@status": "error", "@startTime": "2024-01-01T00:00:00Z"}'
TASK_TITLE="Find errors since start time"
```

### SLI: Count Error Documents
```
DATABASE_NAME="mydatabase"
CONTAINER_NAME="mycontainer"
COSMOSDB_QUERY="SELECT COUNT(1) FROM c WHERE c.status = 'error'"
TASK_TITLE="Count error documents in Cosmos DB"
```

### SLI: Count Items by Status
```
DATABASE_NAME="mydatabase"
CONTAINER_NAME="mycontainer"
COSMOSDB_QUERY="SELECT COUNT(1) FROM c WHERE c.status = @status"
QUERY_PARAMETERS='{"@status": "error"}'
TASK_TITLE="Count documents by status"
```

### TaskSet: Get Recent Failed Transactions
```
DATABASE_NAME="transactions"
CONTAINER_NAME="orders"
COSMOSDB_QUERY="SELECT c.id, c.customerId, c.errorMessage, c._ts FROM c WHERE c.failed = true ORDER BY c._ts DESC OFFSET 0 LIMIT 50"
TASK_TITLE="Get recent failed transactions"
```

## Query Guidelines

### Basic Queries
- Use standard SQL syntax: `SELECT * FROM c WHERE c.field = 'value'`
- `c` is the alias for the container
- Use `ORDER BY c._ts DESC` to sort by timestamp (newest first)
- Use `OFFSET 0 LIMIT 100` to limit results

### Parameterized Queries (Recommended for Security)
- Use `@paramName` in your query: `SELECT * FROM c WHERE c.status = @status`
- Provide parameters as JSON: `QUERY_PARAMETERS='{"@status": "error"}'`
- Prevents injection attacks and improves performance

### Count Queries for SLI
- Use `SELECT COUNT(1) FROM c WHERE condition` to count matching items
- The SLI will extract the count value and push it as a metric
- Or use any SELECT query - the SLI will count the number of rows returned

### Cross-Partition Queries
- All queries automatically enable cross-partition query support
- Performance may vary based on query complexity and data distribution

## Features
- Execute any SQL query against Cosmos DB containers
- Support for parameterized queries (recommended for security)
- Automatic cross-partition query support
- Count query results for metrics
- Full JSON result output for TaskSet
- Flexible query configuration per use case

## Notes
- Uses the Azure Cosmos DB Python SDK (`azure-cosmos`)
- Queries run with cross-partition support enabled
- For SLI, if your query doesn't use COUNT, it will return the number of rows returned
- Results are returned as JSON strings
- Parameterized queries are recommended to prevent injection and improve caching

