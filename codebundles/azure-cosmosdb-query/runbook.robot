*** Settings ***
Documentation       This taskset runs a user-provided Cosmos DB SQL query and adds the output to the report. Uses the Azure Cosmos DB Python SDK.

Metadata            Author    stewartshea
Metadata            Display Name    Azure Cosmos DB Query
Metadata            Supports    Azure    CosmosDB

Library             BuiltIn
Library             RW.Core
Library             RW.platform
Library             RW.Azure.Cosmosdb

Suite Setup         Suite Initialization


*** Tasks ***
${TASK_TITLE}
    [Documentation]    Executes a user-provided Cosmos DB SQL query and adds the results to the report.
    [Tags]    azure    cosmosdb    query    generic
    TRY
        ${results}=    RW.Azure.Cosmosdb.Query Container
        ...    ${DATABASE_NAME}
        ...    ${CONTAINER_NAME}
        ...    ${COSMOSDB_QUERY}
        ...    ${QUERY_PARAMETERS}
        RW.Core.Add Pre To Report    Query: ${COSMOSDB_QUERY}
        RW.Core.Add Pre To Report    Results:\n${results}
    EXCEPT    AS    ${error_message}
        RW.Core.Add Issue
        ...    title=Cosmos DB Query Failed
        ...    severity=3
        ...    expected=Query should execute successfully
        ...    actual=Query execution failed with error
        ...    reproduce_hint=Execute query: ${COSMOSDB_QUERY} against database ${DATABASE_NAME}, container ${CONTAINER_NAME}
        ...    next_steps=Check Cosmos DB connection, verify endpoint and key are correct, ensure database and container exist, and verify query syntax
        ...    details=Failed to execute Cosmos DB query.\n\nError: ${error_message}\n\nEndpoint: ${COSMOSDB_ENDPOINT}\nDatabase: ${DATABASE_NAME}\nContainer: ${CONTAINER_NAME}\nQuery: ${COSMOSDB_QUERY}
        RW.Core.Add Pre To Report    Error executing query: ${error_message}
    END


*** Keywords ***
Suite Initialization
    ${COSMOSDB_ENDPOINT}=    RW.Core.Import User Variable
    ...    COSMOSDB_ENDPOINT
    ...    type=string
    ...    description=The Cosmos DB account endpoint URL (e.g., https://myaccount.documents.azure.com:443/)
    ...    pattern=\w*
    ...    example=https://myaccount.documents.azure.com:443/
    ${AZURE_SUBSCRIPTION_ID}=    RW.Core.Import User Variable    AZURE_SUBSCRIPTION_ID
    ...    type=string
    ...    description=Azure subscription ID (optional, only needed if service principal will retrieve keys)
    ...    pattern=\w*
    ...    example=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    ...    default=
    ${AZURE_RESOURCE_GROUP}=    RW.Core.Import User Variable    AZURE_RESOURCE_GROUP
    ...    type=string
    ...    description=Azure resource group name (optional, only needed if service principal will retrieve keys)
    ...    pattern=\w*
    ...    example=my-resource-group
    ...    default=
    ${COSMOSDB_ACCOUNT_NAME}=    RW.Core.Import User Variable    COSMOSDB_ACCOUNT_NAME
    ...    type=string
    ...    description=Cosmos DB account name (optional, only needed if service principal will retrieve keys)
    ...    pattern=\w*
    ...    example=my-cosmosdb-account
    ...    default=
    ${DATABASE_NAME}=    RW.Core.Import User Variable    DATABASE_NAME
    ...    type=string
    ...    description=The name of the Cosmos DB database
    ...    pattern=\w*
    ...    example=mydatabase
    ${CONTAINER_NAME}=    RW.Core.Import User Variable    CONTAINER_NAME
    ...    type=string
    ...    description=The name of the Cosmos DB container
    ...    pattern=\w*
    ...    example=mycontainer
    ${COSMOSDB_QUERY}=    RW.Core.Import User Variable    COSMOSDB_QUERY
    ...    type=string
    ...    description=The SQL query to execute against the Cosmos DB container
    ...    pattern=\w*
    ...    example=SELECT * FROM c WHERE c.status = 'error' ORDER BY c._ts DESC
    ${QUERY_PARAMETERS}=    RW.Core.Import User Variable    QUERY_PARAMETERS
    ...    type=string
    ...    description=Optional JSON string of query parameters for parameterized queries
    ...    pattern=\w*
    ...    example={"@status": "error", "@limit": 10}
    ...    default=
    ${TASK_TITLE}=    RW.Core.Import User Variable    TASK_TITLE
    ...    type=string
    ...    description=The name of the task to run. This is useful for helping find this generic task with RunWhen Digital Assistants.
    ...    pattern=\w*
    ...    example="Query Cosmos DB for error documents"
    
    # Import optional secrets for authentication
    ${azure_credentials}=    RW.Core.Import Secret
    ...    azure_credentials
    ...    type=string
    ...    description=Service principal credentials with AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_CLIENT_SECRET (optional)
    ...    pattern=.*
    ...    optional=True
    
    ${cosmosdb_key}=    RW.Core.Import Secret
    ...    cosmosdb_key
    ...    type=string
    ...    description=The Cosmos DB account primary or secondary key (optional)
    ...    pattern=.*
    ...    optional=True
    
    # Smart authentication with multiple fallback options
    ${auth_method}=    Set Variable    none
    ${auth_error}=    Set Variable    ${EMPTY}
    ${sp_key_error}=    Set Variable    ${EMPTY}
    ${has_azure_creds}=    Evaluate    bool($azure_credentials)
    ${has_cosmosdb_key}=    Evaluate    bool($cosmosdb_key)
    
    IF    ${has_azure_creds}
        # Try 1: Azure AD data plane RBAC
        TRY
            RW.Azure.Cosmosdb.Connect To Cosmosdb With Azure Credentials    ${COSMOSDB_ENDPOINT}
            ${auth_method}=    Set Variable    azure_credentials_rbac
        EXCEPT    AS    ${azure_error}
            Log    Azure AD data plane authentication failed: ${azure_error}    WARN
            ${auth_error}=    Set Variable    ${azure_error}
            # Try 2: Use service principal to retrieve key from control plane
            ${can_retrieve_key}=    Evaluate    "${AZURE_SUBSCRIPTION_ID}" and "${AZURE_RESOURCE_GROUP}" and "${COSMOSDB_ACCOUNT_NAME}"
            IF    ${can_retrieve_key}
                Log    Attempting to retrieve Cosmos DB key using service principal control plane access...    WARN
                TRY
                    RW.Azure.Cosmosdb.Connect To Cosmosdb With Azure Credentials And Retrieve Key
                    ...    ${COSMOSDB_ENDPOINT}
                    ...    ${AZURE_SUBSCRIPTION_ID}
                    ...    ${AZURE_RESOURCE_GROUP}
                    ...    ${COSMOSDB_ACCOUNT_NAME}
                    ${auth_method}=    Set Variable    azure_credentials_retrieved_key
                EXCEPT    AS    ${retrieve_error}
                    Log    Failed to retrieve key via service principal: ${retrieve_error}    WARN
                    ${sp_key_error}=    Set Variable    ${retrieve_error}
                    # Try 3: Fall back to cosmosdb_key secret if available
                    IF    ${has_cosmosdb_key}
                        RW.Azure.Cosmosdb.Connect To Cosmosdb    ${COSMOSDB_ENDPOINT}    ${cosmosdb_key}
                        ${auth_method}=    Set Variable    cosmosdb_key
                    ELSE
                        Fail    Azure AD authentication failed and no cosmosdb_key provided
                    END
                END
            ELSE
                Log    Missing AZURE_SUBSCRIPTION_ID, AZURE_RESOURCE_GROUP, or COSMOSDB_ACCOUNT_NAME - cannot retrieve key    WARN
                Log    Falling back to cosmosdb_key secret...    WARN
                # Try 3: Fall back to cosmosdb_key secret if available
                IF    ${has_cosmosdb_key}
                    RW.Azure.Cosmosdb.Connect To Cosmosdb    ${COSMOSDB_ENDPOINT}    ${cosmosdb_key}
                    ${auth_method}=    Set Variable    cosmosdb_key
                ELSE
                    Fail    Azure AD authentication failed and no cosmosdb_key provided
                END
            END
        END
    ELSE IF    ${has_cosmosdb_key}
        # Only cosmosdb_key provided
        RW.Azure.Cosmosdb.Connect To Cosmosdb    ${COSMOSDB_ENDPOINT}    ${cosmosdb_key}
        ${auth_method}=    Set Variable    cosmosdb_key
    ELSE
        # No credentials provided at all
        RW.Core.Add Issue
        ...    title=No Cosmos DB Authentication Credentials Provided
        ...    severity=1
        ...    expected=Either azure_credentials or cosmosdb_key secret should be configured
        ...    actual=No authentication credentials found
        ...    reproduce_hint=Configure either azure_credentials or cosmosdb_key secret
        ...    next_steps=1. For service principal: Configure azure_credentials secret with AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_CLIENT_SECRET\n2. For key-based auth: Configure cosmosdb_key secret\n3. See README for authentication options
        ...    details=No authentication credentials provided for Cosmos DB at ${COSMOSDB_ENDPOINT}\n\nSee README for authentication setup instructions.
        Fail    No authentication credentials provided
    END
    
    Log    Successfully connected using authentication method: ${auth_method}    INFO

