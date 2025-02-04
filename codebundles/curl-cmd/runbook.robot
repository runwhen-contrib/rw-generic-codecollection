*** Settings ***
Documentation       This taskset runs a user provided curl command and adds the output to the report. Command line tools like jq are available.
Metadata            Author    jon-funk
Metadata            Display Name    cURL CLI Command
Metadata            Supports    cURL

Library             BuiltIn
Library             RW.Core
Library             RW.platform
Library             OperatingSystem
Library             RW.CLI

Suite Setup         Suite Initialization


*** Tasks ***
Run User-Provided Curl Command and Add Output to Report for `${TASK_TITLE}` in `${SPECIFIC_LOCATION}`
    [Documentation]    Runs a user provided curl command and adds the output to the report.
    [Tags]    curl    cli    generic
    ${rsp}=    RW.CLI.Run Cli
    ...    cmd=${CURL_COMMAND}
    ${history}=    RW.CLI.Pop Shell History
    RW.Core.Add Pre To Report    Command stdout: ${rsp.stdout}
    RW.Core.Add Pre To Report    Command stderr: ${rsp.stderr}
    RW.Core.Add Pre To Report    Commands Used: ${history}


*** Keywords ***
Suite Initialization
    ${CURL_COMMAND}=    RW.Core.Import User Variable    CURL_COMMAND
    ...    type=string
    ...    description=The curl command to run. Can use tools like jq.
    ...    pattern=\w*
    ...    example="curl -X POST https://postman-echo.com/post --fail --silent --show-error | jq -r '.json'"
    Run User-Provided Curl Command and Add Output to Report for `${TASK_TITLE}` in `${SPECIFIC_LOCATION}`=    RW.Core.Import User Variable    TASK_TITLE
    ...    type=string
    ...    description=The name of the task to run. This is useful for helping find this generic task with RunWhen Digital Assistants. 
    ...    pattern=\w*
    ...    example="Curl the API endpoint and parse results with jq"
    Set Suite Variable    Run User-Provided Curl Command and Add Output to Report for `${TASK_TITLE}` in `${SPECIFIC_LOCATION}`    Run User-Provided Curl Command and Add Output to Report for `${TASK_TITLE}` in `${SPECIFIC_LOCATION}`
    Set Suite Variable    ${CURL_COMMAND}    ${CURL_COMMAND}
