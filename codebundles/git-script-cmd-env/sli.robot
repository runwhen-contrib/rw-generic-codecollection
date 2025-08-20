*** Settings ***
Documentation       This SLI runs a user-provided script/command with up to 10 configurable environment variables from secrets and pushes the result as a metric.
...                 Each environment variable is configured as an individual secret for maximum security and clarity.
...                 The supplied command must result in a distinct single metric.

Metadata            Author    stewartshea
Metadata            Display Name    Environment Script Command Metric with Individual Secrets
Metadata            Supports    Git    Bash    Scripts    Environment

Library             BuiltIn
Library             RW.Core
Library             RW.platform
Library             OperatingSystem
Library             RW.CLI
Library             Collections

Suite Setup         Suite Initialization


*** Tasks ***
${TASK_TITLE}
    [Documentation]    Executes a user-provided script/command with up to 10 individually configured environment variables from secrets and pushes the stdout as a metric.
    ...                Special handling for SSH keys to enable private git repository access.
    [Tags]            git    bash    script    environment    secrets    metric    sli    generic

    # Build environment dictionary starting with PATH
    ${env_dict}=    Create Dictionary
    ${OS_PATH}=    Get Environment Variable    PATH
    Set To Dictionary    ${env_dict}    PATH=${OS_PATH}
    
    # Add each configured environment variable if provided
    IF    $ENV_VAR_1_NAME != "" and $ENV_VAR_1_VALUE.value != ""
        Set To Dictionary    ${env_dict}    ${ENV_VAR_1_NAME}=${ENV_VAR_1_VALUE.value}
    END
    
    IF    $ENV_VAR_2_NAME != "" and $ENV_VAR_2_VALUE.value != ""
        Set To Dictionary    ${env_dict}    ${ENV_VAR_2_NAME}=${ENV_VAR_2_VALUE.value}
    END
    
    IF    $ENV_VAR_3_NAME != "" and $ENV_VAR_3_VALUE.value != ""
        Set To Dictionary    ${env_dict}    ${ENV_VAR_3_NAME}=${ENV_VAR_3_VALUE.value}
    END
    
    IF    $ENV_VAR_4_NAME != "" and $ENV_VAR_4_VALUE.value != ""
        Set To Dictionary    ${env_dict}    ${ENV_VAR_4_NAME}=${ENV_VAR_4_VALUE.value}
    END
    
    IF    $ENV_VAR_5_NAME != "" and $ENV_VAR_5_VALUE.value != ""
        Set To Dictionary    ${env_dict}    ${ENV_VAR_5_NAME}=${ENV_VAR_5_VALUE.value}
    END
    
    IF    $ENV_VAR_6_NAME != "" and $ENV_VAR_6_VALUE.value != ""
        Set To Dictionary    ${env_dict}    ${ENV_VAR_6_NAME}=${ENV_VAR_6_VALUE.value}
    END
    
    IF    $ENV_VAR_7_NAME != "" and $ENV_VAR_7_VALUE.value != ""
        Set To Dictionary    ${env_dict}    ${ENV_VAR_7_NAME}=${ENV_VAR_7_VALUE.value}
    END
    
    IF    $ENV_VAR_8_NAME != "" and $ENV_VAR_8_VALUE.value != ""
        Set To Dictionary    ${env_dict}    ${ENV_VAR_8_NAME}=${ENV_VAR_8_VALUE.value}
    END
    
    IF    $ENV_VAR_9_NAME != "" and $ENV_VAR_9_VALUE.value != ""
        Set To Dictionary    ${env_dict}    ${ENV_VAR_9_NAME}=${ENV_VAR_9_VALUE.value}
    END
    
    IF    $ENV_VAR_10_NAME != "" and $ENV_VAR_10_VALUE.value != ""
        Set To Dictionary    ${env_dict}    ${ENV_VAR_10_NAME}=${ENV_VAR_10_VALUE.value}
    END
    
    # Setup KUBECONFIG if provided
    IF    $kubeconfig != ''
        Set To Dictionary    ${env_dict}    KUBECONFIG=./${kubeconfig.key}
    END
    
    # Setup SSH if provided
    IF    $SSH_PRIVATE_KEY.value != ""
        Set To Dictionary    ${env_dict}    SSH_PRIVATE_KEY=${SSH_PRIVATE_KEY.value}
    END
    
    # Add SSH setup prefix if SSH key is provided
    ${ssh_setup}=    Set Variable    ${EMPTY}
    IF    $SSH_PRIVATE_KEY.value != ""
        ${ssh_setup}=    Set Variable    echo "$SSH_PRIVATE_KEY" > private_key_file && chmod 600 private_key_file && export GIT_SSH_COMMAND='ssh -i private_key_file -o IdentitiesOnly=yes' && 
    END
    
    ${full_command}=    Set Variable    ${ssh_setup}${SCRIPT_COMMAND}
    
    ${rsp}=    RW.CLI.Run Cli
    ...        cmd=${full_command}
    ...        env=${env_dict}
    ...        secret_file__kubeconfig=${kubeconfig}
    ...        timeout_seconds=1800
    
    # Push 1 for success (healthy), 0 for failure (unhealthy)
    ${metric_value}=    Set Variable If    ${rsp.returncode} == 0    1    0
    
    IF    ${rsp.returncode} != 0
        RW.Core.Add Issue
        ...    severity=2
        ...    expected=Script command should execute successfully
        ...    actual=Script command failed with return code ${rsp.returncode}
        ...    title=Script Execution Failed
        ...    reproduce_hint=Check the script command and environment variables. Verify SSH key and repository access if using Git operations.
        ...    details=Command: ${SCRIPT_COMMAND}${\n}Return Code: ${rsp.returncode}${\n}Stdout: ${rsp.stdout}${\n}Stderr: ${rsp.stderr}
    END
    
    RW.Core.Push Metric    ${metric_value}


*** Keywords ***
Suite Initialization
    # Import optional SSH private key for git operations
    ${SSH_PRIVATE_KEY}=    RW.Core.Import Secret
    ...    SSH_PRIVATE_KEY
    ...    type=string
    ...    description=SSH private key for git repository access (optional)
    ...    pattern=.*
    ...    example=
    ...    optional=True
    
    # Import optional kubeconfig for Kubernetes operations
    ${kubeconfig}=    RW.Core.Import Secret
    ...    kubeconfig
    ...    type=string
    ...    description=Kubernetes config file for cluster access (optional)
    ...    pattern=.*
    ...    example=
    ...    optional=True
    
    # Import up to 10 environment variable pairs (only showing first 3 for brevity)
    ${ENV_VAR_1_NAME}=    RW.Core.Import User Variable    ENV_VAR_1_NAME
    ...    type=string
    ...    description=Name of the first environment variable (optional)
    ...    pattern=.*
    ...    example=DATABASE_URL
    ...    default=''
    
    ${ENV_VAR_1_VALUE}=    RW.Core.Import Secret
    ...    ENV_VAR_1_VALUE
    ...    type=string
    ...    description=Value of the first environment variable (optional)
    ...    pattern=.*
    ...    example=postgres://user:pass@host:5432/db
    ...    optional=True
    
    ${ENV_VAR_2_NAME}=    RW.Core.Import User Variable    ENV_VAR_2_NAME
    ...    type=string
    ...    description=Name of the second environment variable (optional)
    ...    pattern=.*
    ...    example=API_KEY
    ...    default=''
    
    ${ENV_VAR_2_VALUE}=    RW.Core.Import Secret
    ...    ENV_VAR_2_VALUE
    ...    type=string
    ...    description=Value of the second environment variable (optional)
    ...    pattern=.*
    ...    example=sk-1234567890abcdef
    ...    optional=True
    
    ${ENV_VAR_3_NAME}=    RW.Core.Import User Variable    ENV_VAR_3_NAME
    ...    type=string
    ...    description=Name of the third environment variable (optional)
    ...    pattern=.*
    ...    example=GIT_TOKEN
    ...    default=''
    
    ${ENV_VAR_3_VALUE}=    RW.Core.Import Secret
    ...    ENV_VAR_3_VALUE
    ...    type=string
    ...    description=Value of the third environment variable (optional)
    ...    pattern=.*
    ...    example=ghp_xxxxxxxxxxxxxxxxxxxx
    ...    optional=True
    
    # Import remaining environment variables (4-10) with minimal descriptions
    ${ENV_VAR_4_NAME}=    RW.Core.Import User Variable    ENV_VAR_4_NAME
    ...    type=string
    ...    description=Name of the fourth environment variable (optional)
    ...    pattern=.*
    ...    example=
    ...    default=''
    ${ENV_VAR_4_VALUE}=    RW.Core.Import Secret
    ...    ENV_VAR_4_VALUE
    ...    type=string
    ...    description=Value of the fourth environment variable (optional)
    ...    pattern=.*
    ...    example=
    ...    optional=True
    ${ENV_VAR_5_NAME}=    RW.Core.Import User Variable    ENV_VAR_5_NAME
    ...    type=string
    ...    description=Name of the fifth environment variable (optional)
    ...    pattern=.*
    ...    example=
    ...    default=''
    ${ENV_VAR_5_VALUE}=    RW.Core.Import Secret
    ...    ENV_VAR_5_VALUE
    ...    type=string
    ...    description=Value of the fifth environment variable (optional)
    ...    pattern=.*
    ...    example=
    ...    optional=True
    ${ENV_VAR_6_NAME}=    RW.Core.Import User Variable    ENV_VAR_6_NAME
    ...    type=string
    ...    description=Name of the sixth environment variable (optional)
    ...    pattern=.*
    ...    example=
    ...    default=''
    ${ENV_VAR_6_VALUE}=    RW.Core.Import Secret
    ...    ENV_VAR_6_VALUE
    ...    type=string
    ...    description=Value of the sixth environment variable (optional)
    ...    pattern=.*
    ...    example=
    ...    optional=True
    ${ENV_VAR_7_NAME}=    RW.Core.Import User Variable    ENV_VAR_7_NAME
    ...    type=string
    ...    description=Name of the seventh environment variable (optional)
    ...    pattern=.*
    ...    example=
    ...    default=''
    ${ENV_VAR_7_VALUE}=    RW.Core.Import Secret
    ...    ENV_VAR_7_VALUE
    ...    type=string
    ...    description=Value of the seventh environment variable (optional)
    ...    pattern=.*
    ...    example=
    ...    optional=True
    ${ENV_VAR_8_NAME}=    RW.Core.Import User Variable    ENV_VAR_8_NAME
    ...    type=string
    ...    description=Name of the eighth environment variable (optional)
    ...    pattern=.*
    ...    example=
    ...    default=''
    ${ENV_VAR_8_VALUE}=    RW.Core.Import Secret
    ...    ENV_VAR_8_VALUE
    ...    type=string
    ...    description=Value of the eighth environment variable (optional)
    ...    pattern=.*
    ...    example=
    ...    optional=True
    ${ENV_VAR_9_NAME}=    RW.Core.Import User Variable    ENV_VAR_9_NAME
    ...    type=string
    ...    description=Name of the ninth environment variable (optional)
    ...    pattern=.*
    ...    example=
    ...    default=''
    ${ENV_VAR_9_VALUE}=    RW.Core.Import Secret
    ...    ENV_VAR_9_VALUE
    ...    type=string
    ...    description=Value of the ninth environment variable (optional)
    ...    pattern=.*
    ...    example=
    ...    optional=True
    ${ENV_VAR_10_NAME}=    RW.Core.Import User Variable    ENV_VAR_10_NAME
    ...    type=string
    ...    description=Name of the tenth environment variable (optional)
    ...    pattern=.*
    ...    example=
    ...    default=''
    ${ENV_VAR_10_VALUE}=    RW.Core.Import Secret
    ...    ENV_VAR_10_VALUE
    ...    type=string
    ...    description=Value of the tenth environment variable (optional)
    ...    pattern=.*
    ...    example=
    ...    optional=True
    
    # Import required script command
    ${SCRIPT_COMMAND}=    RW.Core.Import User Variable    SCRIPT_COMMAND
    ...    type=string
    ...    description=The script or command to execute that returns a single metric value
    ...    pattern=.*
    ...    example=git clone https://$GIT_TOKEN@github.com/private/repo.git /tmp/repo && /tmp/repo/scripts/health-check.sh | jq -r '.metric'
    
    ${TASK_TITLE}=    RW.Core.Import User Variable    TASK_TITLE
    ...    type=string
    ...    description=The name of the task to run. This helps identify the task in RunWhen Digital Assistants.
    ...    pattern=.*
    ...    example=Check Application Health from Private Repository
    ...    default=Execute Script Metric with Environment Variables
    
    # Set all suite variables
    Set Suite Variable    ${SSH_PRIVATE_KEY}
    Set Suite Variable    ${kubeconfig}
    Set Suite Variable    ${ENV_VAR_1_NAME}
    Set Suite Variable    ${ENV_VAR_1_VALUE}
    Set Suite Variable    ${ENV_VAR_2_NAME}
    Set Suite Variable    ${ENV_VAR_2_VALUE}
    Set Suite Variable    ${ENV_VAR_3_NAME}
    Set Suite Variable    ${ENV_VAR_3_VALUE}
    Set Suite Variable    ${ENV_VAR_4_NAME}
    Set Suite Variable    ${ENV_VAR_4_VALUE}
    Set Suite Variable    ${ENV_VAR_5_NAME}
    Set Suite Variable    ${ENV_VAR_5_VALUE}
    Set Suite Variable    ${ENV_VAR_6_NAME}
    Set Suite Variable    ${ENV_VAR_6_VALUE}
    Set Suite Variable    ${ENV_VAR_7_NAME}
    Set Suite Variable    ${ENV_VAR_7_VALUE}
    Set Suite Variable    ${ENV_VAR_8_NAME}
    Set Suite Variable    ${ENV_VAR_8_VALUE}
    Set Suite Variable    ${ENV_VAR_9_NAME}
    Set Suite Variable    ${ENV_VAR_9_VALUE}
    Set Suite Variable    ${ENV_VAR_10_NAME}
    Set Suite Variable    ${ENV_VAR_10_VALUE}
    Set Suite Variable    ${SCRIPT_COMMAND}
    Set Suite Variable    ${TASK_TITLE} 