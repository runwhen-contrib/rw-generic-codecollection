*** Settings ***
Documentation       This SLI runs a user provided curl command and can push the result as a metric. Command line tools like jq are available.
Metadata            Author    jon-funk
Metadata            DisplayName    Metric cURL CLI Command
Metadata            Supports    cURL

Library             BuiltIn
Library             RW.Core
Library             RW.platform
Library             OperatingSystem
Library             RW.CLI

Suite Setup         Suite Initialization


*** Tasks ***
${TASK_TITLE}
    [Documentation]    Runs a user provided curl command and pushes the result as a metric.
    [Tags]    curl    cli    generic
    ${rsp}=    RW.CLI.Run Cli
    ...    cmd=${CURL_COMMAND}
    RW.Core.Push Metric    ${rsp.stdout}


*** Keywords ***
Suite Initialization
    ${CURL_COMMAND}=    RW.Core.Import User Variable    CURL_COMMAND
    ...    type=string
    ...    description=The curl command to run where the result can be pushed as a metric. Can use tools like jq.
    ...    pattern=\w*
    ...    example="curl -X POST https://postman-echo.com/post --fail --silent --show-error | jq -r '.json | length'"
    ${TASK_TITLE}=    RW.Core.Import User Variable    TASK_TITLE
    ...    type=string
    ...    description=The name of the task to run. This is useful for helping find this generic task with RunWhen Digital Assistants. 
    ...    pattern=\w*
    ...    example="Curl the API endpoint and parse results with jq"
    Set Suite Variable    ${TASK_TITLE}    ${TASK_TITLE}
    Set Suite Variable    ${CURL_COMMAND}    ${CURL_COMMAND}

