#!/usr/bin/env python3
"""
Run integration tests for the Azure Cosmos DB generic query codebundle.
"""

import argparse
import subprocess
import sys
from azure.cosmos import CosmosClient


def get_cosmos_credentials(account_name, resource_group):
    """Get Cosmos DB endpoint and key from Azure CLI."""
    endpoint_cmd = [
        "az", "cosmosdb", "show",
        "--name", account_name,
        "--resource-group", resource_group,
        "--query", "documentEndpoint",
        "-o", "tsv"
    ]
    endpoint = subprocess.check_output(endpoint_cmd).decode().strip()
    
    key_cmd = [
        "az", "cosmosdb", "keys", "list",
        "--name", account_name,
        "--resource-group", resource_group,
        "--query", "primaryMasterKey",
        "-o", "tsv"
    ]
    key = subprocess.check_output(key_cmd).decode().strip()
    
    return endpoint, key


def test_query_library(endpoint, key, database_name, container_name):
    """Test the RW.Azure.Cosmosdb library directly."""
    print("\n" + "="*60)
    print("Testing RW.Azure.Cosmosdb Library")
    print("="*60)
    
    sys.path.insert(0, 'libraries')
    from RW.Azure.Cosmosdb import Cosmosdb
    
    cosmosdb = Cosmosdb()
    
    # Test 1: Connect
    print("\nTest 1: Connect to Cosmos DB")
    result = cosmosdb.connect_to_cosmosdb(endpoint, key)
    print(f"  ✅ {result}")
    
    # Test 2: Query for all documents
    print("\nTest 2: Query all documents")
    result = cosmosdb.query_container(database_name, container_name, "SELECT * FROM c")
    print(f"  ✅ Found documents (first 200 chars): {result[:200]}...")
    
    # Test 3: Query for error documents
    print("\nTest 3: Query for error documents")
    result = cosmosdb.query_container(
        database_name, 
        container_name, 
        "SELECT * FROM c WHERE c.status = 'error'"
    )
    print(f"  ✅ Found error documents: {result[:200]}...")
    
    # Test 4: Count error documents
    print("\nTest 4: Count error documents")
    count = cosmosdb.count_query_results(
        database_name,
        container_name,
        "SELECT COUNT(1) FROM c WHERE c.status = 'error'"
    )
    print(f"  ✅ Error document count: {count}")
    assert count > 0, "Expected to find error documents"
    
    # Test 5: Parameterized query
    print("\nTest 5: Parameterized query")
    result = cosmosdb.query_container(
        database_name,
        container_name,
        "SELECT * FROM c WHERE c.status = @status",
        '{"@status": "error"}'
    )
    print(f"  ✅ Parameterized query results: {result[:200]}...")
    
    # Test 6: Query with no results
    print("\nTest 6: Query with no results")
    count = cosmosdb.count_query_results(
        database_name,
        container_name,
        "SELECT * FROM c WHERE c.status = 'nonexistent'"
    )
    print(f"  ✅ Count for non-existent status: {count}")
    assert count == 0, "Expected 0 results"
    
    # Test 7: Failed orders
    print("\nTest 7: Query for failed orders")
    count = cosmosdb.count_query_results(
        database_name,
        container_name,
        "SELECT * FROM c WHERE c.failed = true"
    )
    print(f"  ✅ Failed order count: {count}")
    
    # Test 8: High retry count
    print("\nTest 8: Query for high retry count")
    result = cosmosdb.query_container(
        database_name,
        container_name,
        "SELECT c.id, c.name, c.retryCount FROM c WHERE c.retryCount > 5"
    )
    print(f"  ✅ High retry count results: {result[:200]}...")
    
    print("\n" + "="*60)
    print("✅ All library tests passed!")
    print("="*60)


def verify_test_data(endpoint, key, database_name, container_name):
    """Verify test data exists in Cosmos DB."""
    print("\n" + "="*60)
    print("Verifying Test Data")
    print("="*60)
    
    client = CosmosClient(endpoint, key)
    database = client.get_database_client(database_name)
    container = database.get_container_client(container_name)
    
    # Count total documents
    items = list(container.query_items(
        query="SELECT VALUE COUNT(1) FROM c",
        enable_cross_partition_query=True
    ))
    total_count = items[0] if items else 0
    print(f"\nTotal documents: {total_count}")
    
    # Count error documents
    error_items = list(container.query_items(
        query="SELECT VALUE COUNT(1) FROM c WHERE c.status = 'error'",
        enable_cross_partition_query=True
    ))
    error_count = error_items[0] if error_items else 0
    print(f"Error documents: {error_count}")
    
    # Count failed orders
    failed_items = list(container.query_items(
        query="SELECT VALUE COUNT(1) FROM c WHERE c.failed = true",
        enable_cross_partition_query=True
    ))
    failed_count = failed_items[0] if failed_items else 0
    print(f"Failed orders: {failed_count}")
    
    if total_count == 0:
        print("\n❌ ERROR: No test data found. Run 'task populate-test-data' first.")
        sys.exit(1)
    
    print("\n✅ Test data verification passed!")


def main():
    parser = argparse.ArgumentParser(description="Run integration tests")
    parser.add_argument("--account-name", required=True, help="Cosmos DB account name")
    parser.add_argument("--resource-group", required=True, help="Azure resource group")
    parser.add_argument("--database", required=True, help="Database name")
    parser.add_argument("--container", required=True, help="Container name")
    
    args = parser.parse_args()
    
    print("Getting Cosmos DB credentials...")
    endpoint, key = get_cosmos_credentials(args.account_name, args.resource_group)
    
    print(f"Endpoint: {endpoint}")
    print(f"Database: {args.database}")
    print(f"Container: {args.container}")
    
    try:
        # Verify test data exists
        verify_test_data(endpoint, key, args.database, args.container)
        
        # Test the library
        test_query_library(endpoint, key, args.database, args.container)
        
        print("\n" + "="*60)
        print("🎉 All integration tests passed successfully!")
        print("="*60)
        print("\nYou can now use these credentials to test the codebundle:")
        print(f"  cosmosdb_endpoint={endpoint}")
        print(f"  cosmosdb_key=<use: az cosmosdb keys list --name {args.account_name} --resource-group {args.resource_group}>")
        print(f"  DATABASE_NAME={args.database}")
        print(f"  CONTAINER_NAME={args.container}")
        
    except Exception as e:
        print(f"\n❌ Test failed: {str(e)}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()

