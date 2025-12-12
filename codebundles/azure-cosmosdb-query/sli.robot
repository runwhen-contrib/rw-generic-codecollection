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
    TRY
        ${results}=    RW.Azure.Cosmosdb.Query Container
        ...    ${DATABASE_NAME}
        ...    ${CONTAINER_NAME}
        ...    ${COSMOSDB_QUERY}
        ...    ${QUERY_PARAMETERS}
        ${results_list}=    Evaluate    json.loads($results)    json
        ${count}=    Extract Count From Results    ${COSMOSDB_QUERY}    ${results_list}
        RW.Core.Add Pre To Report    Query: ${COSMOSDB_QUERY}
        RW.Core.Add Pre To Report    Count: ${count}
        RW.Core.Add Pre To Report    Results:\n${results}
        RW.Core.Push Metric    ${count}
    EXCEPT    AS    ${error_message}
        RW.Core.Add Pre To Report    Error executing query: ${error_message}
        Fail    Failed to execute Cosmos DB query: ${error_message}
    END


*** Keywords ***
Extract Count From Results
    [Arguments]    ${query}    ${results_list}
    [Documentation]    Extracts count from query results, handling both regular queries and COUNT aggregate queries
    
    # Check if query is a COUNT aggregate query using regex
    ${is_count_query}=    Evaluate    bool(__import__('re').search(r'\\bCOUNT\\s*\\(', $query, __import__('re').IGNORECASE))
    
    IF    ${is_count_query} and ${results_list}
        # This is a COUNT query - extract the count value
        ${first_item}=    Set Variable    ${results_list}[0]
        ${first_item_type}=    Evaluate    type($first_item).__name__
        
        IF    "${first_item_type}" == "int" or "${first_item_type}" == "float"
            # SELECT VALUE COUNT(1) returns just a number
            ${count}=    Convert To Integer    ${first_item}
            RETURN    ${count}
        ELSE IF    "${first_item_type}" == "dict"
            # SELECT COUNT(1) returns an object - try different field names
            ${has_dollar1}=    Evaluate    "$1" in $first_item
            ${has_count}=    Evaluate    "count" in $first_item
            ${has_Count}=    Evaluate    "Count" in $first_item
            
            IF    ${has_dollar1}
                ${count}=    Convert To Integer    ${first_item}[$1]
                RETURN    ${count}
            ELSE IF    ${has_count}
                ${count}=    Convert To Integer    ${first_item}[count]
                RETURN    ${count}
            ELSE IF    ${has_Count}
                ${count}=    Convert To Integer    ${first_item}[Count]
                RETURN    ${count}
            ELSE
                # Try to extract first value if it's numeric
                ${first_value}=    Evaluate    list($first_item.values())[0]
                ${value_type}=    Evaluate    type($first_value).__name__
                IF    "${value_type}" == "int" or "${value_type}" == "float"
                    ${count}=    Convert To Integer    ${first_value}
                    RETURN    ${count}
                END
            END
        END
    END
    
    # Fall back to counting items in the list
    ${count}=    Evaluate    len($results_list)
    RETURN    ${count}

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
        Fail    No authentication credentials provided. Configure either azure_credentials or cosmosdb_key secret.
    END
    
    Log    Successfully connected using authentication method: ${auth_method}    INFO

