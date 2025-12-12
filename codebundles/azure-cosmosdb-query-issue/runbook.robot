*** Settings ***
Documentation       Runs a user-provided Cosmos DB SQL query, and if the query returns results, an issue is generated with a configurable title and content.
...                 User queries should filter for error/problem conditions - results indicate issues were found.

Metadata            Author    stewartshea
Metadata            Display Name    Azure Cosmos DB Query with Issue Detection
Metadata            Supports    Azure    CosmosDB

Library             BuiltIn
Library             RW.Core
Library             RW.platform
Library             RW.Azure.Cosmosdb

Suite Setup         Suite Initialization


*** Tasks ***
${TASK_TITLE}
    [Documentation]    Executes a user-provided Cosmos DB SQL query and if results are returned, raises an issue.
    [Tags]    azure    cosmosdb    query    generic    issue
    TRY
        ${results}=    RW.Azure.Cosmosdb.Query Container
        ...    ${DATABASE_NAME}
        ...    ${CONTAINER_NAME}
        ...    ${COSMOSDB_QUERY}
        ...    ${QUERY_PARAMETERS}
        ${results_list}=    Evaluate    json.loads($results)    json
        ${count}=    Evaluate    len($results_list)
        
        # Determine if issue should be raised based on condition
        ${should_raise_issue}=    Set Variable    ${False}
        ${expected_msg}=    Set Variable    ${EMPTY}
        ${actual_msg}=    Set Variable    ${EMPTY}
        
        IF    "${ISSUE_ON}" == "results_found"
            ${should_raise_issue}=    Evaluate    ${count} > 0
            ${expected_msg}=    Set Variable    The query should return no results
            ${actual_msg}=    Set Variable    Query returned ${count} results
        ELSE IF    "${ISSUE_ON}" == "no_results"
            ${should_raise_issue}=    Evaluate    ${count} == 0
            ${expected_msg}=    Set Variable    The query should return results
            ${actual_msg}=    Set Variable    Query returned no results
        ELSE IF    "${ISSUE_ON}" == "count_above"
            ${threshold}=    Convert To Integer    ${ISSUE_THRESHOLD}
            ${should_raise_issue}=    Evaluate    ${count} > ${threshold}
            ${expected_msg}=    Set Variable    The query should return ${threshold} or fewer results
            ${actual_msg}=    Set Variable    Query returned ${count} results (above threshold of ${threshold})
        ELSE IF    "${ISSUE_ON}" == "count_below"
            ${threshold}=    Convert To Integer    ${ISSUE_THRESHOLD}
            ${should_raise_issue}=    Evaluate    ${count} < ${threshold}
            ${expected_msg}=    Set Variable    The query should return ${threshold} or more results
            ${actual_msg}=    Set Variable    Query returned ${count} results (below threshold of ${threshold})
        ELSE
            Log    Invalid ISSUE_ON value: ${ISSUE_ON}. Using default "results_found".    WARN
            ${should_raise_issue}=    Evaluate    ${count} > 0
            ${expected_msg}=    Set Variable    The query should return no results
            ${actual_msg}=    Set Variable    Query returned ${count} results
        END
        
        IF    ${should_raise_issue}
            RW.Core.Add Issue
            ...    title=${ISSUE_TITLE}
            ...    severity=${ISSUE_SEVERITY}
            ...    expected=${expected_msg}
            ...    actual=${actual_msg}
            ...    reproduce_hint=Query Cosmos DB with: ${COSMOSDB_QUERY}
            ...    next_steps=${ISSUE_NEXT_STEPS}
            ...    details=${ISSUE_DETAILS}\n\nQuery Results (${count} documents):\n${results}
            RW.Core.Add Pre To Report    Query: ${COSMOSDB_QUERY}
            RW.Core.Add Pre To Report    Issue raised: ${actual_msg}\n\nResults:\n${results}
        ELSE
            RW.Core.Add Pre To Report    Query: ${COSMOSDB_QUERY}
            RW.Core.Add Pre To Report    No issue detected. Query returned ${count} results (condition: ${ISSUE_ON})
        END
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
    ...    description=The SQL query to execute. Should filter for errors/problems only - results indicate issues.
    ...    pattern=\w*
    ...    example=SELECT * FROM c WHERE c.status = 'error' ORDER BY c._ts DESC
    ${QUERY_PARAMETERS}=    RW.Core.Import User Variable    QUERY_PARAMETERS
    ...    type=string
    ...    description=Optional JSON string of query parameters for parameterized queries
    ...    pattern=\w*
    ...    example={"@status": "error"}
    ...    default=
    ${TASK_TITLE}=    RW.Core.Import User Variable    TASK_TITLE
    ...    type=string
    ...    description=The name of the task to run. This is useful for helping find this generic task with RunWhen Digital Assistants.
    ...    pattern=\w*
    ...    example="Check Cosmos DB for error documents"
    ${ISSUE_TITLE}=    RW.Core.Import User Variable    ISSUE_TITLE
    ...    type=string
    ...    description=The title of the issue to raise if the query returns results.
    ...    pattern=\w*
    ...    example="Found error documents in Cosmos DB"
    ...    default="Found results in Cosmos DB query"
    ${ISSUE_NEXT_STEPS}=    RW.Core.Import User Variable    ISSUE_NEXT_STEPS
    ...    type=string
    ...    description=The next steps to take if the query returns results.
    ...    pattern=\w*
    ...    example="Review the error documents and investigate the root cause."
    ...    default="Review the query results and take appropriate action."
    ${ISSUE_DETAILS}=    RW.Core.Import User Variable    ISSUE_DETAILS
    ...    type=string
    ...    description=The details of the issue to raise if the query returns results.
    ...    pattern=\w*
    ...    example="The Cosmos DB query found documents with error status."
    ...    default="The Cosmos DB query returned results, indicating issues were found."
    ${ISSUE_SEVERITY}=    RW.Core.Import User Variable    ISSUE_SEVERITY
    ...    type=string
    ...    description=An integer severity rating for the issue if raised, where 1 is critical, and 4 is informational.
    ...    pattern=\w*
    ...    example=3
    ...    default=3
    ${ISSUE_ON}=    RW.Core.Import User Variable    ISSUE_ON
    ...    type=string
    ...    description=When to raise an issue: "results_found" (default), "no_results", "count_above", "count_below"
    ...    pattern=\w*
    ...    example=results_found
    ...    default=results_found
    ${ISSUE_THRESHOLD}=    RW.Core.Import User Variable    ISSUE_THRESHOLD
    ...    type=string
    ...    description=Numeric threshold for "count_above" or "count_below" conditions (ignored for other conditions)
    ...    pattern=\w*
    ...    example=100
    ...    default=0
    
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
                        Log    Falling back to cosmosdb_key secret...    WARN
                        RW.Azure.Cosmosdb.Connect To Cosmosdb    ${COSMOSDB_ENDPOINT}    ${cosmosdb_key}
                        ${auth_method}=    Set Variable    cosmosdb_key
                    ELSE
                        # All authentication methods failed - raise issue
                        RW.Core.Add Issue
                        ...    title=Failed to Authenticate to Cosmos DB
                        ...    severity=1
                        ...    expected=Should successfully authenticate using azure_credentials
                        ...    actual=All authentication methods failed
                        ...    reproduce_hint=Check that azure_credentials secret is configured correctly. For service principal, ensure RBAC permissions are granted or control plane access to retrieve keys.
                        ...    next_steps=1. Verify azure_credentials contains valid AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_CLIENT_SECRET\n2. Ensure service principal has Cosmos DB Built-in Data Reader role OR Microsoft.DocumentDB/databaseAccounts/listKeys/action permission\n3. Alternatively, provide cosmosdb_key secret as fallback\n4. Check endpoint URL is correct: ${COSMOSDB_ENDPOINT}
                        ...    details=Failed to authenticate to Cosmos DB at ${COSMOSDB_ENDPOINT}\n\nAzure AD Data Plane Error: ${auth_error}\nService Principal Key Retrieval Error: ${sp_key_error}\n\nSee README for authentication options.
                        Fail    All authentication methods failed and no cosmosdb_key provided
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
                    # Azure AD failed and no fallback - raise issue
                    RW.Core.Add Issue
                    ...    title=Failed to Authenticate to Cosmos DB
                    ...    severity=1
                    ...    expected=Should successfully authenticate using azure_credentials
                    ...    actual=Azure AD authentication failed
                    ...    reproduce_hint=Check that azure_credentials secret is configured correctly. For service principal, ensure RBAC permissions are granted or provide AZURE_SUBSCRIPTION_ID, AZURE_RESOURCE_GROUP, and COSMOSDB_ACCOUNT_NAME for key retrieval.
                    ...    next_steps=1. Verify azure_credentials contains valid AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_CLIENT_SECRET\n2. Ensure service principal has Cosmos DB Built-in Data Reader role\n3. Alternatively, provide AZURE_SUBSCRIPTION_ID, AZURE_RESOURCE_GROUP, and COSMOSDB_ACCOUNT_NAME for key retrieval\n4. Or provide cosmosdb_key secret as fallback\n5. Check endpoint URL is correct: ${COSMOSDB_ENDPOINT}
                    ...    details=Failed to authenticate to Cosmos DB at ${COSMOSDB_ENDPOINT}\n\nAzure AD Error: ${auth_error}\n\nSee README for authentication options.
                    Fail    Azure AD authentication failed and no cosmosdb_key provided
                END
            END
        END
    ELSE IF    ${has_cosmosdb_key}
        # Only cosmosdb_key provided
        RW.Azure.Cosmosdb.Connect To Cosmosdb    ${COSMOSDB_ENDPOINT}    ${cosmosdb_key}
        ${auth_method}=    Set Variable    cosmosdb_key
    ELSE
        # No credentials provided at all - raise issue
        RW.Core.Add Issue
        ...    title=No Cosmos DB Authentication Credentials Provided
        ...    severity=1
        ...    expected=Either azure_credentials or cosmosdb_key secret should be configured
        ...    actual=No authentication credentials found
        ...    reproduce_hint=Configure either azure_credentials or cosmosdb_key secret
        ...    next_steps=1. For service principal: Configure azure_credentials secret\n2. For key-based auth: Configure cosmosdb_key secret\n3. See README for authentication options
        ...    details=No authentication credentials provided for Cosmos DB at ${COSMOSDB_ENDPOINT}
        Fail    No authentication credentials provided
    END
    
    Log    Successfully connected using authentication method: ${auth_method}    INFO

