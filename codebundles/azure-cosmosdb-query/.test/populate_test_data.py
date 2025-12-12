#!/usr/bin/env python3
"""
Populate Azure Cosmos DB with test data for testing the generic query codebundle.
"""

import argparse
import json
import subprocess
from datetime import datetime, timedelta
from azure.cosmos import CosmosClient


def get_cosmos_credentials(account_name, resource_group):
    """Get Cosmos DB endpoint and key from Azure CLI."""
    # Get endpoint
    endpoint_cmd = [
        "az", "cosmosdb", "show",
        "--name", account_name,
        "--resource-group", resource_group,
        "--query", "documentEndpoint",
        "-o", "tsv"
    ]
    endpoint = subprocess.check_output(endpoint_cmd).decode().strip()
    
    # Get key
    key_cmd = [
        "az", "cosmosdb", "keys", "list",
        "--name", account_name,
        "--resource-group", resource_group,
        "--query", "primaryMasterKey",
        "-o", "tsv"
    ]
    key = subprocess.check_output(key_cmd).decode().strip()
    
    return endpoint, key


def create_test_documents():
    """Create test documents with various scenarios."""
    base_time = datetime.utcnow()
    
    documents = [
        # Healthy documents
        {
            "id": "doc-001",
            "name": "Order 001",
            "status": "completed",
            "type": "order",
            "customerId": "cust-001",
            "amount": 99.99,
            "timestamp": (base_time - timedelta(hours=1)).isoformat(),
            "failed": False
        },
        {
            "id": "doc-002",
            "name": "Order 002",
            "status": "completed",
            "type": "order",
            "customerId": "cust-002",
            "amount": 149.99,
            "timestamp": (base_time - timedelta(hours=2)).isoformat(),
            "failed": False
        },
        {
            "id": "doc-003",
            "name": "Order 003",
            "status": "processing",
            "type": "order",
            "customerId": "cust-003",
            "amount": 79.99,
            "timestamp": (base_time - timedelta(minutes=30)).isoformat(),
            "failed": False
        },
        # Error documents (for testing error detection)
        {
            "id": "doc-004",
            "name": "Order 004",
            "status": "error",
            "type": "order",
            "customerId": "cust-004",
            "amount": 199.99,
            "errorMessage": "Payment processing failed",
            "errorCode": "PAYMENT_FAILED",
            "timestamp": (base_time - timedelta(minutes=15)).isoformat(),
            "failed": True,
            "retryCount": 3
        },
        {
            "id": "doc-005",
            "name": "Order 005",
            "status": "error",
            "type": "order",
            "customerId": "cust-005",
            "amount": 299.99,
            "errorMessage": "Insufficient inventory",
            "errorCode": "INVENTORY_ERROR",
            "timestamp": (base_time - timedelta(minutes=45)).isoformat(),
            "failed": True,
            "retryCount": 1
        },
        {
            "id": "doc-006",
            "name": "Order 006",
            "status": "error",
            "type": "order",
            "customerId": "cust-006",
            "amount": 49.99,
            "errorMessage": "Invalid shipping address",
            "errorCode": "VALIDATION_ERROR",
            "timestamp": (base_time - timedelta(hours=3)).isoformat(),
            "failed": True,
            "retryCount": 0
        },
        # High retry count (for testing threshold queries)
        {
            "id": "doc-007",
            "name": "Order 007",
            "status": "pending",
            "type": "order",
            "customerId": "cust-007",
            "amount": 129.99,
            "timestamp": (base_time - timedelta(hours=6)).isoformat(),
            "failed": False,
            "retryCount": 8
        },
        # Stale document (old timestamp)
        {
            "id": "doc-008",
            "name": "Order 008",
            "status": "pending",
            "type": "order",
            "customerId": "cust-008",
            "amount": 89.99,
            "timestamp": (base_time - timedelta(days=7)).isoformat(),
            "lastUpdated": (base_time - timedelta(days=7)).isoformat(),
            "failed": False,
            "retryCount": 0
        },
        # Different document types
        {
            "id": "user-001",
            "name": "Test User 1",
            "type": "user",
            "email": "user1@example.com",
            "status": "active",
            "timestamp": (base_time - timedelta(days=1)).isoformat()
        },
        {
            "id": "user-002",
            "name": "Test User 2",
            "type": "user",
            "email": "user2@example.com",
            "status": "suspended",
            "suspensionReason": "Account security review",
            "timestamp": (base_time - timedelta(hours=12)).isoformat()
        }
    ]
    
    return documents


def populate_data(account_name, resource_group, database_name, container_name):
    """Populate Cosmos DB with test data."""
    print(f"Getting Cosmos DB credentials for account: {account_name}")
    endpoint, key = get_cosmos_credentials(account_name, resource_group)
    
    print(f"Connecting to Cosmos DB: {endpoint}")
    client = CosmosClient(endpoint, key)
    
    print(f"Getting database: {database_name}")
    database = client.get_database_client(database_name)
    
    print(f"Getting container: {container_name}")
    container = database.get_container_client(container_name)
    
    print("Creating test documents...")
    documents = create_test_documents()
    
    for doc in documents:
        print(f"  Creating document: {doc['id']} ({doc.get('status', 'N/A')})")
        container.upsert_item(doc)
    
    print(f"\n✅ Successfully created {len(documents)} test documents!")
    print("\nTest data summary:")
    print(f"  - Total documents: {len(documents)}")
    print(f"  - Error documents: {sum(1 for d in documents if d.get('status') == 'error')}")
    print(f"  - Failed orders: {sum(1 for d in documents if d.get('failed') == True)}")
    print(f"  - High retry count: {sum(1 for d in documents if d.get('retryCount', 0) > 5)}")
    
    print("\nExample queries to test:")
    print(f"  1. Find errors: SELECT * FROM c WHERE c.status = 'error'")
    print(f"  2. Count errors: SELECT COUNT(1) FROM c WHERE c.status = 'error'")
    print(f"  3. Failed orders: SELECT * FROM c WHERE c.failed = true")
    print(f"  4. High retries: SELECT * FROM c WHERE c.retryCount > 5")
    print(f"  5. Recent errors: SELECT * FROM c WHERE c.status = 'error' ORDER BY c.timestamp DESC")


def main():
    parser = argparse.ArgumentParser(description="Populate Cosmos DB with test data")
    parser.add_argument("--account-name", required=True, help="Cosmos DB account name")
    parser.add_argument("--resource-group", required=True, help="Azure resource group")
    parser.add_argument("--database", required=True, help="Database name")
    parser.add_argument("--container", required=True, help="Container name")
    
    args = parser.parse_args()
    
    populate_data(args.account_name, args.resource_group, args.database, args.container)


if __name__ == "__main__":
    main()

