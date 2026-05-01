*** Settings ***
Documentation       This CodeBundle queries a Prometheus-compatible datasource (Prometheus, Mimir,
...                 Cortex, Thanos, etc.) via Grafana, supporting relative times like 30m, 2h, 2d.
...                 Two modes are supported via QUERY_MODE:
...                   - "proxy" (default): hits /api/datasources/proxy/{uid|id}/api/v1/query[_range].
...                   - "ds_query": hits POST /api/ds/query (the same API Grafana Explore uses). Use this
...                     if "proxy" fails (for example with TLS errors like
...                     "x509: certificate signed by unknown authority") while Grafana Explore can run
...                     the same query successfully.
...                 QUERY_TYPE selects "range" (default, returns a time series) or "instant" (single
...                 evaluation at PROM_END).
...                 PROMQL_QUERY (and the JSON body in ds_query mode) are passed via base64 + stdin so
...                 PromQL containing quotes, braces, or other shell-special characters is safe.
...                 If HEADERS is provided, '-K ./HEADERS' is appended for authentication.
...                 If POST_PROCESS is provided, the command output is piped to that command (e.g., jq).
Metadata            Author       stewartshea
Metadata            Display Name     Prometheus Query via Grafana (Relative Times)
Metadata            Supports     Grafana Prometheus Mimir Cortex Thanos

Library             BuiltIn
Library             RW.Core
Library             RW.platform
Library             OperatingSystem
Library             RW.CLI
Library             RW.Utils.Time

Suite Setup         Suite Initialization


*** Tasks ***
${TASK_TITLE}
    [Documentation]    Builds and runs a Prometheus-compatible query through Grafana, allowing
    ...                relative start/end times (like 30m, 2h, 2d). Uses either the datasource
    ...                proxy API (default) or Grafana's /api/ds/query API depending on QUERY_MODE.
    ...                Set QUERY_TYPE to "range" (default) or "instant".
    [Tags]            grafana    prometheus    mimir    cortex    cli    generic    access:read-only

    IF    '${QUERY_MODE}' == 'ds_query'
        # ds_query mode: POST /api/ds/query (Explore's API). Times are in milliseconds.
        ${start_ms}=    Convert Relative Time To Ms Epoch    ${PROM_START}
        ${end_ms}=      Convert Relative Time To Ms Epoch    ${PROM_END}
        ${interval_ms}=    Convert Duration To Ms    ${PROM_STEP}

        IF    '${QUERY_TYPE}' == 'instant'
            ${json_body}=    Evaluate    json.dumps({"queries":[{"refId":"A","expr":$PROMQL_QUERY,"queryType":"instant","instant":True,"datasource":{"type":"prometheus","uid":$DATASOURCE_UID}}],"from":str($start_ms),"to":str($end_ms)})    modules=json
        ELSE
            ${json_body}=    Evaluate    json.dumps({"queries":[{"refId":"A","expr":$PROMQL_QUERY,"queryType":"range","range":True,"datasource":{"type":"prometheus","uid":$DATASOURCE_UID},"intervalMs":int($interval_ms),"maxDataPoints":1000}],"from":str($start_ms),"to":str($end_ms)})    modules=json
        END

        ${b64_body}=     Evaluate    base64.b64encode(($json_body).encode()).decode()    modules=base64

        Set Suite Variable    ${GRAFANA_PROM_COMMAND}    echo ${b64_body} | base64 -d | curl -sS -X POST "${GRAFANA_URL}/api/ds/query?ds_type=prometheus" -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Datasource-Uid: ${DATASOURCE_UID}" -H "X-Plugin-Id: prometheus" --data-binary @-
    ELSE
        # proxy mode: prefer the UID-based path so DATASOURCE_ID is optional.
        IF    '${DATASOURCE_ID}' != ''
            ${PROXY_TARGET}=    Set Variable    ${DATASOURCE_ID}
        ELSE
            ${PROXY_TARGET}=    Set Variable    uid/${DATASOURCE_UID}
        END

        IF    '${QUERY_TYPE}' == 'instant'
            ${PROM_PATH}=    Set Variable    api/v1/query
        ELSE
            ${PROM_PATH}=    Set Variable    api/v1/query_range
        END

        # Pipe PromQL via base64 so it is shell-safe regardless of contents (quotes, braces, etc.).
        ${b64_query}=    Evaluate    base64.b64encode(($PROMQL_QUERY).encode()).decode()    modules=base64

        Set Suite Variable    ${GRAFANA_PROM_COMMAND}    echo ${b64_query} | base64 -d | curl -G "${GRAFANA_URL}/api/datasources/proxy/${PROXY_TARGET}/${PROM_PATH}" --data-urlencode "query@-"

        IF    '${QUERY_TYPE}' == 'instant'
            ${eval_epoch}=    Convert Relative Time To Sec Epoch    ${PROM_END}
            Set Suite Variable    ${GRAFANA_PROM_COMMAND}    ${GRAFANA_PROM_COMMAND} --data-urlencode "time=${eval_epoch}"
        ELSE
            ${start_epoch}=    Convert Relative Time To Sec Epoch    ${PROM_START}
            ${end_epoch}=      Convert Relative Time To Sec Epoch    ${PROM_END}
            Set Suite Variable    ${GRAFANA_PROM_COMMAND}    ${GRAFANA_PROM_COMMAND} --data-urlencode "start=${start_epoch}"
            Set Suite Variable    ${GRAFANA_PROM_COMMAND}    ${GRAFANA_PROM_COMMAND} --data-urlencode "end=${end_epoch}"
            Set Suite Variable    ${GRAFANA_PROM_COMMAND}    ${GRAFANA_PROM_COMMAND} --data-urlencode "step=${PROM_STEP}"
        END
    END

    IF    $HEADERS != ''
        Set Suite Variable    ${GRAFANA_PROM_COMMAND}    ${GRAFANA_PROM_COMMAND} -K ./HEADERS
    END

    IF    $POST_PROCESS != ''
        Set Suite Variable    ${GRAFANA_PROM_COMMAND}    ${GRAFANA_PROM_COMMAND} | ${POST_PROCESS}
    END

    ${rsp}=    RW.CLI.Run Cli
    ...        cmd=${GRAFANA_PROM_COMMAND}
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
    ...                 description=Which Grafana API to use. "proxy" (default) hits /api/datasources/proxy/{uid|id}/api/v1/query[_range]. "ds_query" hits POST /api/ds/query (the same API Grafana Explore uses). Use "ds_query" if "proxy" fails (e.g. with TLS errors like "x509: certificate signed by unknown authority") while Grafana Explore can run the same query.
    ...                 pattern=\w*
    ...                 default=proxy
    ...                 example=ds_query

    ${QUERY_TYPE}=       RW.Core.Import User Variable    QUERY_TYPE
    ...                 type=string
    ...                 description="range" (default) returns a time series between PROM_START and PROM_END at PROM_STEP resolution. "instant" returns a single evaluation at PROM_END (or "now" if empty).
    ...                 pattern=\w*
    ...                 default=range
    ...                 example=instant

    ${DATASOURCE_UID}=   RW.Core.Import User Variable    DATASOURCE_UID
    ...                 type=string
    ...                 description=UID of your Prometheus-compatible datasource in Grafana. Recommended primary identifier (easier to find than the numeric ID and stable across environments). Required.
    ...                 pattern=\w*
    ...                 example=metrics-mimir

    ${DATASOURCE_ID}=    RW.Core.Import User Variable    DATASOURCE_ID
    ...                 type=string
    ...                 description=Optional. Numeric ID of your datasource. Only used in QUERY_MODE=proxy. If empty, the UID-based proxy URL is used instead.
    ...                 pattern=\w*
    ...                 default=
    ...                 example=42

    ${PROMQL_QUERY}=     RW.Core.Import User Variable    PROMQL_QUERY
    ...                 type=string
    ...                 description=The PromQL expression to evaluate (e.g. up{job="api"}).
    ...                 pattern=\w*
    ...                 example=sum(rate(http_requests_total[5m])) by (status)

    ${PROM_START}=       RW.Core.Import User Variable    PROM_START
    ...                 type=string
    ...                 description=Optional. A relative time (30m, 2h, 2d) or an absolute Unix-seconds / RFC3339 timestamp. If relative, it is converted to "now - X" (seconds in proxy mode, milliseconds in ds_query mode). Used only by QUERY_TYPE=range.
    ...                 pattern=\w*
    ...                 default=1h
    ...                 example=2h

    ${PROM_END}=         RW.Core.Import User Variable    PROM_END
    ...                 type=string
    ...                 description=Optional. Same semantics as PROM_START. Empty means "now". For QUERY_TYPE=instant this is the evaluation time.
    ...                 pattern=\w*
    ...                 default=
    ...                 example=30m

    ${PROM_STEP}=        RW.Core.Import User Variable    PROM_STEP
    ...                 type=string
    ...                 description=Step / resolution for QUERY_TYPE=range (e.g. 15s, 30s, 1m). In proxy mode this is sent as-is to Prometheus. In ds_query mode it is converted to "intervalMs". Ignored for QUERY_TYPE=instant.
    ...                 pattern=\w*
    ...                 default=15s
    ...                 example=30s

    ${HEADERS}=          RW.Core.Import Secret    HEADERS
    ...                 type=string
    ...                 description=Optional file containing headers for cURL (e.g. auth token) in -K format.
    ...                 pattern=\w*
    ...                 example='header = "Authorization: Bearer GRAFANA_TOKEN"'

    ${POST_PROCESS}=     RW.Core.Import User Variable    POST_PROCESS
    ...                 type=string
    ...                 description=Optional command to parse/transform cURL output (e.g., jq).
    ...                 pattern=\w*
    ...                 example="jq -r '.data.result[].metric'"

    ${TASK_TITLE}=       RW.Core.Import User Variable    TASK_TITLE
    ...                 type=string
    ...                 description=The name of the task to run.
    ...                 pattern=\w*
    ...                 example="Fetch metrics from Prometheus via Grafana"
    ...                 default="Prometheus Query Through Grafana"

    Set Suite Variable    ${TASK_TITLE}    ${TASK_TITLE}
