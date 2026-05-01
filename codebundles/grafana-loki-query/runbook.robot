*** Settings ***
Documentation       This CodeBundle queries Loki via Grafana, supporting relative times like 30m, 2h, 2d.
...                 Two modes are supported via QUERY_MODE:
...                   - "proxy" (default): hits /api/datasources/proxy/{uid|id}/loki/api/v1/query_range.
...                   - "ds_query": hits POST /api/ds/query (the same API Grafana Explore uses). Use this
...                     if "proxy" fails (for example with TLS errors like
...                     "x509: certificate signed by unknown authority") while Grafana Explore can run
...                     the same query successfully.
...                 LOKI_QUERY (and the JSON body in ds_query mode) are passed via base64 + stdin so
...                 LogQL containing quotes, backticks, or other shell-special characters is safe.
...                 If HEADERS is provided, '-K ./HEADERS' is appended for authentication.
...                 If POST_PROCESS is provided, the command output is piped to that command (e.g., jq).
Metadata            Author       stewartshea
Metadata            Display Name     Loki Query via Grafana (Relative Times)
Metadata            Supports     Grafana Loki

Library             BuiltIn
Library             RW.Core
Library             RW.platform
Library             OperatingSystem
Library             RW.CLI
Library             RW.Utils.Time

Suite Setup         Suite Initialization


*** Tasks ***
${TASK_TITLE}
    [Documentation]    Builds and runs a Loki query through Grafana, allowing
    ...                relative start/end times (like 30m, 2h, 2d). Uses either the
    ...                datasource proxy API (default) or Grafana's /api/ds/query API
    ...                depending on QUERY_MODE.
    [Tags]            grafana    loki    cli    generic    access:read-only

    IF    '${QUERY_MODE}' == 'ds_query'
        # ds_query mode: POST /api/ds/query (Explore's API). Times are in milliseconds.
        ${start_ms}=    Convert Relative Time To Ms Epoch    ${LOKI_START}
        ${end_ms}=      Convert Relative Time To Ms Epoch    ${LOKI_END}
        ${MAX_LINES}=   Set Variable If    '${LOKI_LIMIT}' == ''    100    ${LOKI_LIMIT}

        # Build the JSON body in Python so any quotes/backticks/etc in LOKI_QUERY are escaped properly,
        # then base64-encode it so we can pipe it into curl without shell-quoting hazards.
        ${json_body}=    Evaluate    json.dumps({"queries":[{"refId":"A","expr":$LOKI_QUERY,"queryType":"range","maxLines":int($MAX_LINES),"datasource":{"type":"loki","uid":$DATASOURCE_UID}}],"from":str($start_ms),"to":str($end_ms)})    modules=json
        ${b64_body}=     Evaluate    base64.b64encode(($json_body).encode()).decode()    modules=base64

        Set Suite Variable    ${GRAFANA_LOKI_COMMAND}    echo ${b64_body} | base64 -d | curl -sS -X POST "${GRAFANA_URL}/api/ds/query?ds_type=loki" -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Datasource-Uid: ${DATASOURCE_UID}" -H "X-Plugin-Id: loki" --data-binary @-
    ELSE
        # proxy mode: prefer the UID-based path so DATASOURCE_ID is optional.
        IF    '${DATASOURCE_ID}' != ''
            ${PROXY_TARGET}=    Set Variable    ${DATASOURCE_ID}
        ELSE
            ${PROXY_TARGET}=    Set Variable    uid/${DATASOURCE_UID}
        END

        # Pipe the LogQL via base64 so it is shell-safe regardless of contents (quotes, backticks, etc.).
        ${b64_query}=    Evaluate    base64.b64encode(($LOKI_QUERY).encode()).decode()    modules=base64

        Set Suite Variable    ${GRAFANA_LOKI_COMMAND}    echo ${b64_query} | base64 -d | curl -G "${GRAFANA_URL}/api/datasources/proxy/${PROXY_TARGET}/loki/api/v1/query_range" --data-urlencode "query@-"

        IF    $LOKI_LIMIT != ''
            Set Suite Variable    ${GRAFANA_LOKI_COMMAND}    ${GRAFANA_LOKI_COMMAND} --data-urlencode "limit=${LOKI_LIMIT}"
        END

        IF    $LOKI_START != ''
            ${start_epoch}=    Convert Relative Time To Nano Epoch    ${LOKI_START}
            Set Suite Variable    ${GRAFANA_LOKI_COMMAND}    ${GRAFANA_LOKI_COMMAND} --data-urlencode "start=${start_epoch}"
        END

        IF    $LOKI_END != ''
            ${end_epoch}=    Convert Relative Time To Nano Epoch    ${LOKI_END}
            Set Suite Variable    ${GRAFANA_LOKI_COMMAND}    ${GRAFANA_LOKI_COMMAND} --data-urlencode "end=${end_epoch}"
        END
    END

    IF    $HEADERS != ''
        Set Suite Variable    ${GRAFANA_LOKI_COMMAND}    ${GRAFANA_LOKI_COMMAND} -K ./HEADERS
    END

    IF    $POST_PROCESS != ''
        Set Suite Variable    ${GRAFANA_LOKI_COMMAND}    ${GRAFANA_LOKI_COMMAND} | ${POST_PROCESS}
    END

    ${rsp}=    RW.CLI.Run Cli
    ...        cmd=${GRAFANA_LOKI_COMMAND}
    ...        secret_file__HEADERS=${HEADERS}

    ${history}=    RW.CLI.Pop Shell History

    RW.Core.Add Pre To Report    Command stdout: ${rsp.stdout}
    RW.Core.Add Pre To Report    Command stderr: ${rsp.stderr}


*** Keywords ***
Suite Initialization
    ${GRAFANA_URL}=      RW.Core.Import User Variable    GRAFANA_URL
    ...                 type=string
    ...                 description=The base URL to your Grafana instance (e.g. https://my-grafana.org).
    ...                 pattern=\w*
    ...                 example=https://my-grafana.org

    ${QUERY_MODE}=       RW.Core.Import User Variable    QUERY_MODE
    ...                 type=string
    ...                 description=Which Grafana API to use. "proxy" (default) hits /api/datasources/proxy/{uid|id}/loki/api/v1/query_range. "ds_query" hits POST /api/ds/query (the same API Grafana Explore uses). Use "ds_query" if "proxy" fails (e.g. with TLS errors like "x509: certificate signed by unknown authority") while Grafana Explore can run the same query.
    ...                 pattern=\w*
    ...                 default=proxy
    ...                 example=ds_query

    ${DATASOURCE_UID}=   RW.Core.Import User Variable    DATASOURCE_UID
    ...                 type=string
    ...                 description=UID of your Loki datasource in Grafana. Recommended primary identifier (easier to find than the numeric ID and stable across environments). Required.
    ...                 pattern=\w*
    ...                 example=logs-production

    ${DATASOURCE_ID}=    RW.Core.Import User Variable    DATASOURCE_ID
    ...                 type=string
    ...                 description=Optional. Numeric ID of your Loki datasource. Only used in QUERY_MODE=proxy. If empty, the UID-based proxy URL is used instead.
    ...                 pattern=\w*
    ...                 default=
    ...                 example=201

    ${LOKI_QUERY}=       RW.Core.Import User Variable    LOKI_QUERY
    ...                 type=string
    ...                 description=The Loki log query expression (e.g. {app="myapp"}).
    ...                 pattern=\w*
    ...                 example={app="myapp"}

    ${LOKI_LIMIT}=       RW.Core.Import User Variable    LOKI_LIMIT
    ...                 type=string
    ...                 description=Optional. Maximum entries to return. In QUERY_MODE=proxy this is the Loki "limit" parameter; in QUERY_MODE=ds_query it becomes "maxLines" (defaults to 100 if unset).
    ...                 pattern=\w*
    ...                 default=
    ...                 example=100

    ${LOKI_START}=       RW.Core.Import User Variable    LOKI_START
    ...                 type=string
    ...                 description=Optional. A relative time (30m, 2h, 2d) or an absolute timestamp. If relative, it is converted to "now - X" (nanoseconds in proxy mode, milliseconds in ds_query mode).
    ...                 pattern=\w*
    ...                 example=2h
    ...                 default=30m

    ${LOKI_END}=         RW.Core.Import User Variable    LOKI_END
    ...                 type=string
    ...                 description=Optional. A relative or absolute time. Same semantics as LOKI_START. In ds_query mode an empty value defaults to "now".
    ...                 pattern=\w*
    ...                 example=30m
    ...                 default=

    ${HEADERS}=          RW.Core.Import Secret    HEADERS
    ...                 type=string
    ...                 description=Optional file containing headers for cURL (e.g. auth token) in -K format.
    ...                 pattern=\w*
    ...                 example='header = "Authorization: Bearer GRAFANA_TOKEN"'

    ${POST_PROCESS}=     RW.Core.Import User Variable    POST_PROCESS
    ...                 type=string
    ...                 description=Optional command to parse/transform cURL output (e.g., jq).
    ...                 pattern=\w*
    ...                 example="jq -r '.data.result[].values[][1]'"

    ${TASK_TITLE}=       RW.Core.Import User Variable    TASK_TITLE
    ...                 type=string
    ...                 description=The name of the task to run.
    ...                 pattern=\w*
    ...                 example="Fetch logs from Loki via Grafana"
    ...                 default="Loki Query Through Grafana"

    Set Suite Variable    ${TASK_TITLE}    ${TASK_TITLE}
