"""
Azure Cosmos DB Python library for Robot Framework.

This library provides keywords for executing SQL queries against Azure Cosmos DB using the Python SDK.
"""

from azure.cosmos import CosmosClient, exceptions
from azure.identity import DefaultAzureCredential
from typing import Optional
import json
import os


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
            
            # If query contains COUNT, extract the count value
            if "COUNT" in query.upper():
                if items and len(items) > 0:
                    first_item = items[0]
                    # Try different count field names
                    if "$1" in first_item:
                        return int(first_item["$1"])
                    elif "count" in first_item:
                        return int(first_item["count"])
                    elif "Count" in first_item:
                        return int(first_item["Count"])
                    else:
                        # Return first value from the first key
                        return int(list(first_item.values())[0])
                return 0
            else:
                # Just return the number of items returned
                return len(items)
        except Exception as e:
            raise Exception(f"Failed to count query results: {str(e)}")
