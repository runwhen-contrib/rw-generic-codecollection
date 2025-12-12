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
        ${count}=    RW.Azure.Cosmosdb.Count Query Results
        ...    ${DATABASE_NAME}
        ...    ${CONTAINER_NAME}
        ...    ${COSMOSDB_QUERY}
        ...    ${QUERY_PARAMETERS}
        
        IF    ${count} > 0
            RW.Core.Add Issue
            ...    title=${ISSUE_TITLE}
            ...    severity=${ISSUE_SEVERITY}
            ...    expected=The query should return no results, indicating no errors were found.
            ...    actual=Query returned ${count} results, indicating errors were found.
            ...    reproduce_hint=Query Cosmos DB with: ${COSMOSDB_QUERY}
            ...    next_steps=${ISSUE_NEXT_STEPS}
            ...    details=${ISSUE_DETAILS}\n\nQuery Results:\n${results}
            RW.Core.Add Pre To Report    Query: ${COSMOSDB_QUERY}
            RW.Core.Add Pre To Report    Found ${count} results:\n${results}
        ELSE
            RW.Core.Add Pre To Report    Query: ${COSMOSDB_QUERY}
            RW.Core.Add Pre To Report    No results returned - no errors found.
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
    
    # Try Azure AD authentication first (service principal - recommended), fall back to key-based auth
    ${auth_method}=    Set Variable    none
    ${auth_error}=    Set Variable    ${EMPTY}
    TRY
        ${azure_credentials}=    RW.Core.Import Secret
        ...    azure_credentials
        ...    type=string
        ...    description=The secret containing AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_CLIENT_SECRET for service principal authentication
        ...    pattern=\w*
        TRY
            RW.Azure.Cosmosdb.Connect To Cosmosdb With Azure Credentials    ${COSMOSDB_ENDPOINT}
            ${auth_method}=    Set Variable    azure_credentials
        EXCEPT    AS    ${azure_error}
            Log    Azure AD authentication failed: ${azure_error}    WARN
            Log    Falling back to key-based authentication...    WARN
            ${auth_error}=    Set Variable    ${azure_error}
            ${cosmosdb_key}=    RW.Core.Import Secret
            ...    cosmosdb_key
            ...    type=string
            ...    description=The Cosmos DB account primary or secondary key
            ...    pattern=\w*
            RW.Azure.Cosmosdb.Connect To Cosmosdb    ${COSMOSDB_ENDPOINT}    ${cosmosdb_key.key}
            ${auth_method}=    Set Variable    cosmosdb_key
        END
    EXCEPT    AS    ${key_error}
        ${cosmosdb_key}=    RW.Core.Import Secret
        ...    cosmosdb_key
        ...    type=string
        ...    description=The Cosmos DB account primary or secondary key
        ...    pattern=\w*
        TRY
            RW.Azure.Cosmosdb.Connect To Cosmosdb    ${COSMOSDB_ENDPOINT}    ${cosmosdb_key.key}
            ${auth_method}=    Set Variable    cosmosdb_key
        EXCEPT    AS    ${final_error}
            # Both authentication methods failed - raise an issue
            RW.Core.Add Issue
            ...    title=Failed to Authenticate to Cosmos DB
            ...    severity=1
            ...    expected=Should successfully authenticate using either azure_credentials (service principal) or cosmosdb_key
            ...    actual=Both authentication methods failed
            ...    reproduce_hint=Check that azure_credentials or cosmosdb_key secret is configured correctly. For service principal, ensure RBAC permissions are granted.
            ...    next_steps=1. Verify azure_credentials contains valid AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_CLIENT_SECRET\n2. Ensure service principal has Cosmos DB Built-in Data Reader role (00000000-0000-0000-0000-000000000001)\n3. Alternatively, provide a valid cosmosdb_key secret\n4. Check endpoint URL is correct: ${COSMOSDB_ENDPOINT}
            ...    details=Failed to authenticate to Cosmos DB at ${COSMOSDB_ENDPOINT}\n\nAzure AD Error: ${auth_error}\nKey-based Error: ${final_error}\n\nFor service principal auth, grant RBAC:\naz cosmosdb sql role assignment create --account-name <account> --resource-group <rg> --scope "/" --principal-id <sp-object-id> --role-definition-id 00000000-0000-0000-0000-000000000001
            Fail    Authentication to Cosmos DB failed with both methods
        END
    END
    Log    Successfully connected using authentication method: ${auth_method}    INFO

