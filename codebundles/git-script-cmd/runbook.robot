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
    
    # Add all imported secrets as environment variables
    IF    $SSH_PRIVATE_KEY != ''
        Set To Dictionary    ${env_dict}    SSH_PRIVATE_KEY=${SSH_PRIVATE_KEY}
    END
    
    IF    $GIT_USERNAME != ''
        Set To Dictionary    ${env_dict}    GIT_USERNAME=${GIT_USERNAME}
    END
    
    IF    $GIT_TOKEN != ''
        Set To Dictionary    ${env_dict}    GIT_TOKEN=${GIT_TOKEN}
    END
    
    IF    $ADDITIONAL_SECRETS != ''
        # Parse additional secrets JSON and add to environment
        ${additional_env}=    Evaluate    json.loads('''${ADDITIONAL_SECRETS}''')    json
        FOR    ${key}    ${value}    IN    &{additional_env}
            Set To Dictionary    ${env_dict}    ${key}=${value}
        END
    END
    
    # Setup SSH if SSH_PRIVATE_KEY is provided
    ${pre_commands}=    Set Variable    ${EMPTY}
    IF    $SSH_PRIVATE_KEY != ''
        ${pre_commands}=    Set Variable    chmod 600 ./${SSH_PRIVATE_KEY.key} && ssh-keyscan -t rsa github.com > ./.ssh_known_hosts 2>/dev/null && export GIT_SSH_COMMAND="ssh -i ./${SSH_PRIVATE_KEY.key} -o UserKnownHostsFile=./.ssh_known_hosts -o StrictHostKeyChecking=no -o IdentitiesOnly=yes" && 
    END
    
    # Execute the script with full environment
    ${full_command}=    Set Variable    ${pre_commands}${SCRIPT_COMMAND}
    
    ${rsp}=    RW.CLI.Run Cli
    ...        cmd=${full_command}
    ...        env=${env_dict}
    ...        secret_file__SSH_PRIVATE_KEY=${SSH_PRIVATE_KEY}
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
    ...    default=${EMPTY}
    
    # Import optional git HTTPS credentials
    ${GIT_USERNAME}=    RW.Core.Import Secret    GIT_USERNAME
    ...    type=string
    ...    description=Git username for HTTPS authentication (optional)
    ...    pattern=\w*
    ...    example=myusername
    ...    default=${EMPTY}
    
    ${GIT_TOKEN}=    RW.Core.Import Secret    GIT_TOKEN
    ...    type=string
    ...    description=Git token/password for HTTPS authentication (optional)
    ...    pattern=.*
    ...    example=ghp_xxxxxxxxxxxxxxxxxxxx
    ...    default=${EMPTY}
    
    # Import additional secrets as JSON
    ${ADDITIONAL_SECRETS}=    RW.Core.Import Secret    ADDITIONAL_SECRETS
    ...    type=string
    ...    description=Additional secrets as JSON object to be loaded as environment variables (optional)
    ...    pattern=.*
    ...    example={"DATABASE_URL":"postgres://...", "API_KEY":"secret123", "SLACK_TOKEN":"xoxb-..."}
    ...    default=${EMPTY}
    
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
    Set Suite Variable    ${SCRIPT_COMMAND}
    Set Suite Variable    ${TASK_TITLE} 