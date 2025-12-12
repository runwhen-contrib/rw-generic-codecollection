*** Settings ***
Documentation       This SLI runs a user-provided Cosmos DB SQL query and pushes a health metric. Returns 0 (unhealthy) if results are found, 1 (healthy) if no results.

Metadata            Author    stewartshea
Metadata            Display Name    Health Metric from Azure Cosmos DB Query
Metadata            Supports    Azure    CosmosDB

Library             BuiltIn
Library             RW.Core
Library             RW.platform
Library             RW.Azure.Cosmosdb

Suite Setup         Suite Initialization


*** Tasks ***
${TASK_TITLE}
    [Documentation]    Executes a user-provided Cosmos DB SQL query and pushes 0 if results are found (unhealthy), 1 if no results (healthy).
    [Tags]    azure    cosmosdb    query    generic    sli
    ${count}=    RW.Azure.Cosmosdb.Count Query Results
    ...    ${DATABASE_NAME}
    ...    ${CONTAINER_NAME}
    ...    ${COSMOSDB_QUERY}
    ...    ${QUERY_PARAMETERS}
    
    IF    ${count} > 0
        RW.Core.Push Metric    0
    ELSE
        RW.Core.Push Metric    1
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
    ...    description=The SQL query to execute. Should filter for errors/problems - results indicate unhealthy state.
    ...    pattern=\w*
    ...    example=SELECT * FROM c WHERE c.status = 'error'
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
    ...    example="Monitor Cosmos DB for error documents"
    
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
            # Both authentication methods failed - this is critical for SLI
            Fail    Authentication to Cosmos DB failed. Azure AD: ${auth_error} | Key-based: ${final_error}
        END
    END
    Log    Successfully connected using authentication method: ${auth_method}    INFO

