*** Settings ***
Documentation       This taskset runs a user-provided cURL command and adds its output to the report. Command line tools like jq are available. 
...                 If HEADERS is provided, -K ./HEADERS is appended to the base command.
...                 If POST_PROCESS is provided, the command output is piped to POST_PROCESS.
Metadata            Author    stewartshea
Metadata            Display Name    cURL CLI Command with Headers
Metadata            Supports    cURL

Library             BuiltIn
Library             RW.Core
Library             RW.platform
Library             OperatingSystem
Library             RW.CLI

Suite Setup         Suite Initialization


*** Tasks ***
${TASK_TITLE}
    [Documentation]    Runs a user-provided cURL command, optionally includes headers (-K ./HEADERS), optionally pipes output to POST_PROCESS, and adds the outputs to the report.
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

    ${history}=    RW.CLI.Pop Shell History

    RW.Core.Add Pre To Report    Command stdout: ${rsp.stdout}
    RW.Core.Add Pre To Report    Command stderr: ${rsp.stderr}
    RW.Core.Add Pre To Report    Commands Used: ${history}


*** Keywords ***
Suite Initialization
    ${HEADERS}=         RW.Core.Import Secret    HEADERS
    ...                 type=string
    ...                 description=The secret containing any headers that should be passed to cURL. Must be a file format cURL can use with -K.
    ...                 pattern=\w*
    ...                 example='header = "Authorization: Bearer TOKEN"'

    ${CURL_COMMAND}=     RW.Core.Import User Variable    CURL_COMMAND
    ...                 type=string
    ...                 description=The base cURL command to run.
    ...                 pattern=\w*
    ...                 example="curl -X POST https://postman-echo.com/post --fail --silent --show-error 

    ${TASK_TITLE}=       RW.Core.Import User Variable    TASK_TITLE
    ...                 type=string
    ...                 description=The name of the task to run. Useful for referencing this generic task in RunWhen Digital Assistants.
    ...                 pattern=\w*
    ...                 example="Curl the API endpoint and parse results with jq"

    ${POST_PROCESS}=     RW.Core.Import User Variable    POST_PROCESS
    ...                 type=string
    ...                 description=An optional command to run after cURL, e.g., piping to jq.
    ...                 pattern=\w*
    ...                 example="jq -r '.json'"

    Set Suite Variable    ${TASK_TITLE}      ${TASK_TITLE}
    Set Suite Variable    ${CURL_COMMAND}    ${CURL_COMMAND}
