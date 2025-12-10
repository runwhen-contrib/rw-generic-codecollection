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
    ${results}=    RW.Azure.Cosmosdb.Query Container
    ...    ${DATABASE_NAME}
    ...    ${CONTAINER_NAME}
    ...    ${COSMOSDB_QUERY}
    ...    ${QUERY_PARAMETERS}
    RW.Core.Add Pre To Report    Query: ${COSMOSDB_QUERY}
    RW.Core.Add Pre To Report    Results:\n${results}


*** Keywords ***
Suite Initialization
    ${cosmosdb_endpoint}=    RW.Core.Import Secret
    ...    cosmosdb_endpoint
    ...    type=string
    ...    description=The Cosmos DB account endpoint URL (e.g., https://myaccount.documents.azure.com:443/)
    ...    pattern=\w*
    ${cosmosdb_key}=    RW.Core.Import Secret
    ...    cosmosdb_key
    ...    type=string
    ...    description=The Cosmos DB account key
    ...    pattern=\w*
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
    
    RW.Azure.Cosmosdb.Connect To Cosmosdb    ${cosmosdb_endpoint}    ${cosmosdb_key}

