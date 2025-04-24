*** Settings ***
Documentation       Runs an ad-hoc user-provided command, and if the provided command outputs a non-empty string to stdout then an issue is generated with a configurable title and content.
...                 User commands should filter expected/healthy content (eg: with grep) and only output found errors.

Metadata            Author    jon-funk
Metadata            Display Name    Azure CLI Command with Issue
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
    IF    ${process.returncode} > 0
        RW.Core.Add Issue
        ...    title=${ISSUE_TITLE}
        ...    severity=${ISSUE_SEVERITY}
        ...    expected=The metric check should succeed.
        ...    actual=The metric check did not succeed, indicating it is outside of expected value(s)
        ...    reproduce_hint=Run metric_check.sh
        ...    next_steps=${ISSUE_NEXT_STEPS}
        ...    details=${ISSUE_DETAILS}
    END
    RW.Core.Add Pre To Report    Command stdout: ${process.stdout}
    RW.Core.Add Pre To Report    Command stderr: ${process.stderr}
    RW.Core.Add Pre To Report    Commands Used: ${history}


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
    ${ISSUE_TITLE}=    RW.Core.Import User Variable    ISSUE_TITLE
    ...    type=string
    ...    description=The title of the issue to raise if the command returns a non-empty string.
    ...    pattern=\w*
    ...    example="Found errors in the command output"
    ...    default="Found errors in the command output"
    ${ISSUE_NEXT_STEPS}=    RW.Core.Import User Variable    ISSUE_NEXT_STEPS
    ...    type=string
    ...    description=The next steps to take if the command returns a non-empty string.
    ...    pattern=\w*
    ...    example="Review the command output and take appropriate action."
    ...    default="Review the command output and take appropriate action."
    ${ISSUE_DETAILS}=    RW.Core.Import User Variable    ISSUE_DETAILS
    ...    type=string
    ...    description=The details of the issue to raise if the command returns a non-empty string.
    ...    pattern=\w*
    ...    example="The command returned the following output, indicating errors: \${STDOUT}"
    ...    default="The command returned the following output, indicating errors: \${STDOUT}"
    ${ISSUE_SEVERITY}=    RW.Core.Import User Variable    ISSUE_SEVERITY
    ...    type=string
    ...    description=An integer severity rating for the issue if raised, where 1 is critical, and 4 is informational.
    ...    pattern=\w*
    ...    example=3
    ...    default=3

