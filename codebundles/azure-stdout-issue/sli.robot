*** Settings ***
Documentation       Runs an ad-hoc user-provided command, and if the provided command outputs a non-empty string to stdout then a health score of 0 (unhealthy) is pushed, otherwise if there is no output, indicating no issues, then a 1 is pushed.
...                 User commands should filter expected/healthy content (eg: with grep) and only output found errors.


Metadata            Author    jon-funk
Metadata            Display Name    Metric from Azure CLI Command
Metadata            Supports    Azure

Library             BuiltIn
Library             RW.Core
Library             RW.platform
Library             OperatingSystem
Library             RW.CLI

Suite Setup         Suite Initialization


*** Tasks ***
${TASK_TITLE}
    [Documentation]    Runs a user provided azure cli command and if the return string is non-empty it indicates an error was found, pushing a health score of 0, otherwise pushes a 1.
    [Tags]    azure    cli    generic
    ${rsp}=    RW.CLI.Run Cli
    ...    cmd=${AZURE_COMMAND}
    ...    timeout_seconds=${TIMEOUT_SECONDS}
    ...    env=${env}
    ${history}=    RW.CLI.Pop Shell History
    ${STDOUT}=    Set Variable    ${rsp.stdout}
    IF    """${rsp.stdout}""" != ""
        RW.Core.Push Metric     0
    ELSE
        RW.Core.Push Metric     1
    END

*** Keywords ***
Suite Initialization
    ${azure_credentials}=    RW.Core.Import Secret
    ...    azure_credentials
    ...    type=string
    ...    description=The secret containing AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_CLIENT_SECRET, AZURE_SUBSCRIPTION_ID
    ...    pattern=\w*

    ${AZURE_COMMAND}=    RW.Core.Import User Variable    AZURE_COMMAND
    ...    type=string
    ...    description=The az cli command to run. Can use tools like jq.
    ...    pattern=\w*
    ...    example=az monitor metrics list --resource myapp --resource-group myrg --resource-type Microsoft.Web/sites --metric "HealthCheckStatus" --interval 5m | -r '.value[].timeseries[].data[0].average'
    ${TASK_TITLE}=    RW.Core.Import User Variable    TASK_TITLE
    ...    type=string
    ...    description=The name of the task to run. This is useful for helping find this generic task with RunWhen Digital Assistants. 
    ...    pattern=\w*
    ...    example="Count the number of pods in the namespace"
    ${TIMEOUT_SECONDS}=    RW.Core.Import User Variable    TIMEOUT_SECONDS
    ...    type=string
    ...    description=The amount of seconds before the command is killed. 
    ...    pattern=\w*
    ...    example=60
    ...    default=60
    ${OS_PATH}=    Get Environment Variable    PATH
    ${CODEBUNDLE_TEMP_DIR}=    Get Environment Variable    CODEBUNDLE_TEMP_DIR
    Set Suite Variable
    ...    ${env}
    ...    {"HOME":"${CODEBUNDLE_TEMP_DIR}","PATH":"$PATH:${OS_PATH}"}
    ${powershell_auth}=     RW.CLI.Run Cli
    ...    cmd=pwsh -Command "\$PSStyle.OutputRendering = 'PlainText'; \$ProgressPreference = 'SilentlyContinue'; Install-Module Az.Accounts -Scope CurrentUser -Force -ErrorAction SilentlyContinue; Import-Module Az.Accounts; \$token = (az account get-access-token --output json | ConvertFrom-Json).accessToken; \$account = az account show --output json | ConvertFrom-Json; Connect-AzAccount -AccessToken \$token -AccountId \$account.user.name -TenantId \$account.tenantId -SubscriptionId \$account.id | Out-Null"
    ...    timeout_seconds=30