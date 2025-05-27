*** Settings ***
Documentation       This SLI runs a user provided curl command and can push the result as a metric. Command line tools like jq are available. Accepts HEADERS as a secret.
Metadata            Author    stewartshea
Metadata            Display Name    cURL CLI Command
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
    IF  '${HEADERS}' != ''
        Set Suite Variable    ${CURL_COMMAND}    ${CURL_COMMAND} -K ./HEADERS
    END

    ${rsp}=    RW.CLI.Run Cli
    ...    cmd=${CURL_COMMAND}
    ...    secret_file__HEADERS=${HEADERS}
    RW.Core.Push Metric    ${rsp.stdout}


*** Keywords ***
Suite Initialization
    ${HEADERS}=        RW.Core.Import Secret    HEADERS
    ...    type=string
    ...    description=The secret containing any headers that should be passed along in the curl call. Must be in the form of a file that cURL can use with the -K option.
    ...    pattern=\w*
    ...    example='header = "Authorization: Bearer TOKEN"' 
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

