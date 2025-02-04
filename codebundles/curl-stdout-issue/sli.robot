*** Settings ***
Documentation       Runs an ad-hoc user-provided command, and if the provided command outputs a non-empty string to stdout then a health score of 0 (unhealthy) is pushed, otherwise if there is no output, indicating no issues, then a 1 is pushed.
...                 User commands should filter expected/healthy content (eg: with grep) and only output found errors.

Metadata            Author    jon-funk
Metadata            Display Name    Metric from cURL CLI Command
Metadata            Supports    cURL

Library             BuiltIn
Library             RW.Core
Library             RW.platform
Library             OperatingSystem
Library             RW.CLI

Suite Setup         Suite Initialization


*** Tasks ***
Check Health Status with CURL_COMMAND in `${TASK_TITLE}`
    [Documentation]    Runs a user provided curl command and if the return string is non-empty it indicates an error was found, pushing a health score of 0, otherwise pushes a 1.
    [Tags]    curl    cli    generic
    ${rsp}=    RW.CLI.Run Cli
    ...    cmd=${CURL_COMMAND}
    ${history}=    RW.CLI.Pop Shell History
    ${STDOUT}=    Set Variable    ${rsp.stdout}
    IF    """${rsp.stdout}""" != ""
        RW.Core.Push Metric     0
    ELSE
        RW.Core.Push Metric     1
    END


*** Keywords ***
Suite Initialization
    ${CURL_COMMAND}=    RW.Core.Import User Variable    CURL_COMMAND
    ...    type=string
    ...    description=The curl command to run. Can use tools like jq.
    ...    pattern=\w*
    ...    example="curl -X POST https://postman-echo.com/post --fail --silent --show-error | jq -r '.json'"
    Check Health Status with CURL_COMMAND in `${TASK_TITLE}`=    RW.Core.Import User Variable    TASK_TITLE
    ...    type=string
    ...    description=The name of the task to run. This is useful for helping find this generic task with RunWhen Digital Assistants. 
    ...    pattern=\w*
    ...    example="Count the number of pods in the namespace"

