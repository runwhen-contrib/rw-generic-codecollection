*** Settings ***
Documentation       This taskset runs a user-provided script/command with flexible environment variable support, designed for git operations and script execution with secrets.
...                 Supports SSH keys, git credentials, and arbitrary environment variables from secrets.
...                 All secrets are loaded as environment variables, with special handling for SSH keys and git credentials.

Metadata            Author    stewartshea
Metadata            Display Name    Git Script Command with Secrets
Metadata            Supports    Git    Bash    Scripts

Library             BuiltIn
Library             RW.Core
Library             RW.platform
Library             OperatingSystem
Library             RW.CLI
Library             Collections

Suite Setup         Suite Initialization


*** Tasks ***
${TASK_TITLE}
    [Documentation]    Executes a user-provided script/command with all configured secrets loaded as environment variables.
    ...                Special handling for SSH keys and git credentials to enable private repository access.
    [Tags]            git    bash    script    secrets    generic

    # Build environment dictionary with all secrets
    ${env_dict}=    Create Dictionary
    
    # Add standard environment variables
    ${OS_PATH}=    Get Environment Variable    PATH
    Set To Dictionary    ${env_dict}    PATH=${OS_PATH}
    
    # Build export commands for all secrets (reading from secure files)
    ${env_exports}=    Set Variable    ""
    
    # Add Git credentials as exports (only if they have values)
    IF    $GIT_USERNAME.value != ""
        ${env_exports}=    Set Variable    ${env_exports}export GIT_USERNAME="$(cat ./${GIT_USERNAME.key})" && 
    END
    IF    $GIT_TOKEN.value != ""
        ${env_exports}=    Set Variable    ${env_exports}export GIT_TOKEN="$(cat ./${GIT_TOKEN.key})" && 
    END
    
    # Add additional secrets from JSON (only if JSON is provided)
    IF    $ADDITIONAL_SECRETS.value != ""
        ${additional_env}=    Evaluate    json.loads(open('./${ADDITIONAL_SECRETS.key}').read())    json
        FOR    ${key}    ${value}    IN    &{additional_env}
            ${env_exports}=    Set Variable    ${env_exports}export ${key}="${value}" && 
        END
    END
    
    # Setup KUBECONFIG if provided
    IF    $kubeconfig != ''
        Set To Dictionary    ${env_dict}    KUBECONFIG=./${kubeconfig.key}
    END
    
    # Setup SSH if provided (reading from secure file)
    ${ssh_setup}=    Set Variable    ""
    IF    $SSH_PRIVATE_KEY.value != ""
        ${ssh_setup}=    Set Variable    chmod 600 ./${SSH_PRIVATE_KEY.key} && export GIT_SSH_COMMAND='ssh -i ./${SSH_PRIVATE_KEY.key} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new' &&
    END
    
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
    ...        secret_file__GIT_USERNAME=${GIT_USERNAME}
    ...        secret_file__GIT_TOKEN=${GIT_TOKEN}
    ...        secret_file__ADDITIONAL_SECRETS=${ADDITIONAL_SECRETS}
    ...        timeout_seconds=1800

    ${history}=    RW.CLI.Pop Shell History

    RW.Core.Add Pre To Report    Command stdout: ${rsp.stdout}
    RW.Core.Add Pre To Report    Command stderr: ${rsp.stderr}
    RW.Core.Add Pre To Report    Commands Used: ${history}


*** Keywords ***
Suite Initialization
    # Import optional SSH private key for git operations
    ${SSH_PRIVATE_KEY}=    RW.Core.Import Secret    SSH_PRIVATE_KEY
    ...    type=string
    ...    description=SSH private key for git repository access (optional)
    ...    pattern=.*
    ...    example=-----BEGIN OPENSSH PRIVATE KEY-----\nkey_content_here\n-----END OPENSSH PRIVATE KEY-----
    ...    default=""
    ...    optional=True
    
    # Import optional git HTTPS credentials
    ${GIT_USERNAME}=    RW.Core.Import Secret    GIT_USERNAME
    ...    type=string
    ...    description=Git username for HTTPS authentication (optional)
    ...    pattern=.*
    ...    example=myusername
    ...    default=""
    ...    optional=True
    
    ${GIT_TOKEN}=    RW.Core.Import Secret    GIT_TOKEN
    ...    type=string
    ...    description=Git token/password for HTTPS authentication (optional)
    ...    pattern=.*
    ...    example=ghp_xxxxxxxxxxxxxxxxxxxx
    ...    default=""
    ...    optional=True
    
    # Import additional secrets as JSON
    ${ADDITIONAL_SECRETS}=    RW.Core.Import Secret    ADDITIONAL_SECRETS
    ...    type=string
    ...    description=Additional secrets as JSON object to be loaded as environment variables (optional)
    ...    pattern=.*
    ...    example={"DATABASE_URL":"postgres://...", "API_KEY":"secret123", "SLACK_TOKEN":"xoxb-..."}
    ...    default=""
    ...    optional=True
    
    # Import optional kubeconfig for Kubernetes operations
    ${kubeconfig}=    RW.Core.Import Secret
    ...    kubeconfig
    ...    type=string
    ...    description=Kubernetes config file for cluster access (optional)
    ...    pattern=.*
    ...    example=
    ...    optional=True
    
    # Import required script command
    ${SCRIPT_COMMAND}=    RW.Core.Import User Variable    SCRIPT_COMMAND
    ...    type=string
    ...    description=The script or command to execute with full environment context
    ...    pattern=.*
    ...    example=git clone git@github.com:private/repo.git /tmp/repo && bash /tmp/repo/scripts/deploy.sh
    
    ${TASK_TITLE}=    RW.Core.Import User Variable    TASK_TITLE
    ...    type=string
    ...    description=The name of the task to run. This helps identify the task in RunWhen Digital Assistants.
    ...    pattern=.*
    ...    example=Deploy Application from Private Repository
    ...    default=Execute Script with Secrets
    
    # Set suite variables
    Set Suite Variable    ${SSH_PRIVATE_KEY}
    Set Suite Variable    ${GIT_USERNAME}
    Set Suite Variable    ${GIT_TOKEN}
    Set Suite Variable    ${ADDITIONAL_SECRETS}
    Set Suite Variable    ${kubeconfig}
    Set Suite Variable    ${SCRIPT_COMMAND}
    Set Suite Variable    ${TASK_TITLE} 