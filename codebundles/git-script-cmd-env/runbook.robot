*** Settings ***
Documentation       This taskset runs a user-provided script/command with up to 10 configurable environment variables from secrets.
...                 Supports SSH keys for git operations and provides maximum flexibility for script execution with secrets.
...                 Each environment variable is configured as an individual secret for maximum security and clarity.


Metadata            Author    stewartshea
Metadata            Display Name    Environment Script Command with Individual Secrets
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
    [Documentation]    Executes a user-provided script/command with up to 10 individually configured environment variables from secrets.
    ...                Special handling for SSH keys to enable private git repository access.
    [Tags]            git    bash    script    environment    secrets    generic

    # Build environment dictionary starting with PATH
    ${env_dict}=    Create Dictionary
    ${OS_PATH}=    Get Environment Variable    PATH
    Set To Dictionary    ${env_dict}    PATH=${OS_PATH}
    
    # Build export commands for environment variables (reading from secure files)
    ${env_exports}=    Set Variable    ""
    IF    $ENV_VAR_1_NAME != "" and $ENV_VAR_1_VALUE.value != ""
        ${env_exports}=    Set Variable    ${env_exports}export ${ENV_VAR_1_NAME}="$(cat ./${ENV_VAR_1_VALUE.key})" && 
    END
    IF    $ENV_VAR_2_NAME != "" and $ENV_VAR_2_VALUE.value != ""
        ${env_exports}=    Set Variable    ${env_exports}export ${ENV_VAR_2_NAME}="$(cat ./${ENV_VAR_2_VALUE.key})" && 
    END
    IF    $ENV_VAR_3_NAME != "" and $ENV_VAR_3_VALUE.value != ""
        ${env_exports}=    Set Variable    ${env_exports}export ${ENV_VAR_3_NAME}="$(cat ./${ENV_VAR_3_VALUE.key})" && 
    END
    IF    $ENV_VAR_4_NAME != "" and $ENV_VAR_4_VALUE.value != ""
        ${env_exports}=    Set Variable    ${env_exports}export ${ENV_VAR_4_NAME}="$(cat ./${ENV_VAR_4_VALUE.key})" && 
    END
    IF    $ENV_VAR_5_NAME != "" and $ENV_VAR_5_VALUE.value != ""
        ${env_exports}=    Set Variable    ${env_exports}export ${ENV_VAR_5_NAME}="$(cat ./${ENV_VAR_5_VALUE.key})" && 
    END
    IF    $ENV_VAR_6_NAME != "" and $ENV_VAR_6_VALUE.value != ""
        ${env_exports}=    Set Variable    ${env_exports}export ${ENV_VAR_6_NAME}="$(cat ./${ENV_VAR_6_VALUE.key})" && 
    END
    IF    $ENV_VAR_7_NAME != "" and $ENV_VAR_7_VALUE.value != ""
        ${env_exports}=    Set Variable    ${env_exports}export ${ENV_VAR_7_NAME}="$(cat ./${ENV_VAR_7_VALUE.key})" && 
    END
    IF    $ENV_VAR_8_NAME != "" and $ENV_VAR_8_VALUE.value != ""
        ${env_exports}=    Set Variable    ${env_exports}export ${ENV_VAR_8_NAME}="$(cat ./${ENV_VAR_8_VALUE.key})" && 
    END
    IF    $ENV_VAR_9_NAME != "" and $ENV_VAR_9_VALUE.value != ""
        ${env_exports}=    Set Variable    ${env_exports}export ${ENV_VAR_9_NAME}="$(cat ./${ENV_VAR_9_VALUE.key})" && 
    END
    IF    $ENV_VAR_10_NAME != "" and $ENV_VAR_10_VALUE.value != ""
        ${env_exports}=    Set Variable    ${env_exports}export ${ENV_VAR_10_NAME}="$(cat ./${ENV_VAR_10_VALUE.key})" && 
    END
    
    # Setup KUBECONFIG if provided
    IF    $kubeconfig != ''
        Set To Dictionary    ${env_dict}    KUBECONFIG=./${kubeconfig.key}
    END
    
    # Setup SSH if provided (using secure file approach)
    ${ssh_setup}=    Set Variable    ""
    ${ssh_setup}=    Set Variable    chmod 600 ./${SSH_PRIVATE_KEY.key} && export GIT_SSH_COMMAND='ssh -i ./${SSH_PRIVATE_KEY.key} -o IdentitiesOnly=yes' && ls -lha &&
    
    # Build command parts explicitly to avoid concatenation issues
    IF   ${env_exports} == ""
        ${full_command}=    Set Variable    ${ssh_setup}${SCRIPT_COMMAND}
    ELSE
        ${full_command}=    Set Variable    ${ssh_setup}${env_exports}${SCRIPT_COMMAND}
    END
    

    ${rsp}=    RW.CLI.Run Cli
    ...        cmd=${full_command}
    ...        env=${env_dict}
    ...        secret_file__kubeconfig=${kubeconfig}
    ...        secret_file__SSH_PRIVATE_KEY=${SSH_PRIVATE_KEY}
    ...        secret_file__ENV_VAR_1_VALUE=${ENV_VAR_1_VALUE}
    ...        secret_file__ENV_VAR_2_VALUE=${ENV_VAR_2_VALUE}
    ...        secret_file__ENV_VAR_3_VALUE=${ENV_VAR_3_VALUE}
    ...        secret_file__ENV_VAR_4_VALUE=${ENV_VAR_4_VALUE}
    ...        secret_file__ENV_VAR_5_VALUE=${ENV_VAR_5_VALUE}
    ...        secret_file__ENV_VAR_6_VALUE=${ENV_VAR_6_VALUE}
    ...        secret_file__ENV_VAR_7_VALUE=${ENV_VAR_7_VALUE}
    ...        secret_file__ENV_VAR_8_VALUE=${ENV_VAR_8_VALUE}
    ...        secret_file__ENV_VAR_9_VALUE=${ENV_VAR_9_VALUE}
    ...        secret_file__ENV_VAR_10_VALUE=${ENV_VAR_10_VALUE}
    ...        timeout_seconds=1800

    ${history}=    RW.CLI.Pop Shell History

    RW.Core.Add Pre To Report    Command stdout: ${rsp.stdout}
    RW.Core.Add Pre To Report    Command stderr: ${rsp.stderr}
    RW.Core.Add Pre To Report    Commands Used: ${history}
    
    IF    ${rsp.returncode} != 0
        RW.Core.Add Issue
        ...    severity=2
        ...    expected=Script command should execute successfully
        ...    actual=Script command failed with return code ${rsp.returncode}
        ...    title=Script Execution Failed
        ...    reproduce_hint=Check the script command and environment variables. Verify SSH key and repository access if using Git operations.
        ...    details=Command: ${SCRIPT_COMMAND}${\n}Return Code: ${rsp.returncode}${\n}Stdout: ${rsp.stdout}${\n}Stderr: ${rsp.stderr}
        ...    next_steps=1. Verify the SCRIPT_COMMAND syntax is correct\n2. Check that all required environment variables are set with valid values\n3. If using SSH, ensure SSH_PRIVATE_KEY is valid and has access to the repository\n4. If using HTTPS, verify GIT_USERNAME and GIT_TOKEN are correct\n5. Test the script command locally to isolate the issue\n6. Check repository URL and access permissions
    END


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
    
    # Import up to 10 environment variable pairs
    ${ENV_VAR_1_NAME}=    RW.Core.Import User Variable    ENV_VAR_1_NAME
    ...    type=string
    ...    description=Name of the first environment variable (optional)
    ...    pattern=.*
    ...    example=
    ...    default=""
    
    ${ENV_VAR_1_VALUE}=    RW.Core.Import Secret
    ...    ENV_VAR_1_VALUE
    ...    type=string
    ...    description=Value of the first environment variable (optional)
    ...    pattern=.*
    ...    example=
    ...    optional=True
    
    ${ENV_VAR_2_NAME}=    RW.Core.Import User Variable    ENV_VAR_2_NAME
    ...    type=string
    ...    description=Name of the second environment variable (optional)
    ...    pattern=.*
    ...    example=
    ...    default=""
    
    ${ENV_VAR_2_VALUE}=    RW.Core.Import Secret
    ...    ENV_VAR_2_VALUE
    ...    type=string
    ...    description=Value of the second environment variable (optional)
    ...    pattern=.*
    ...    example=
    ...    optional=True
    
    ${ENV_VAR_3_NAME}=    RW.Core.Import User Variable    ENV_VAR_3_NAME
    ...    type=string
    ...    description=Name of the third environment variable (optional)
    ...    pattern=.*
    ...    example=
    ...    default=""
    
    ${ENV_VAR_3_VALUE}=    RW.Core.Import Secret
    ...    ENV_VAR_3_VALUE
    ...    type=string
    ...    description=Value of the third environment variable (optional)
    ...    pattern=.*
    ...    example=
    ...    optional=True
    
    ${ENV_VAR_4_NAME}=    RW.Core.Import User Variable    ENV_VAR_4_NAME
    ...    type=string
    ...    description=Name of the fourth environment variable (optional)
    ...    pattern=.*
    ...    default=""
    
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
    ...    default=""
    
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
    ...    default=""
    
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
    ...    default=""
    
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
    ...    default=""
    
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
    ...    default=""
    
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
    ...    default=""
    
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
    ...    description=The script or command to execute with full environment context
    ...    pattern=.*
    ...    example=
    
    ${TASK_TITLE}=    RW.Core.Import User Variable    TASK_TITLE
    ...    type=string
    ...    description=The name of the task to run. This helps identify the task in RunWhen Digital Assistants.
    ...    pattern=.*
    ...    example=
    ...    default=Execute Script with Environment Variables
    
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