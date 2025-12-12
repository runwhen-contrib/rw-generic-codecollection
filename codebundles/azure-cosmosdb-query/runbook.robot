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
    
    # Smart authentication with multiple fallback options
    ${auth_method}=    Set Variable    none
    ${auth_error}=    Set Variable    ${EMPTY}
    ${sp_key_error}=    Set Variable    ${EMPTY}
    TRY
        ${azure_credentials}=    RW.Core.Import Secret
        ...    azure_credentials
        ...    type=string
        ...    description=The secret containing AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_CLIENT_SECRET for service principal authentication
        ...    pattern=\w*
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
                    # Try 3: Fall back to cosmosdb_key secret
                    ${cosmosdb_key}=    RW.Core.Import Secret
                    ...    cosmosdb_key
                    ...    type=string
                    ...    description=The Cosmos DB account primary or secondary key
                    ...    pattern=\w*
                    RW.Azure.Cosmosdb.Connect To Cosmosdb    ${COSMOSDB_ENDPOINT}    ${cosmosdb_key.key}
                    ${auth_method}=    Set Variable    cosmosdb_key
                END
            ELSE
                Log    Missing AZURE_SUBSCRIPTION_ID, AZURE_RESOURCE_GROUP, or COSMOSDB_ACCOUNT_NAME - cannot retrieve key    WARN
                Log    Falling back to cosmosdb_key secret...    WARN
                # Try 3: Fall back to cosmosdb_key secret
                ${cosmosdb_key}=    RW.Core.Import Secret
                ...    cosmosdb_key
                ...    type=string
                ...    description=The Cosmos DB account primary or secondary key
                ...    pattern=\w*
                RW.Azure.Cosmosdb.Connect To Cosmosdb    ${COSMOSDB_ENDPOINT}    ${cosmosdb_key.key}
                ${auth_method}=    Set Variable    cosmosdb_key
            END
        END
    EXCEPT    AS    ${key_error}
        # azure_credentials not available, try cosmosdb_key directly
        ${cosmosdb_key}=    RW.Core.Import Secret
        ...    cosmosdb_key
        ...    type=string
        ...    description=The Cosmos DB account primary or secondary key
        ...    pattern=\w*
        TRY
            RW.Azure.Cosmosdb.Connect To Cosmosdb    ${COSMOSDB_ENDPOINT}    ${cosmosdb_key.key}
            ${auth_method}=    Set Variable    cosmosdb_key
        EXCEPT    AS    ${final_error}
            # All authentication methods failed - raise an issue
            RW.Core.Add Issue
            ...    title=Failed to Authenticate to Cosmos DB
            ...    severity=1
            ...    expected=Should successfully authenticate using azure_credentials (service principal) or cosmosdb_key
            ...    actual=All authentication methods failed
            ...    reproduce_hint=Check that azure_credentials or cosmosdb_key secret is configured correctly
            ...    next_steps=1. Verify azure_credentials contains valid AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_CLIENT_SECRET\n2. For data plane RBAC: Grant Cosmos DB Built-in Data Reader role\n3. For control plane key retrieval: Set AZURE_SUBSCRIPTION_ID, AZURE_RESOURCE_GROUP, COSMOSDB_ACCOUNT_NAME and grant "Cosmos DB Account Reader" or "Contributor" role\n4. Alternatively, provide a valid cosmosdb_key secret\n5. Check endpoint URL is correct: ${COSMOSDB_ENDPOINT}
            ...    details=Failed to authenticate to Cosmos DB at ${COSMOSDB_ENDPOINT}\n\nAzure AD RBAC Error: ${auth_error}\nAzure AD Key Retrieval Error: ${sp_key_error}\nDirect Key Error: ${final_error}\n\nSee README for authentication options.
            Fail    Authentication to Cosmos DB failed with all methods
        END
    END
    Log    Successfully connected using authentication method: ${auth_method}    INFO

