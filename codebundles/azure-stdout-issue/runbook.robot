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
    [Documentation]    Runs a user provided azure cli command and if the return string is non-empty, it's added to a report and used to raise an issue.
    [Tags]    azure    cli    generic
    ${rsp}=    RW.CLI.Run Cli
    ...    cmd=${AZURE_COMMAND}
    ...    env={"AZ_RESOURCE_GROUP":"${AZ_RESOURCE_GROUP}"}
    ...    secret__AZ_USERNAME=${AZ_USERNAME}
    ...    secret__AZ_SECRET_VALUE=${AZ_SECRET_VALUE}
    ...    secret__AZ_TENANT=${AZ_TENANT}
    ...    secret__AZ_SUBSCRIPTION=${AZ_SUBSCRIPTION}
    ${history}=    RW.CLI.Pop Shell History
    ${STDOUT}=    Set Variable    ${rsp.stdout}
    IF    """${rsp.stdout}""" != ""
        RW.Core.Add Issue
        ...    title=${ISSUE_TITLE}
        ...    severity=${ISSUE_SEVERITY}
        ...    expected=The command should produce no output, indicating no errors were found.
        ...    actual=Found stdout output produced by the configured command, indicating errors were found.
        ...    reproduce_hint=Run ${AZURE_COMMAND} to fetch the data that triggered this issue.
        ...    next_steps=${ISSUE_NEXT_STEPS}
        ...    details=${ISSUE_DETAILS}
        RW.Core.Add Pre To Report    Command stdout: ${rsp.stdout}
        RW.Core.Add Pre To Report    Command stderr: ${rsp.stderr}
        RW.Core.Add Pre To Report    Commands Used: ${history}
    ELSE
        RW.Core.Add Pre To Report    No output was returned from the command, indicating no errors were found.
        RW.Core.Add Pre To Report    Command stdout: ${rsp.stdout}
        RW.Core.Add Pre To Report    Command stderr: ${rsp.stderr}
        RW.Core.Add Pre To Report    Commands Used: ${history}
    END

*** Keywords ***
Suite Initialization
    ${AZ_USERNAME}=    RW.Core.Import Secret
    ...    AZ_USERNAME
    ...    type=string
    ...    description=The azure service principal client ID on the app registration.
    ...    pattern=\w*
    ${AZ_SECRET_VALUE}=    RW.Core.Import Secret
    ...    AZ_SECRET_VALUE
    ...    type=string
    ...    description=The service principal secret value on the associated credential for the app registration.
    ...    pattern=\w*
    ${AZ_TENANT}=    RW.Core.Import Secret
    ...    AZ_TENANT
    ...    type=string
    ...    description=The azure tenant ID used by the service principal to authenticate with azure.
    ...    pattern=\w*
    ${AZ_SUBSCRIPTION}=    RW.Core.Import Secret
    ...    AZ_SUBSCRIPTION
    ...    type=string
    ...    description=The azure tenant ID used by the service principal to authenticate with azure.
    ...    pattern=\w*
    ${AZ_RESOURCE_GROUP}=    RW.Core.Import User Variable    AZ_RESOURCE_GROUP
    ...    type=string
    ...    description=The resource group to perform actions against.
    ...    pattern=\w*
    ${AZURE_COMMAND}=    RW.Core.Import User Variable    AZURE_COMMAND
    ...    type=string
    ...    description=The az cli command to run. Can use tools like jq.
    ...    pattern=\w*
    ...    example=az monitor metrics list --resource myapp --resource-group myrg  --resource-type Microsoft.Web/sites --metric "HealthCheckStatus" --interval 5m | -r '.value[].timeseries[].data[].average'
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

