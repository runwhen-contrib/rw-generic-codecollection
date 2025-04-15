*** Settings ***
Documentation       Runs an ad-hoc user-provided command, and pushes the command's stdout as the health metric.
...                 If no output is produced, the resulting metric is empty; if the command produces output, that exact text is used as the metric.
...                 User commands should produce the desired health metric or numeric value if needed—e.g., output "0" if unhealthy or "1" if healthy.
Metadata            Author    stewartshea
Metadata            Display Name    Metric from cURL CLI Command
Metadata            Supports    cURL

Library             BuiltIn
Library             RW.Core
Library             RW.platform
Library             OperatingSystem
Library             RW.CLI

Suite Setup         Suite Initialization


*** Tasks ***
${TASK_TITLE}
    [Documentation]    Runs a user-provided cURL command. If any headers are provided, appends `-K ./HEADERS`. If a post-processing command is provided, it appends `| <post-process>` to the cURL command before running. Finally, it pushes the command's stdout as the health metric.
    [Tags]            curl    cli    generic

    IF  '${HEADERS}' != ''
        Set Suite Variable    ${CURL_COMMAND}    ${CURL_COMMAND} -K ./HEADERS
    END

    IF  '${POST_PROCESS}' != ''
        Set Suite Variable    ${CURL_COMMAND}    ${CURL_COMMAND} | ${POST_PROCESS}
    END

    ${rsp}=    RW.CLI.Run Cli
    ...        cmd=${CURL_COMMAND}
    ...        secret_file__HEADERS=${HEADERS}
    ${history}=    RW.CLI.Pop Shell History
    ${STDOUT}=     Set Variable    ${rsp.stdout}
    RW.Core.Push Metric    ${STDOUT}


*** Keywords ***
Suite Initialization
    ${HEADERS}=         RW.Core.Import Secret    HEADERS
    ...                 type=string
    ...                 description=The secret containing any headers that should be passed in the cURL call (in a file format usable by -K).
    ...                 pattern=\w*
    ...                 example='header = "Authorization: Bearer TOKEN"'

    ${CURL_COMMAND}=     RW.Core.Import User Variable    CURL_COMMAND
    ...                 type=string
    ...                 description=The base cURL command to run, without headers or post-processing.
    ...                 pattern=\w*
    ...                 example="curl -X POST https://postman-echo.com/post --fail --silent --show-error"

    ${TASK_TITLE}=       RW.Core.Import User Variable    TASK_TITLE
    ...                 type=string
    ...                 description=The title of the task to run. Useful for referencing this generic task with RunWhen Engineering Assistants.
    ...                 pattern=\w*
    ...                 example="Count the number of pods in the namespace"

    ${POST_PROCESS}=     RW.Core.Import User Variable    POST_PROCESS
    ...                 type=string
    ...                 description=An optional command to run after cURL finishes (e.g., piping output to jq). This is automatically piped from cURL command output. 
    ...                 pattern=\w*
    ...                 example="jq -r '.json'"
