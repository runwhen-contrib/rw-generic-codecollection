*** Settings ***
Documentation       This CodeBundle queries Loki (via Grafana) using relative times like 30m, 2h, or 2d, 
...                 which are automatically converted to nanosecond timestamps. If HEADERS is provided, 
...                 '-K ./HEADERS' is appended for authentication. If POST_PROCESS is provided, 
...                 the command output is piped to that command (e.g., jq).
Metadata            Author       stewartshea
Metadata            Display Name     Loki Query via Grafana (Relative Times)
Metadata            Supports     Grafana Loki

Library             BuiltIn
Library             RW.Core
Library             RW.platform
Library             OperatingSystem
Library             RW.CLI
Library             DateTime
Library             String

Suite Setup         Suite Initialization


*** Tasks ***
${TASK_TITLE}
    [Documentation]    Builds and runs a Loki query through Grafana’s proxy, allowing 
    ...                relative start/end times (like 30m, 2h, 2d). The output is then
    ...                added to the Robot report.
    [Tags]            grafana    loki    cli    generic    access:read-only

    IF   $DATASOURCE_ID == ''
        ${LIST_CMD}=    Set Variable    curl -s -X GET "${GRAFANA_URL}/api/datasources"
        ${LIST_CMD}=    Set Variable    ${LIST_CMD} -K ./HEADERS
        ${LIST_CMD}=    Set Variable    ${LIST_CMD} | jq -r --arg DS "${DATASOURCE_UID}" '.[] | select(.uid == $DS) | .id'

        ${list_rsp}=    RW.CLI.Run Cli    cmd=${LIST_CMD}
        ${DATASOURCE_ID}=    Convert To Integer    ${list_rsp.stdout}
    END

    # 1) Build the base command
    Set Suite Variable    ${GRAFANA_LOKI_COMMAND}    curl -G "${GRAFANA_URL}/api/datasources/proxy/${DATASOURCE_ID}/loki/api/v1/query_range"

    # 2) Always add the main query
    Set Suite Variable    ${GRAFANA_LOKI_COMMAND}    ${GRAFANA_LOKI_COMMAND} --data-urlencode 'query=${LOKI_QUERY}'

    # 3) Convert and apply LOKI_LIMIT, LOKI_START, LOKI_END if provided
    IF  $LOKI_LIMIT != ''
        Set Suite Variable    ${GRAFANA_LOKI_COMMAND}    ${GRAFANA_LOKI_COMMAND} --data-urlencode 'limit=${LOKI_LIMIT}'
    END

    IF  $LOKI_START != ''
        ${start_epoch}=    Convert Relative Time To Nano Epoch    ${LOKI_START}
        Set Suite Variable    ${GRAFANA_LOKI_COMMAND}    ${GRAFANA_LOKI_COMMAND} --data-urlencode 'start=${start_epoch}'
    END

    IF  $LOKI_END != ''
        ${end_epoch}=      Convert Relative Time To Nano Epoch    ${LOKI_END}
        Set Suite Variable    ${GRAFANA_LOKI_COMMAND}    ${GRAFANA_LOKI_COMMAND} --data-urlencode 'end=${end_epoch}'
    END

    # 4) Conditionally append headers
    IF  $HEADERS != ''
        Set Suite Variable    ${GRAFANA_LOKI_COMMAND}    ${GRAFANA_LOKI_COMMAND} -K ./HEADERS
    END

    # 5) Optionally pipe the cURL output to a post-processing command (e.g. jq)
    IF  $POST_PROCESS != ''
        Set Suite Variable    ${GRAFANA_LOKI_COMMAND}    ${GRAFANA_LOKI_COMMAND} | ${POST_PROCESS}
    END

    # 6) Run the assembled command
    ${rsp}=    RW.CLI.Run Cli
    ...        cmd=${GRAFANA_LOKI_COMMAND}
    ...        secret_file__HEADERS=${HEADERS}

    ${history}=    RW.CLI.Pop Shell History

    # 7) Add output to the report
    RW.Core.Add Pre To Report    Command stdout: ${rsp.stdout}
    RW.Core.Add Pre To Report    Command stderr: ${rsp.stderr}
    RW.Core.Add Pre To Report    Commands Used: ${history}


*** Keywords ***
Suite Initialization
    ${GRAFANA_URL}=      RW.Core.Import User Variable    GRAFANA_URL
    ...                 type=string
    ...                 description=The base URL to your Grafana instance (e.g. https://my-grafana.org).
    ...                 pattern=\w*
    ...                 example=https://my-grafana.org

    ${DATASOURCE_ID}=    RW.Core.Import User Variable    DATASOURCE_ID
    ...                 type=string
    ...                 description=Numeric ID of your Loki data source in Grafana.
    ...                 pattern=\w*
    ...                 example=2
    
    ${DATASOURCE_UID}=    RW.Core.Import User Variable    DATASOURCE_UID
    ...                 type=string
    ...                 description=Name your Loki data source in Grafana.
    ...                 pattern=\w*
    ...                 example=2

    ${LOKI_QUERY}=       RW.Core.Import User Variable    LOKI_QUERY
    ...                 type=string
    ...                 description=The Loki log query expression (e.g. {app="myapp"}).
    ...                 pattern=\w*
    ...                 example={app="myapp"}

    ${LOKI_LIMIT}=       RW.Core.Import User Variable    LOKI_LIMIT
    ...                 type=string
    ...                 description=Optional. The maximum number of entries to return.
    ...                 pattern=\w*
    ...                 example=100

    ${LOKI_START}=       RW.Core.Import User Variable    LOKI_START
    ...                 type=string
    ...                 description=Optional. A relative time (30m, 2h, 2d) or an absolute timestamp in nanoseconds or RFC3339. If relative, it is converted to "now - X".
    ...                 pattern=\w*
    ...                 example=2h
    ...                 default=30m

    ${LOKI_END}=         RW.Core.Import User Variable    LOKI_END
    ...                 type=string
    ...                 description=Optional. A relative or absolute time. If relative, it is also processed as "now - X".
    ...                 pattern=\w*
    ...                 example=30m

    ${HEADERS}=          RW.Core.Import Secret    HEADERS
    ...                 type=string
    ...                 description=Optional file containing headers for cURL (e.g. auth token) in -K format.
    ...                 pattern=\w*
    ...                 example='header = "Authorization: Bearer GRAFANA_TOKEN"'

    ${POST_PROCESS}=      RW.Core.Import User Variable    POST_PROCESS
    ...                 type=string
    ...                 description=Optional command to parse/transform cURL output (e.g., jq).
    ...                 pattern=\w*
    ...                 example="jq -r '.data.result[].values[][1]'"

    ${TASK_TITLE}=        RW.Core.Import User Variable    TASK_TITLE
    ...                 type=string
    ...                 description=The name of the task to run. 
    ...                 pattern=\w*
    ...                 example="Fetch logs from Loki via Grafana"
    ...                 default="Loki Query Through Grafana"

    Set Suite Variable    ${TASK_TITLE}    ${TASK_TITLE}


# -----------------------------------
# Helper to convert "30m", "2h", etc.
# to nanosecond timestamps for Loki
# -----------------------------------
*** Keywords ***
Convert Relative Time To Nano Epoch
    [Arguments]    ${time_string}
    # Example usage:
    #   ${start_ns}=  Convert Relative Time To Nano Epoch    2h
    #   => returns now - 2 hours, in nanoseconds (e.g., 1681594963000000000)

    # 1) Extract the last character to see if it ends in s/m/h/d
    ${length}=    Get Length    ${time_string}
    ${start_index}=    Evaluate    ${length} - 1
    ${last_char}=    Get Substring    ${time_string}    ${start_index}    ${length}

    # 2) If last_char is s, m, h, or d => parse as a relative time
    IF  $last_char in ["s", "m", "h", "d"]
        # The numeric portion is everything but the last character
        ${without_last}=    Get Substring    ${time_string}    0    ${start_index}
        ${amount}=          Convert To Integer    ${without_last}

        # Convert that amount to total seconds
        ${seconds}=  Set Variable    0
        IF    '${last_char}' == 's'
            ${seconds}=    Set Variable    ${amount}
        ELSE IF    '${last_char}' == 'm'
            ${seconds}=    Set Variable    ${amount} * 60
        ELSE IF    '${last_char}' == 'h'
            ${seconds}=    Set Variable    ${amount} * 3600
        ELSE IF    '${last_char}' == 'd'
            ${seconds}=    Set Variable    ${amount} * 86400
        END

        # 3) Get the current time in seconds since epoch, then convert to ns
        ${now_secs}=    Get Current Date    result_format=epoch
        ${now_int}=     Convert To Integer    ${now_secs}    # remove decimal if any
        ${now_ns}=      Evaluate    ${now_int} * 1000000000

        # 4) Subtract the offset
        ${offset_ns}=   Evaluate    ${seconds} * 1000000000
        ${relative_ns}=     Evaluate    ${now_ns} - ${offset_ns}

        Return From Keyword     ${relative_ns}
    END

    # 5) Otherwise, assume it's already an absolute timestamp or RFC3339. Return unchanged.
    Return From Keyword    ${time_string}
