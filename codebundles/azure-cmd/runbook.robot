*** Settings ***
Documentation       This taskset runs a user provided azure command and adds the output to the report. Command line tools like jq are available.

Metadata            Author    jon-funk
Metadata            Display Name    Azure CLI Command
Metadata            Supports    Azure

Library             BuiltIn
Library             RW.Core
Library             RW.platform
Library             OperatingSystem
Library             RW.CLI

Suite Setup         Suite Initialization


*** Tasks ***
${TASK_TITLE}
    [Documentation]    Runs a user provided azure cli command and adds the output to the report.
    [Tags]    azure    cli    generic
    ${rsp}=    RW.CLI.Run Cli
    ...    cmd=${AZURE_COMMAND}
    ...    timeout_seconds=300
    ${history}=    RW.CLI.Pop Shell History
    RW.Core.Add Pre To Report    Command stdout: ${rsp.stdout}
    RW.Core.Add Pre To Report    Command stderr: ${rsp.stderr}
    RW.Core.Add Pre To Report    Commands Used: ${history}


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
    ...    example=az monitor metrics list --resource myapp --resource-group myrg --resource-type Microsoft.Web/sites --metric "HealthCheckStatus" --interval 5m | -r '.value[].timeseries[].data[].average'
    ${TASK_TITLE}=    RW.Core.Import User Variable    TASK_TITLE
    ...    type=string
    ...    description=The name of the task to run. This is useful for helping find this generic task with RunWhen Digital Assistants. 
    ...    pattern=\w*
    ...    example="Count the number of pods in the namespace"