*** Settings ***
Documentation       This SLI runs a user-provided cURL command and can push the result as a metric. Optional headers and post-processing commands are supported.
...                 If HEADERS is provided, the file is appended to the cURL command using -K.
...                 If POST_PROCESS is provided, it is appended as a pipe (|) to further process the output (e.g., jq).
Metadata            Author    stewartshea
Metadata            Display Name    cURL CLI Command Metric
Metadata            Supports    cURL

Library             BuiltIn
Library             RW.Core
Library             RW.platform
Library             OperatingSystem
Library             RW.CLI

Suite Setup         Suite Initialization


*** Tasks ***
${TASK_TITLE}
    [Documentation]    Runs a user-provided cURL command. If HEADERS is set, applies -K ./HEADERS. 
    ...                If POST_PROCESS is set, pipes cURL output through that command. 
    ...                Finally, pushes the resulting stdout as a metric.
    [Tags]            curl    cli    generic

    IF  $HEADERS != ''
        Set Suite Variable    ${CURL_COMMAND}    ${CURL_COMMAND} -K ./HEADERS
    END

    IF  $POST_PROCESS != ''
        Set Suite Variable    ${CURL_COMMAND}    ${CURL_COMMAND} | ${POST_PROCESS}
    END

    ${rsp}=    RW.CLI.Run Cli
    ...        cmd=${CURL_COMMAND}
    ...        secret_file__HEADERS=${HEADERS}
    RW.Core.Push Metric    ${rsp.stdout}


*** Keywords ***
Suite Initialization
    ${HEADERS}=        RW.Core.Import Secret    HEADERS
    ...                type=string
    ...                description=The secret containing any headers that should be passed to cURL. Must be a file format cURL can use with -K.
    ...                pattern=\w*
    ...                example='header = "Authorization: Bearer TOKEN"'

    ${CURL_COMMAND}=    RW.Core.Import User Variable    CURL_COMMAND
    ...                type=string
    ...                description=The base cURL command to run.
    ...                pattern=\w*
    ...                example="curl -X POST https://postman-echo.com/post --fail --silent --show-error

    ${TASK_TITLE}=      RW.Core.Import User Variable    TASK_TITLE
    ...                type=string
    ...                description=The name of the task to run. Useful for referencing this generic SLI with RunWhen Digital Assistants.
    ...                pattern=\w*
    ...                example="Curl the API endpoint and parse results with jq"

    ${POST_PROCESS}=    RW.Core.Import User Variable    POST_PROCESS
    ...                type=string
    ...                description=An optional post-processing command to filter or transform cURL’s output (e.g. jq).
    ...                pattern=\w*
    ...                example="jq -r '.json | length'"

    Set Suite Variable    ${TASK_TITLE}      ${TASK_TITLE}
    Set Suite Variable    ${CURL_COMMAND}    ${CURL_COMMAND}
