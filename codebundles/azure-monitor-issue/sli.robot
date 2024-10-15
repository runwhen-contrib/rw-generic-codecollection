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
    [Documentation]    Runs the configured general metric check and raises an issue if it does not match the expected value.
    [Tags]    azure    cli    metric    generic
    ${process}=    RW.CLI.Run Bash File
    ...    bash_file=metric_check.sh
    ...    env=${env}
    ...    timeout_seconds=180
    ...    include_in_history=false
    ${STDOUT}=    Set Variable    ${process.stdout}
    ${STDERR}=    Set Variable    ${process.stderr}
    ${history}=    RW.CLI.Pop Shell History
    IF    """${process.stdout}""" != ""
        RW.Core.Push Metric     0
    ELSE
        RW.Core.Push Metric     1
    END

*** Keywords ***
Suite Initialization
    ${RESOURCE_UID}=    RW.Core.Import User Variable    RESOURCE_UID
    ...    type=string
    ...    description=The resource uid to perform actions against.
    ...    pattern=\w*
    ${JQ_EXPRESSION}=    RW.Core.Import User Variable    JQ_EXPRESSION
    ...    type=string
    ...    description=The jq expression to run against the metric results.
    ...    pattern=\w*
    ...    default=".value[].timeseries[].data[-1].average < 80"
    ${METRIC_NAME}=    RW.Core.Import User Variable    METRIC_NAME
    ...    type=string
    ...    description=The metric label to query for a timeseries.
    ...    pattern=\w*
    ...    default=Percentage CPU
    ${METRIC_AGGREGATION}=    RW.Core.Import User Variable    METRIC_AGGREGATION
    ...    type=string
    ...    description=How to aggregate the metric timeseries before applying the jq expression.
    ...    pattern=\w*
    ...    default=average
    ${azure_credentials}=    RW.Core.Import Secret
    ...    azure_credentials
    ...    type=string
    ...    description=The secret containing AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_CLIENT_SECRET, AZURE_SUBSCRIPTION_ID
    ...    pattern=\w*
    Set Suite Variable
    ...    ${env}
    ...    {"RESOURCE_UID":"${RESOURCE_UID}","JQ_EXPRESSION":"${JQ_EXPRESSION}","METRIC_NAME":"${METRIC_NAME}", "METRIC_AGGREGATION":"${METRIC_AGGREGATION}"}
    ${TASK_TITLE}=    RW.Core.Import User Variable    TASK_TITLE
    ...    type=string
    ...    description=The name of the task to run. This is useful for helping find this generic task with RunWhen Digital Assistants. 
    ...    pattern=\w*
    ...    example="Count the number of pods in the namespace"