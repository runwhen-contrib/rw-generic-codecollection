"""
Azure Cosmos DB Python library for Robot Framework.

This library provides keywords for executing SQL queries against Azure Cosmos DB using the Python SDK.
"""

from azure.cosmos import CosmosClient, exceptions
from azure.identity import DefaultAzureCredential
from azure.mgmt.cosmosdb import CosmosDBManagementClient
from typing import Optional
import json
import os
import re


class Cosmosdb:
    """
    Library for querying Azure Cosmos DB.
    
    Provides keywords for executing user-provided SQL queries against Cosmos DB containers.
    Supports both key-based authentication and Azure AD authentication (service principals).
    """

    ROBOT_LIBRARY_SCOPE = "GLOBAL"
    ROBOT_LIBRARY_VERSION = "1.0.0"

    def __init__(self):
        self.client: Optional[CosmosClient] = None
        self.endpoint: Optional[str] = None

    def connect_to_cosmosdb(self, endpoint: str, key: Optional[str] = None) -> str:
        """
        Connect to an Azure Cosmos DB account using key-based authentication.
        
        Args:
            endpoint: The Cosmos DB account endpoint URL
            key: The Cosmos DB account key (optional if using Azure AD)
            
        Returns:
            Success message
            
        Example:
            | Connect To Cosmosdb | https://myaccount.documents.azure.com:443/ | mykey |
        """
        try:
            self.endpoint = endpoint
            if key and key.strip():
                # Key-based authentication
                self.client = CosmosClient(self.endpoint, key)
                return f"Successfully connected to Cosmos DB account at {endpoint} using key authentication"
            else:
                # Azure AD authentication (service principal, managed identity, etc.)
                credential = DefaultAzureCredential()
                self.client = CosmosClient(self.endpoint, credential)
                return f"Successfully connected to Cosmos DB account at {endpoint} using Azure AD authentication"
        except Exception as e:
            raise Exception(f"Failed to connect to Cosmos DB: {str(e)}")

    def connect_to_cosmosdb_with_azure_credentials(self, endpoint: str) -> str:
        """
        Connect to an Azure Cosmos DB account using Azure AD authentication.
        Uses DefaultAzureCredential which supports service principals, managed identities, and Azure CLI credentials.
        
        Requires azure_credentials secret with AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_CLIENT_SECRET
        to be set as environment variables.
        
        Args:
            endpoint: The Cosmos DB account endpoint URL
            
        Returns:
            Success message
            
        Example:
            | Connect To Cosmosdb With Azure Credentials | https://myaccount.documents.azure.com:443/ |
        """
        try:
            self.endpoint = endpoint
            credential = DefaultAzureCredential()
            self.client = CosmosClient(self.endpoint, credential)
            return f"Successfully connected to Cosmos DB account at {endpoint} using Azure AD authentication"
        except Exception as e:
            raise Exception(f"Failed to connect to Cosmos DB with Azure credentials: {str(e)}")
    
    def connect_to_cosmosdb_with_azure_credentials_and_retrieve_key(
        self, endpoint: str, subscription_id: str, resource_group: str, account_name: str
    ) -> str:
        """
        Connect to Cosmos DB by using service principal to retrieve the account key from Azure,
        then connecting with that key. This is useful when the service principal doesn't have
        data plane RBAC permissions but has control plane access to list keys.
        
        Requires:
        - azure_credentials secret with AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_CLIENT_SECRET
        - Service principal with Microsoft.DocumentDB/databaseAccounts/listKeys/action permission
          (e.g., "Cosmos DB Account Reader" or "Contributor" role)
        
        Args:
            endpoint: The Cosmos DB account endpoint URL
            subscription_id: Azure subscription ID
            resource_group: Resource group name
            account_name: Cosmos DB account name
            
        Returns:
            Success message
            
        Example:
            | Connect To Cosmosdb With Azure Credentials And Retrieve Key | 
            | ... | https://myaccount.documents.azure.com:443/ |
            | ... | sub-id | my-rg | my-cosmosdb-account |
        """
        try:
            self.endpoint = endpoint
            credential = DefaultAzureCredential()
            
            # Use Azure Management API to retrieve the key
            cosmos_mgmt_client = CosmosDBManagementClient(credential, subscription_id)
            keys = cosmos_mgmt_client.database_accounts.list_keys(resource_group, account_name)
            
            # Connect using the retrieved key
            self.client = CosmosClient(self.endpoint, keys.primary_master_key)
            return f"Successfully connected to Cosmos DB account at {endpoint} using key retrieved via Azure AD (control plane)"
        except Exception as e:
            raise Exception(f"Failed to retrieve Cosmos DB key using Azure credentials: {str(e)}")

    def query_container(
        self, database_name: str, container_name: str, query: str, parameters: Optional[str] = None
    ) -> str:
        """
        Execute a SQL query on a Cosmos DB container.
        
        Args:
            database_name: Name of the database
            container_name: Name of the container
            query: SQL query string
            parameters: Optional JSON string of query parameters (e.g., '{"@status": "error"}')
            
        Returns:
            JSON string containing query results
            
        Example:
            | ${results}= | Query Container | mydb | mycontainer | SELECT * FROM c WHERE c.status = 'error' |
            | ${results}= | Query Container | mydb | mycontainer | SELECT * FROM c WHERE c.id = @id | {"@id": "123"} |
        """
        if not self.client:
            raise Exception("Not connected to Cosmos DB. Call 'Connect To Cosmosdb' first.")
        
        try:
            database = self.client.get_database_client(database_name)
            container = database.get_container_client(container_name)
            
            query_params = []
            if parameters:
                params_dict = json.loads(parameters)
                for key, value in params_dict.items():
                    query_params.append({"name": key, "value": value})
            
            items = list(container.query_items(
                query=query, 
                parameters=query_params if query_params else None,
                enable_cross_partition_query=True
            ))
            return json.dumps(items, indent=2, default=str)
        except exceptions.CosmosResourceNotFoundError as e:
            raise Exception(f"Resource not found: {str(e)}")
        except exceptions.CosmosHttpResponseError as e:
            raise Exception(f"Cosmos DB query error: {str(e)}")
        except Exception as e:
            raise Exception(f"Failed to query container: {str(e)}")

    def count_query_results(
        self, database_name: str, container_name: str, query: str, parameters: Optional[str] = None
    ) -> int:
        """
        Execute a query and return the count of results.
        
        Args:
            database_name: Name of the database
            container_name: Name of the container
            query: SQL query string (if it doesn't contain COUNT, will return number of rows)
            parameters: Optional JSON string of query parameters
            
        Returns:
            Integer count of results
            
        Example:
            | ${count}= | Count Query Results | mydb | mycontainer | SELECT * FROM c WHERE c.status = 'error' |
            | ${count}= | Count Query Results | mydb | mycontainer | SELECT COUNT(1) FROM c WHERE c.status = 'error' |
        """
        if not self.client:
            raise Exception("Not connected to Cosmos DB. Call 'Connect To Cosmosdb' first.")
        
        try:
            database = self.client.get_database_client(database_name)
            container = database.get_container_client(container_name)
            
            query_params = []
            if parameters:
                params_dict = json.loads(parameters)
                for key, value in params_dict.items():
                    query_params.append({"name": key, "value": value})
            
            items = list(container.query_items(
                query=query,
                parameters=query_params if query_params else None,
                enable_cross_partition_query=True
            ))
            
            # Check if query is a COUNT aggregate query using regex to avoid substring matches
            # Matches COUNT( or COUNT ( with optional whitespace, case-insensitive
            count_pattern = re.compile(r'\bCOUNT\s*\(', re.IGNORECASE)
            is_count_query = bool(count_pattern.search(query))
            
            if is_count_query:
                if items and len(items) > 0:
                    first_item = items[0]
                    # Handle SELECT VALUE COUNT(1) which returns just a number
                    if isinstance(first_item, (int, float)):
                        return int(first_item)
                    # Handle SELECT COUNT(1) which returns an object
                    elif isinstance(first_item, dict):
                        # Try different count field names
                        if "$1" in first_item:
                            return int(first_item["$1"])
                        elif "count" in first_item:
                            return int(first_item["count"])
                        elif "Count" in first_item:
                            return int(first_item["Count"])
                        else:
                            # Try to extract numeric value from first field if dict is not empty
                            values = list(first_item.values())
                            if values and isinstance(values[0], (int, float)):
                                return int(values[0])
                            else:
                                # If first value is not numeric or dict is empty, fall back to counting items
                                return len(items)
                    else:
                        # Fallback for unexpected types - try to convert to int
                        try:
                            return int(first_item)
                        except (ValueError, TypeError):
                            # If conversion fails, fall back to counting items
                            return len(items)
                return 0
            else:
                # Just return the number of items returned
                return len(items)
        except Exception as e:
            raise Exception(f"Failed to count query results: {str(e)}")
