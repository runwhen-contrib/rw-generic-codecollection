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
Library             String
Library             RW.CLI
Library             Collections
Library             RW.DynamicIssues

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

    ${history}=    RW.CLI.Pop Shell History
    
    # Check for report.txt files (searches recursively) and add to report if present
    ${find_result}=    RW.CLI.Run Cli
    ...    cmd=find ${CODEBUNDLE_TEMP_DIR} -name "report.txt" -type f 2>/dev/null || true
    IF    """${find_result.stdout}""" != ""
        ${report_files}=    Split String    ${find_result.stdout}    \n
        FOR    ${report_file}    IN    @{report_files}
            ${report_file_trimmed}=    Strip String    ${report_file}
            ${report_exists}=    Run Keyword And Return Status    File Should Exist    ${report_file_trimmed}
            IF    ${report_exists}
                ${report_content}=    Get File    ${report_file_trimmed}
                ${relative_path}=    Replace String    ${report_file_trimmed}    ${CODEBUNDLE_TEMP_DIR}/    ${EMPTY}
                RW.Core.Add Pre To Report    === Report from ${relative_path} ===\n${report_content}
            END
        END
    END
    
    # Method 1: File-based dynamic issue generation (issues.json, searches recursively)
    ${file_issues_created}=    RW.DynamicIssues.Process File Based Issues    ${CODEBUNDLE_TEMP_DIR}
    
    # Method 2: JSON query-based dynamic issue generation (if enabled and configured)
    ${json_issues_created}=    Set Variable    0
    IF    """${ISSUE_JSON_QUERY_ENABLED}""" == "true" and """${rsp.stdout}""" != ""
        ${json_issues_created}=    RW.DynamicIssues.Process Json Query Issues
        ...    ${rsp.stdout}
        ...    ${ISSUE_JSON_TRIGGER_KEY}
        ...    ${ISSUE_JSON_TRIGGER_VALUE}
        ...    ${ISSUE_JSON_ISSUES_KEY}
    END

    RW.Core.Add Pre To Report    Command stdout: ${rsp.stdout}
    RW.Core.Add Pre To Report    Command stderr: ${rsp.stderr}
    RW.Core.Add Pre To Report    Commands Used: ${history}
    
    # Add summary of dynamic issues
    ${total_dynamic_issues}=    Evaluate    ${file_issues_created} + ${json_issues_created}
    IF    ${total_dynamic_issues} > 0
        RW.Core.Add Pre To Report    Dynamic Issue Generation Summary: Created ${file_issues_created} issues from files and ${json_issues_created} issues from JSON queries.
    END


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
    ...    description=The script or command to execute with full environment context
    ...    pattern=.*
    ...    example=git clone git@github.com:private/repo.git /tmp/repo && bash /tmp/repo/scripts/deploy.sh
    
    ${TASK_TITLE}=    RW.Core.Import User Variable    TASK_TITLE
    ...    type=string
    ...    description=The name of the task to run. This helps identify the task in RunWhen Digital Assistants.
    ...    pattern=.*
    ...    example=Deploy Application from Private Repository
    ...    default=Execute Script with Secrets

    ${TIMEOUT_SECONDS}=    RW.Core.Import User Variable    TIMEOUT_SECONDS
    ...    type=string
    ...    description=The amount of seconds before the command is killed. 
    ...    pattern=\w*
    ...    example=1800
    ...    default=1800
    
    # Dynamic Issue Generation Configuration
    ${ISSUE_JSON_QUERY_ENABLED}=    RW.Core.Import User Variable    ISSUE_JSON_QUERY_ENABLED
    ...    type=string
    ...    description=Enable JSON query-based issue generation (true/false). Searches stdout for JSON patterns to create issues.
    ...    pattern=\w*
    ...    example=true
    ...    default=false
    ${ISSUE_JSON_TRIGGER_KEY}=    RW.Core.Import User Variable    ISSUE_JSON_TRIGGER_KEY
    ...    type=string
    ...    description=JSON key to check for triggering issue generation (e.g., "issuesIdentified", "storeIssues", "hasErrors").
    ...    pattern=.*
    ...    example=issuesIdentified
    ...    default=issuesIdentified
    ${ISSUE_JSON_TRIGGER_VALUE}=    RW.Core.Import User Variable    ISSUE_JSON_TRIGGER_VALUE
    ...    type=string
    ...    description=Value of trigger key that indicates issues should be created (e.g., "true", "yes", or "1").
    ...    pattern=.*
    ...    example=true
    ...    default=true
    ${ISSUE_JSON_ISSUES_KEY}=    RW.Core.Import User Variable    ISSUE_JSON_ISSUES_KEY
    ...    type=string
    ...    description=JSON key containing the list of issues to create (e.g., "issues", "problems", "errors").
    ...    pattern=.*
    ...    example=issues
    ...    default=issues
    
    ${CODEBUNDLE_TEMP_DIR}=    Get Environment Variable    CODEBUNDLE_TEMP_DIR

    # Set suite variables
    Set Suite Variable    ${CODEBUNDLE_TEMP_DIR}
    Set Suite Variable    ${SSH_PRIVATE_KEY}
    Set Suite Variable    ${GIT_USERNAME}
    Set Suite Variable    ${GIT_TOKEN}
    Set Suite Variable    ${ADDITIONAL_SECRETS}
    Set Suite Variable    ${kubeconfig}
    Set Suite Variable    ${SCRIPT_COMMAND}
    Set Suite Variable    ${TASK_TITLE} 
    Set Suite Variable    ${TIMEOUT_SECONDS}
    Set Suite Variable    ${ISSUE_JSON_QUERY_ENABLED}
    Set Suite Variable    ${ISSUE_JSON_TRIGGER_KEY}
    Set Suite Variable    ${ISSUE_JSON_TRIGGER_VALUE}
    Set Suite Variable    ${ISSUE_JSON_ISSUES_KEY}
