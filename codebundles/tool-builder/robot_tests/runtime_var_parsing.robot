*** Settings ***
Documentation       Regression: a custom task whose runtime var value contains double quotes
...                 (e.g. a PromQL QUERY) must parse on the runner. The Suite Initialization
...                 used ``json.loads('${var}' ...)`` -- a single-quoted, non-raw literal --
...                 so Robot spliced the JSON text into the Python source and Python un-escaped
...                 the JSON's \\" back to " and corrupted it before json.loads ran. The fix
...                 passes the variable as a Python object via ``$var``. These cases use a
...                 synthetic multi-var payload (no real hostnames/identifiers) so genuine
...                 Robot reproduces the failure, then proves the fix. Needs only BuiltIn +
...                 Collections (no RW.Core); excluded from the SLX index.

Library             Collections


*** Variables ***
# A synthetic PromQL query whose value contains double quotes -- the shape that broke the
# runner. No real hostnames/identifiers.
${SAMPLE_QUERY}         sum by (path) (http_requests_total{service=~"example-service", pod=~".*", status!~"5.."})
${SAMPLE_BASE_URL}      https://api.example.com
${SAMPLE_CLIENT_ID}     example-client
${SAMPLE_SCOPES}        example-scope
${SAMPLE_AUTHORITY}     https://auth.example.com


*** Test Cases ***
Query With Embedded Quotes Round Trips (Fixed Form)
    [Documentation]    A multi-var CONFIG_ENV_MAP with a quote-bearing value must survive
    ...    the fixed $var object-form Evaluate and recover QUERY byte-for-byte.
    ${env_vars_json}=    Build Sample Config Env Map Json
    # --- exact fixed codebundle expression ---
    ${raw_env_vars}=    Evaluate    json.loads($env_vars_json) if $env_vars_json not in [None, 'null', '', 'None'] else {}    modules=json
    Should Be Equal    ${raw_env_vars}[QUERY]        ${SAMPLE_QUERY}
    Should Be Equal    ${raw_env_vars}[BASE_URL]     ${SAMPLE_BASE_URL}
    Should Be Equal    ${raw_env_vars}[AUTHORITY]    ${SAMPLE_AUTHORITY}

Old Single Quoted Form Fails On Embedded Quotes (Documents The Bug)
    [Documentation]    Proves the pre-fix single-quoted, non-raw form crashes on a
    ...    quote-bearing value with the reported JSONDecodeError, under genuine Robot.
    ${env_vars_json}=    Build Sample Config Env Map Json
    Run Keyword And Expect Error
    ...    *JSONDecodeError*Expecting ',' delimiter*
    ...    Evaluate    json.loads('${env_vars_json}' if '${env_vars_json}' not in ['null', '', 'None'] else '{}')    modules=json

Empty And Sentinel Env Vars Default To Empty Dict (Fixed Form)
    FOR    ${sentinel}    IN    ${EMPTY}    null    None
        ${raw_env_vars}=    Evaluate    json.loads($sentinel) if $sentinel not in [None, 'null', '', 'None'] else {}    modules=json
        Should Be Empty    ${raw_env_vars}
    END

Secret Names Json Round Trips (Fixed Form)
    ${secrets}=    Create List    GITHUB_TOKEN    DB_PASSWORD
    ${secrets_json}=    Evaluate    json.dumps($secrets)    modules=json
    ${raw_secrets}=    Evaluate    json.loads($secrets_json) if $secrets_json not in [None, 'null', '', 'None'] else []    modules=json
    Lists Should Be Equal    ${raw_secrets}    ${secrets}


*** Keywords ***
Build Sample Config Env Map Json
    [Documentation]    Serialize a synthetic multi-var payload with Python json.dumps,
    ...    mirroring how papi (explorer.py) emits CONFIG_ENV_MAP for passed runtime vars.
    ${config}=    Create Dictionary
    ...    BASE_URL=${SAMPLE_BASE_URL}
    ...    CLIENT_ID=${SAMPLE_CLIENT_ID}
    ...    SCOPES=${SAMPLE_SCOPES}
    ...    AUTHORITY=${SAMPLE_AUTHORITY}
    ...    QUERY=${SAMPLE_QUERY}
    ${env_vars_json}=    Evaluate    json.dumps($config)    modules=json
    RETURN    ${env_vars_json}
