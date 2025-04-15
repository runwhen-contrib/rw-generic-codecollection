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
    [Documentation]    Runs a user-provided cURL command; whatever is returned in stdout is pushed as the metric. 
    [Tags]            curl    cli    generic

    IF  '${HEADERS}' != ''
        Set Suite Variable    ${CURL_COMMAND}    ${CURL_COMMAND} -K ./HEADERS
    END

    ${rsp}=    RW.CLI.Run Cli
    ...        cmd=${CURL_COMMAND}
    ...        secret_file__HEADERS=${HEADERS}
    ${history}=    RW.CLI.Pop Shell History
    ${STDOUT}=     Set Variable    ${rsp.stdout}
    RW.Core.Push Metric    ${STDOUT}


*** Keywords ***
Suite Initialization
    ${HEADERS}=        RW.Core.Import Secret    HEADERS
    ...                type=string
    ...                description=The secret containing any headers that should be passed along in the cURL call (in a file format usable by -K).
    ...                pattern=\w*
    ...                example='header = "Authorization: Bearer TOKEN"'

    ${CURL_COMMAND}=    RW.Core.Import User Variable    CURL_COMMAND
    ...                type=string
    ...                description=The base cURL command to run. Can include additional tooling (like jq).
    ...                pattern=\w*
    ...                example="curl -X POST https://postman-echo.com/post --fail --silent --show-error | jq -r '.json'"

    ${TASK_TITLE}=      RW.Core.Import User Variable    TASK_TITLE
    ...                type=string
    ...                description=The name of the task to run. This is useful for referencing this generic task with RunWhen Digital Assistants.
    ...                pattern=\w*
    ...                example="Count the number of pods in the namespace"
