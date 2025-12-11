# Testing Azure Cosmos DB Query Codebundle

This directory contains test infrastructure for the `azure-cosmosdb-query` generic codebundle.

## Prerequisites

1. **Azure CLI**: Install and authenticate
   ```bash
   az login
   az account set --subscription <your-subscription-id>
   ```

2. **Task (Taskfile)**: Install from https://taskfile.dev/#/installation
   ```bash
   # macOS
   brew install go-task/tap/go-task
   
   # Linux
   sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b ~/.local/bin
   
   # Windows
   choco install go-task
   ```

3. **Python packages**:
   ```bash
   pip3 install azure-cosmos
   
   # Or let the Taskfile install it automatically
   cd codebundles/azure-cosmosdb-query/.test
   task install-python-deps
   ```


## Quick Start

### 0. Check Prerequisites (Optional but Recommended)

```bash
cd codebundles/azure-cosmosdb-query
task check-prerequisites
```

This verifies:
- Azure CLI is installed and you're logged in
- Python and required packages are available
- Robot Framework is installed

### 1. Set Up Test Infrastructure

This creates:
- Installs required Python packages (if needed)
- Registers Azure provider (if needed)
- Azure Resource Group
- Cosmos DB Account
- Database and Container
- Test data with various scenarios

```bash
task setup
```

**Note**: This takes approximately 5-10 minutes as Cosmos DB provisioning takes time.

**What happens automatically:**
- Python dependencies are installed (azure-cosmos package)
- Microsoft.DocumentDB provider is registered (first time only, adds 1-2 minutes)
- All Azure resources are created
- Test data is populated

### 2. Run Tests

```bash
task test
```

This runs:
- Syntax validation
- Integration tests against real Cosmos DB

### 3. Check Status

```bash
task status
```

### 4. Clean Up

When done testing, delete all infrastructure:

```bash
task cleanup
```

## Available Tasks

```bash
task help        # Show help
task setup       # Create all infrastructure
task test        # Run all tests
task status      # Check infrastructure status
task logs        # View Cosmos DB metrics
task cleanup     # Delete all infrastructure
```

## Test Data

The test data includes:

| Document ID | Status | Type | Purpose |
|------------|--------|------|---------|
| doc-001, doc-002, doc-003 | completed/processing | order | Healthy documents |
| doc-004, doc-005, doc-006 | error | order | Error documents for testing |
| doc-007 | pending | order | High retry count (8 retries) |
| doc-008 | pending | order | Stale document (7 days old) |
| user-001 | active | user | Different document type |
| user-002 | suspended | user | Suspended user |

## Example Queries to Test

### 1. Find All Error Documents
```sql
SELECT * FROM c WHERE c.status = 'error'
```
Expected: 3 documents (doc-004, doc-005, doc-006)

### 2. Count Error Documents
```sql
SELECT COUNT(1) FROM c WHERE c.status = 'error'
```
Expected: 3

### 3. Failed Orders
```sql
SELECT * FROM c WHERE c.failed = true
```
Expected: 3 documents

### 4. High Retry Count
```sql
SELECT * FROM c WHERE c.retryCount > 5
```
Expected: 1 document (doc-007)

### 5. Recent Errors (Last Hour)
```sql
SELECT * FROM c WHERE c.status = 'error' ORDER BY c.timestamp DESC
```
Expected: 3 documents, sorted by timestamp

### 6. Parameterized Query
```sql
SELECT * FROM c WHERE c.status = @status
```
Parameters: `{"@status": "error"}`
Expected: 3 documents

## Manual Testing with Robot Framework

After setup, you can manually test the codebundle:

```bash
# Get credentials
task show-credentials

# Set environment variables (use output from above)
export COSMOSDB_ENDPOINT="https://rw-cosmosdb-test-XXXXX.documents.azure.com:443/"
export COSMOSDB_KEY="<key from output>"
export DATABASE_NAME="testdb"
export CONTAINER_NAME="testcontainer"

# Test query for errors
export COSMOSDB_QUERY="SELECT * FROM c WHERE c.status = 'error'"
export TASK_TITLE="Find error documents"

# Run the codebundle
robot runbook.robot
```

## Testing the Issue Detection Variant

```bash
cd ../azure-cosmosdb-query-issue

# This should raise an issue (errors found)
export COSMOSDB_QUERY="SELECT * FROM c WHERE c.status = 'error'"
export ISSUE_TITLE="Found error documents"
robot runbook.robot

# This should NOT raise an issue (no results)
export COSMOSDB_QUERY="SELECT * FROM c WHERE c.status = 'nonexistent'"
robot runbook.robot
```

## Cost Considerations

The test infrastructure costs approximately:
- **Cosmos DB**: ~$0.008/hour (400 RU/s, free tier may apply)
- **Resource Group**: Free

**Remember to run `task cleanup` when done to avoid charges!**

## Troubleshooting

### Error: "MissingSubscriptionRegistration for Microsoft.DocumentDB"
This means your Azure subscription hasn't been registered for Cosmos DB yet. The `task setup` command automatically handles this, but if you see this error:

```bash
# Manual registration
task register-provider

# Or directly with Azure CLI
az provider register --namespace Microsoft.DocumentDB
az provider wait --namespace Microsoft.DocumentDB --created
```

This is a one-time setup per Azure subscription and takes 1-2 minutes.

### Error: "Account name already exists"
The account name includes a timestamp, but if you run setup very quickly, you might hit this. Just run `task cleanup` and then `task setup` again.

### Error: "Subscription not found"
Make sure you're logged into Azure CLI and have the correct subscription selected:
```bash
az login
az account list --output table
az account set --subscription <subscription-id>
```

### Error: "No test data found"
Run the populate task manually:
```bash
task populate-test-data
```

### Integration tests fail
Verify credentials and connectivity:
```bash
task show-credentials
task status
```

## Files

- **Taskfile.yml**: Task automation for infrastructure management
- **populate_test_data.py**: Script to create test documents
- **run_integration_tests.py**: Integration test suite
- **README.md**: This file

