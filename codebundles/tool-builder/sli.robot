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
    ...    python << 'EOF'
    ...    ${decode_op.stdout}
    ...    import json, os
    ...    resp = main()
    ...    path = os.path.join(os.environ["CODEBUNDLE_TEMP_DIR"], "metric_data.json")
    ...    f = open(path, "w", encoding="utf-8")
    ...    json.dump(resp, f)
    ...    f.close()
    ...    EOF
    ...    ELSE
    ...    Catenate    SEPARATOR=\n
    ...    bash << 'EOF'
    ...    ${decode_op.stdout}
    ...    METRIC_FILE="$CODEBUNDLE_TEMP_DIR/metric_data.json"
    ...    exec 3> "$METRIC_FILE"
    ...    main
    ...    exec 3>&-
    ...    EOF
    
    ${rsp}=    RW.CLI.Run Cli
    ...    cmd=${command}
    ...    env=${raw_env_vars}
    ...    &{secret_kwargs}
    
    ${metric_file}=    Set Variable    ${raw_env_vars["CODEBUNDLE_TEMP_DIR"]}/metric_data.json
    ${metric}=    Evaluate    json.load(open(r'''${metric_file}''')) if os.path.exists(r'''${metric_file}''') and os.path.getsize(r'''${metric_file}''') > 0 else 0    modules=json,os
    
    RW.Core.Push Metric    ${metric}    sub_name=metric
    RW.Core.Push Metric    ${metric}


*** Keywords ***
Suite Initialization
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

    # env vars management
    ${env_vars_json}=    RW.Core.Import User Variable    CONFIG_ENV_MAP
    ...    type=string
    ...    description="JSON string of environment variables to values"
    ...    example="{"env_name": "env_value"}"
    ${raw_env_vars}=    Evaluate    json.loads('${env_vars_json}' if '${env_vars_json}' not in ['null', '', 'None'] else '{}')    modules=json
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
    
    # secrets management
    ${secrets_json}=    RW.Core.Import User Variable    SECRET_ENV_MAP
    ...    type=string
    ...    description="JSON string of environment variables to secrets"
    ...    example="['env_name']"
    ${raw_secrets}=     Evaluate    json.loads('${secrets_json}' if '${secrets_json}' not in ['null', '', 'None'] else '[]')    modules=json

    ${secret_objs}=    Create Dictionary
    FOR    ${env_name}    IN    @{raw_secrets}
        ${secret_obj}=    RW.Core.Import Secret    ${env_name}
        Set To Dictionary    ${secret_objs}    ${env_name}    ${secret_obj}
    END
    
    Set Suite Variable    ${TASK_TITLE}    ${TASK_TITLE}
    Set Suite Variable    ${INTERPRETER}    ${INTERPRETER}
    Set Suite Variable    ${GEN_CMD}    ${GEN_CMD}
    Set Suite Variable    ${raw_env_vars}    ${raw_env_vars}
    Set Suite Variable    ${secret_objs}    ${secret_objs}