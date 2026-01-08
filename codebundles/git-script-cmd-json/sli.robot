*** Settings ***
Documentation       This SLI runs a user-provided script/command with flexible environment variable support and pushes the result as a metric.
...                 Supports SSH keys, git credentials, and arbitrary environment variables from secrets.
...                 The supplied command must result in a distinct single metric.

Metadata            Author    stewartshea
Metadata            Display Name    Git Script Command Metric with Secrets
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
    [Documentation]    Executes a user-provided script/command with all configured secrets loaded as environment variables and pushes the stdout as a metric.
    ...                Special handling for SSH keys and git credentials to enable private repository access.
    [Tags]            git    bash    script    secrets    metric    sli    generic

    # Build environment dictionary with all secrets
    ${env_dict}=    Create Dictionary
    
    # Add standard environment variables
    ${OS_PATH}=    Get Environment Variable    PATH
    Set To Dictionary    ${env_dict}    PATH=${OS_PATH}
    
    # Build export commands for all secrets (reading from secure files)
    ${env_exports}=    Set Variable    ${EMPTY}
    
    # Add Git credentials as exports (only if they have values)
    TRY
        IF    $GIT_USERNAME.value != ""
            ${env_exports}=    Set Variable    ${env_exports}export GIT_USERNAME="$(cat ./${GIT_USERNAME.key})" && 
        END
    EXCEPT
        Log    GIT_USERNAME not provided, skipping    DEBUG
    END
    TRY
        IF    $GIT_TOKEN.value != ""
            ${env_exports}=    Set Variable    ${env_exports}export GIT_TOKEN="$(cat ./${GIT_TOKEN.key})" && 
        END
    EXCEPT
        Log    GIT_TOKEN not provided, skipping    DEBUG
    END
    
    # Add additional secrets from JSON (only if JSON is provided)
    TRY
        IF    $ADDITIONAL_SECRETS.value != ""
            ${additional_env}=    Evaluate    json.loads('''${ADDITIONAL_SECRETS.value}''')    json
            FOR    ${key}    ${value}    IN    &{additional_env}
                ${env_exports}=    Set Variable    ${env_exports}export ${key}="${value}" && 
            END
        END
    EXCEPT
        Log    ADDITIONAL_SECRETS not provided, skipping    DEBUG
    END
    
    # Setup KUBECONFIG if provided
    TRY
        Set To Dictionary    ${env_dict}    KUBECONFIG=./${kubeconfig.key}
    EXCEPT
        Log    kubeconfig not provided, skipping    DEBUG
    END
    
    # Setup SSH if provided (reading from secure file)
    ${ssh_setup}=    Set Variable    ${EMPTY}
    TRY
        IF    $SSH_PRIVATE_KEY.value != ""
            ${ssh_setup}=    Set Variable    chmod 600 ./${SSH_PRIVATE_KEY.key} && export GIT_SSH_COMMAND='ssh -i ./${SSH_PRIVATE_KEY.key} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new' &&
        END
    EXCEPT
        Log    SSH_PRIVATE_KEY not provided, skipping    DEBUG
    END
    
    # Build command parts explicitly to avoid concatenation issues
    IF   $env_exports == ""
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
    ...        timeout_seconds=${TIMEOUT_SECONDS}
    
    # Determine metric value based on METRIC_MODE
    IF    "${METRIC_MODE}" == "output"
        # Parse metric from stdout (strip whitespace)
        ${metric_value}=    Strip String    ${rsp.stdout}
        # Validate that output is a number
        TRY
            ${metric_value}=    Convert To Number    ${metric_value}
        EXCEPT
            RW.Core.Add Issue
            ...    severity=2
            ...    expected=Script output should be a numeric value when METRIC_MODE=output
            ...    actual=Script output is not a valid number: ${metric_value}
            ...    title=Invalid Metric Output
            ...    reproduce_hint=When METRIC_MODE=output, the script stdout must output a single numeric value.
            ...    details=Command: ${SCRIPT_COMMAND}${\n}Return Code: ${rsp.returncode}${\n}Stdout: ${rsp.stdout}${\n}Stderr: ${rsp.stderr}
            ...    next_steps=1. Ensure your script outputs only a numeric value to stdout\n2. Use tools like 'jq' or 'grep' to extract numeric values from complex output\n3. Consider using METRIC_MODE=returncode if you cannot output a numeric value
            ${metric_value}=    Set Variable    0
        END
        # Still add issue if command failed, but use the output value
        IF    ${rsp.returncode} != 0
            RW.Core.Add Issue
            ...    severity=2
            ...    expected=Script command should execute successfully
            ...    actual=Script command failed with return code ${rsp.returncode}
            ...    title=Script Execution Failed
            ...    reproduce_hint=Check the script command and environment variables. Verify SSH key and repository access if using Git operations.
            ...    details=Command: ${SCRIPT_COMMAND}${\n}Return Code: ${rsp.returncode}${\n}Stdout: ${rsp.stdout}${\n}Stderr: ${rsp.stderr}
            ...    next_steps=1. Verify the SCRIPT_COMMAND syntax is correct\n2. Check GIT_USERNAME and GIT_TOKEN are set correctly for HTTPS authentication\n3. If using SSH, ensure SSH_PRIVATE_KEY is valid and has repository access\n4. Validate ADDITIONAL_SECRETS JSON format if using additional environment variables\n5. Test the script command locally to isolate the issue\n6. Check repository URL and access permissions
        END
    ELSE
        # Default: Push 1 for success (healthy), 0 for failure (unhealthy)
        ${metric_value}=    Set Variable If    ${rsp.returncode} == 0    1    0
        
        IF    ${rsp.returncode} != 0
            RW.Core.Add Issue
            ...    severity=2
            ...    expected=Script command should execute successfully
            ...    actual=Script command failed with return code ${rsp.returncode}
            ...    title=Script Execution Failed
            ...    reproduce_hint=Check the script command and environment variables. Verify SSH key and repository access if using Git operations.
            ...    details=Command: ${SCRIPT_COMMAND}${\n}Return Code: ${rsp.returncode}${\n}Stdout: ${rsp.stdout}${\n}Stderr: ${rsp.stderr}
            ...    next_steps=1. Verify the SCRIPT_COMMAND syntax is correct\n2. Check GIT_USERNAME and GIT_TOKEN are set correctly for HTTPS authentication\n3. If using SSH, ensure SSH_PRIVATE_KEY is valid and has repository access\n4. Validate ADDITIONAL_SECRETS JSON format if using additional environment variables\n5. Test the script command locally to isolate the issue\n6. Check repository URL and access permissions
        END
    END
    RW.Core.Push Metric    ${metric_value}

*** Keywords ***
Suite Initialization
    # Import optional SSH private key for git operations
    ${SSH_PRIVATE_KEY}=    RW.Core.Import Secret    SSH_PRIVATE_KEY
    ...    type=string
    ...    description=SSH private key for git repository access (optional)
    ...    pattern=.*
    ...    example=-----BEGIN OPENSSH PRIVATE KEY-----\nkey_content_here\n-----END OPENSSH PRIVATE KEY-----
    ...    optional=True
    
    # Import optional git HTTPS credentials
    ${GIT_USERNAME}=    RW.Core.Import Secret    GIT_USERNAME
    ...    type=string
    ...    description=Git username for HTTPS authentication (optional)
    ...    pattern=.*
    ...    example=myusername
    ...    optional=True
    
    ${GIT_TOKEN}=    RW.Core.Import Secret    GIT_TOKEN
    ...    type=string
    ...    description=Git token/password for HTTPS authentication (optional)
    ...    pattern=.*
    ...    example=ghp_xxxxxxxxxxxxxxxxxxxx
    ...    optional=True
    
    # Import additional secrets as JSON
    ${ADDITIONAL_SECRETS}=    RW.Core.Import Secret    ADDITIONAL_SECRETS
    ...    type=string
    ...    description=Additional secrets as JSON object to be loaded as environment variables (optional)
    ...    pattern=.*
    ...    example={"DATABASE_URL":"postgres://...", "API_KEY":"secret123", "SLACK_TOKEN":"xoxb-..."}
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
    ...    description=The script or command to execute that returns a single metric value
    ...    pattern=.*
    ...    example=git clone git@github.com:private/repo.git /tmp/repo && /tmp/repo/scripts/health-check.sh | jq -r '.metric'
    
    ${TASK_TITLE}=    RW.Core.Import User Variable    TASK_TITLE
    ...    type=string
    ...    description=The name of the task to run. This helps identify the task in RunWhen Digital Assistants.
    ...    pattern=.*
    ...    example=Check Application Health from Private Repository
    ...    default=Execute Script Metric with Secrets

    ${TIMEOUT_SECONDS}=    RW.Core.Import User Variable    TIMEOUT_SECONDS
    ...    type=string
    ...    description=The amount of seconds before the command is killed. 
    ...    pattern=\w*
    ...    example=120
    ...    default=120

    # Set suite variables
    Set Suite Variable    ${SSH_PRIVATE_KEY}
    Set Suite Variable    ${GIT_USERNAME}
    Set Suite Variable    ${GIT_TOKEN}
    Set Suite Variable    ${ADDITIONAL_SECRETS}
    Set Suite Variable    ${kubeconfig}
    Set Suite Variable    ${SCRIPT_COMMAND}
    Set Suite Variable    ${TASK_TITLE}
    Set Suite Variable    ${TIMEOUT_SECONDS}
