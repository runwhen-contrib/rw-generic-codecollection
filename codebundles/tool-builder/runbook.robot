*** Settings ***
Documentation       A CodeBundle that supports the Tool Builder in the RunWhen Platform for bash and python scripts. 
Metadata            Author    theyashl
Metadata            Display Name    Tool Builder (BASH/PYTHON)
Metadata            Supports    bash    python    RunWhen    Generic

Library             BuiltIn
Library             RW.Core
Library             RW.platform
Library             OperatingSystem
Library             RW.CLI
Library             Collections

Suite Setup         Suite Initialization


*** Tasks ***
${TASK_TITLE}
    [Documentation]    Executes a user provided bash or python script. 
    [Tags]    bash    cli    generic
    
    ${secret_kwargs}=    Create Dictionary

    FOR    ${key}    ${secret}    IN    &{secret_objs}
        Set To Dictionary    ${secret_kwargs}    secret_file__${key}=${secret}
    END
    
    ${decode_op}=    RW.CLI.Run Cli
    ...    cmd=echo '${GEN_CMD}' | base64 -d

    ${command}=    Run Keyword If    '${INTERPRETER}' == 'python'
    ...    Catenate    SEPARATOR=\n
    ...    python << 'RW_GENERIC_EOF'
    ...    ${decode_op.stdout}
    ...    import json, os
    ...    resp = main()
    ...    path = os.path.join(os.environ["CODEBUNDLE_TEMP_DIR"], "run_output.json")
    ...    f = open(path, "w", encoding="utf-8")
    ...    json.dump(resp, f)
    ...    f.close()
    ...    RW_GENERIC_EOF
    ...    ELSE
    ...    Catenate    SEPARATOR=\n
    ...    bash << 'RW_GENERIC_EOF'
    ...    ${decode_op.stdout}
    ...    ISSUES_FILE="$CODEBUNDLE_TEMP_DIR/run_output.json"
    ...    exec 3> "$ISSUES_FILE"
    ...    main
    ...    exec 3>&-
    ...    RW_GENERIC_EOF
    
    ${rsp}=    RW.CLI.Run Cli
    ...    cmd=${command}
    ...    env=${raw_env_vars}
    ...    &{secret_kwargs}
    ...    timeout_seconds=${TIMEOUT_SECONDS}

    ${history}=    RW.CLI.Pop Shell History
    
    # Surface the script's stdout/stderr in the report up front, so it is visible
    # whether the task passes OR fails below.
    RW.Core.Add Pre To Report    Command stdout: ${rsp.stdout}
    RW.Core.Add Pre To Report    Command stderr: ${rsp.stderr}

    ${run_output_file}=    Set Variable    ${raw_env_vars["CODEBUNDLE_TEMP_DIR"]}/run_output.json
    TRY
        ${run_output}=    Evaluate    json.load(open(r'''${run_output_file}''')) if os.path.exists(r'''${run_output_file}''') and os.path.getsize(r'''${run_output_file}''') > 0 else []    modules=json,os
    EXCEPT    AS    ${output_err}
        IF    $RUN_TYPE == 'sli'
            Log    Script metric output was not valid JSON; defaulting to 0: ${output_err}    WARN
            ${run_output}=    Set Variable    ${0}
        ELSE
            # Fundamental malformation — fail LOUDLY (visible run status) with an actionable message.
            Fail    Task script output could not be read as JSON. The script must write a JSON list of issue objects (use [] for no issues). Parser error: ${output_err}
        END
    END

    IF    $RUN_TYPE == 'sli'
        RW.Core.Add Pre To Report    Reported Metric: ${run_output}
    ELSE
        # Contract: the script returns a JSON LIST of issue objects (use [] for no issues).
        IF    not isinstance($run_output, list)
            ${out_type}=    Evaluate    type($run_output).__name__
            Fail    Task script did not return a JSON list of issues (got a ${out_type}). Return a list of issue objects; use [] for no issues.
        END
        # Add the valid issues; collect any malformed ones and fail at the end (so the
        # good findings are still recorded, but the author is told what to fix).
        ${malformed}=    Create List
        FOR    ${issue}    IN    @{run_output}
            ${issue_title}=    Evaluate    $issue.get('issue title') if isinstance($issue, dict) else None
            IF    $issue_title is None
                Append To List    ${malformed}    ${issue}
                CONTINUE
            END
            RW.Core.Add Issue
            ...    title=${issue_title}
            ...    severity=${issue.get('issue severity', 4)}
            ...    expected=The script should produce no issues, indicating no errors were found.
            ...    actual=Found issues output produced by the provided script, indicating errors were found.
            ...    reproduce_hint=look at the SLX description for more details.
            ...    next_steps=${issue.get('issue next steps', '')}
            ...    details=${issue.get('issue description', '')}
            ...    observed_at=${issue.get('issue observed at', None)}
        END
        ${malformed_count}=    Get Length    ${malformed}
        IF    ${malformed_count} > 0
            Fail    Task script produced ${malformed_count} malformed issue(s); each issue must be a JSON object with at least an 'issue title'. First offending item: ${malformed}[0]
        END
    END


*** Keywords ***
Suite Initialization
    ${RUN_TYPE}=    RW.Core.Import User Variable    RUN_TYPE
    ...    type=string
    ...    description="Type of run: runbook or sli"
    ...    default=runbook
    ${INTERPRETER}=    RW.Core.Import User Variable    INTERPRETER
    ...    type=string
    ...    description="Shell: bash or python"
    ...    default=bash
    ${GEN_CMD}=    RW.Core.Import User Variable    GEN_CMD
    ...    type=string
    ...    description=base64 encoded command to run
    ...    pattern=\w*
    ...    example="ZWNobyAnSGVsbG8gV29ybGQn"
    ${TASK_TITLE}=    RW.Core.Import User Variable    TASK_TITLE
    ...    type=string
    ...    description=A useful task title. This is useful for helping find this generic task with RunWhen Assistants. 
    ...    pattern=\w*
    ...    example="Run a bash command"
    ${TIMEOUT_SECONDS}=    RW.Core.Import User Variable    TIMEOUT_SECONDS
    ...    type=string
    ...    description=The amount of seconds before the command is killed. 
    ...    pattern=\w*
    ...    example=300
    ...    default=300
    # env vars management
    ${env_vars_json}=    RW.Core.Import User Variable    CONFIG_ENV_MAP
    ...    type=string
    ...    description="JSON string of environment variables to values"
    ...    example="{"env_name": "env_value"}"
    ${raw_env_vars}=    Evaluate    json.loads($env_vars_json) if $env_vars_json not in [None, 'null', '', 'None'] else {}    modules=json
    ${OS_PATH}=    Get Environment Variable    PATH
    Run Keyword If    'PATH' in ${raw_env_vars}
    ...    Set To Dictionary
    ...    ${raw_env_vars}
    ...    PATH=${raw_env_vars['PATH']}:${OS_PATH}
    Run Keyword If    'PATH' not in ${raw_env_vars}
    ...    Set To Dictionary
    ...    ${raw_env_vars}
    ...    PATH=${OS_PATH}
    Set To Dictionary    ${raw_env_vars}
    ...    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
    ...    REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
    # Warn about runtime var names bash cannot reference (letters/digits/underscore only).
    ${nonshell_keys}=    Evaluate    [k for k in $raw_env_vars if not __import__('re').match(r'^[A-Za-z_][A-Za-z0-9_]*$', str(k))]
    IF    $nonshell_keys and '${INTERPRETER}' == 'bash'
        Log    Runtime var names not usable as bash variables (rename to letters/digits/underscore): ${nonshell_keys}    WARN
    END

    # secrets management
    ${secrets_json}=    RW.Core.Import User Variable    SECRET_ENV_MAP
    ...    type=string
    ...    description="JSON string of environment variables to secrets"
    ...    example="['env_name']"
    ${raw_secrets}=     Evaluate    json.loads($secrets_json) if $secrets_json not in [None, 'null', '', 'None'] else []    modules=json

    ${secret_objs}=    Create Dictionary
    FOR    ${env_name}    IN    @{raw_secrets}
        ${secret_obj}=    RW.Core.Import Secret    ${env_name}
        Set To Dictionary    ${secret_objs}    ${env_name}    ${secret_obj}
    END
    
    Set Suite Variable    ${RUN_TYPE}    ${RUN_TYPE}
    Set Suite Variable    ${TASK_TITLE}    ${TASK_TITLE}
    Set Suite Variable    ${INTERPRETER}    ${INTERPRETER}
    Set Suite Variable    ${GEN_CMD}    ${GEN_CMD}
    Set Suite Variable    ${raw_env_vars}    ${raw_env_vars}
    Set Suite Variable    ${secret_objs}    ${secret_objs}
    Set Suite Variable    ${TIMEOUT_SECONDS}
