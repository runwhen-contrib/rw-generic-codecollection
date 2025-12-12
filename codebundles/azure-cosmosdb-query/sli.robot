*** Settings ***
Documentation       This SLI runs a user-provided Cosmos DB SQL query and pushes a metric based on the result count. Uses the Azure Cosmos DB Python SDK.

Metadata            Author    stewartshea
Metadata            Display Name    Metric from Azure Cosmos DB Query
Metadata            Supports    Azure    CosmosDB

Library             BuiltIn
Library             RW.Core
Library             RW.platform
Library             RW.Azure.Cosmosdb

Suite Setup         Suite Initialization


*** Tasks ***
${TASK_TITLE}
    [Documentation]    Executes a user-provided Cosmos DB SQL query and pushes the count of results as a metric.
    [Tags]    azure    cosmosdb    query    generic    sli
    ${count}=    RW.Azure.Cosmosdb.Count Query Results
    ...    ${DATABASE_NAME}
    ...    ${CONTAINER_NAME}
    ...    ${COSMOSDB_QUERY}
    ...    ${QUERY_PARAMETERS}
    RW.Core.Push Metric    ${count}


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
    ...    description=The SQL query to execute. Use SELECT COUNT(1) to count matching items, or any SELECT to count returned rows.
    ...    pattern=\w*
    ...    example=SELECT COUNT(1) FROM c WHERE c.status = 'error'
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
    ...    example="Count error documents in Cosmos DB"
    
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
    
    # Smart authentication with fallback
    ${auth_method}=    Set Variable    none
    ${has_azure_creds}=    Evaluate    bool($azure_credentials)
    ${has_cosmosdb_key}=    Evaluate    bool($cosmosdb_key)
    
    IF    ${has_azure_creds}
        # Try Azure AD authentication
        TRY
            RW.Azure.Cosmosdb.Connect To Cosmosdb With Azure Credentials    ${COSMOSDB_ENDPOINT}
            ${auth_method}=    Set Variable    azure_credentials
        EXCEPT    AS    ${azure_error}
            Log    Azure AD authentication failed: ${azure_error}    WARN
            IF    ${has_cosmosdb_key}
                Log    Falling back to key-based authentication...    WARN
                RW.Azure.Cosmosdb.Connect To Cosmosdb    ${COSMOSDB_ENDPOINT}    ${cosmosdb_key}
                ${auth_method}=    Set Variable    cosmosdb_key
            ELSE
                Fail    Azure AD authentication failed and no cosmosdb_key provided: ${azure_error}
            END
        END
    ELSE IF    ${has_cosmosdb_key}
        # Only cosmosdb_key provided
        RW.Azure.Cosmosdb.Connect To Cosmosdb    ${COSMOSDB_ENDPOINT}    ${cosmosdb_key}
        ${auth_method}=    Set Variable    cosmosdb_key
    ELSE
        # No credentials provided
        Fail    No authentication credentials provided. Configure either azure_credentials or cosmosdb_key secret.
    END
    
    Log    Successfully connected using authentication method: ${auth_method}    INFO

