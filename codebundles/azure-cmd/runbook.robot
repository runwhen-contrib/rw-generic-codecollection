*** Settings ***
Documentation       This taskset runs a user provided azure command and adds the output to the report. Command line tools like jq are available.

Metadata            Author    jon-funk
Metadata            Display Name    Azure CLI Command
Metadata            Supports    Azure

Library             BuiltIn
Library             RW.Core
Library             RW.platform
Library             OperatingSystem
Library             String
Library             RW.CLI
Library             RW.DynamicIssues

Suite Setup         Suite Initialization


*** Tasks ***
${TASK_TITLE}
    [Documentation]    Runs a user provided azure cli command and adds the output to the report.
    ...                Supports dynamic issue generation via issues.json, report.txt, and JSON query patterns.
    [Tags]    azure    cli    generic
    ${rsp}=    RW.CLI.Run Cli
    ...    cmd=${AZURE_COMMAND}
    ...    env=${env}
    ...    timeout_seconds=${TIMEOUT_SECONDS}
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
    
    # Dynamic issue generation from issues.json (searches recursively)
    ${file_issues_created}=    RW.DynamicIssues.Process File Based Issues    ${CODEBUNDLE_TEMP_DIR}
    
    # Dynamic issue generation from JSON query (if enabled)
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
    
    # Add summary if any dynamic issues were created
    ${total_issues}=    Evaluate    ${file_issues_created} + ${json_issues_created}
    IF    ${total_issues} > 0
        RW.Core.Add Pre To Report    Created ${file_issues_created} issues from files and ${json_issues_created} issues from JSON queries.
    END


*** Keywords ***
Suite Initialization
    ${azure_credentials}=    RW.Core.Import Secret
    ...    azure_credentials
    ...    type=string
    ...    description=The secret containing AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_CLIENT_SECRET, AZURE_SUBSCRIPTION_ID
    ...    pattern=\w*
    ${AZURE_COMMAND}=    RW.Core.Import User Variable    AZURE_COMMAND
    ...    type=string
    ...    description=The az cli command to run. Can use tools like jq.
    ...    pattern=\w*
    ...    example=az monitor metrics list --resource myapp --resource-group myrg --resource-type Microsoft.Web/sites --metric "HealthCheckStatus" --interval 5m | -r '.value[].timeseries[].data[].average'
    ${TASK_TITLE}=    RW.Core.Import User Variable    TASK_TITLE
    ...    type=string
    ...    description=The name of the task to run. This is useful for helping find this generic task with RunWhen Digital Assistants. 
    ...    pattern=\w*
    ...    example="Count the number of pods in the namespace"
    ${TIMEOUT_SECONDS}=    RW.Core.Import User Variable    TIMEOUT_SECONDS
    ...    type=string
    ...    description=The amount of seconds before the command is killed. 
    ...    pattern=\w*
    ...    example=300
    ...    default=300
    
    # Dynamic Issue Generation Configuration
    ${ISSUE_JSON_QUERY_ENABLED}=    RW.Core.Import User Variable    ISSUE_JSON_QUERY_ENABLED
    ...    type=string
    ...    description=Enable JSON query-based issue generation (true/false). When enabled, searches stdout for JSON patterns.
    ...    pattern=\w*
    ...    example=false
    ...    default=false
    ${ISSUE_JSON_TRIGGER_KEY}=    RW.Core.Import User Variable    ISSUE_JSON_TRIGGER_KEY
    ...    type=string
    ...    description=JSON key to check for triggering issue generation (e.g., "issuesIdentified" or "storeIssues").
    ...    pattern=.*
    ...    example=issuesIdentified
    ...    default=issuesIdentified
    ${ISSUE_JSON_TRIGGER_VALUE}=    RW.Core.Import User Variable    ISSUE_JSON_TRIGGER_VALUE
    ...    type=string
    ...    description=Value of trigger key that indicates issues should be created (e.g., "true" or "1").
    ...    pattern=.*
    ...    example=true
    ...    default=true
    ${ISSUE_JSON_ISSUES_KEY}=    RW.Core.Import User Variable    ISSUE_JSON_ISSUES_KEY
    ...    type=string
    ...    description=JSON key containing the list of issues to create (e.g., "issues" or "problems").
    ...    pattern=.*
    ...    example=issues
    ...    default=issues
    
    ${OS_PATH}=    Get Environment Variable    PATH
    ${CODEBUNDLE_TEMP_DIR}=    Get Environment Variable    CODEBUNDLE_TEMP_DIR
    Set Suite Variable    ${CODEBUNDLE_TEMP_DIR}
    Set Suite Variable
    ...    ${env}
    ...    {"HOME":"${CODEBUNDLE_TEMP_DIR}","PATH":"$PATH:${OS_PATH}","TERM":"dumb","NO_COLOR":"1"}
    ${powershell_auth}=     RW.CLI.Run Cli
    ...    cmd=pwsh -NoLogo -NoProfile -Command "Install-Module Az.Accounts -Scope CurrentUser -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null; Import-Module Az.Accounts; \\$token = (az account get-access-token --output json | ConvertFrom-Json).accessToken; \\$account = az account show --output json | ConvertFrom-Json; Connect-AzAccount -AccessToken \\$token -AccountId \\$account.user.name -TenantId \\$account.tenantId -SubscriptionId \\$account.id | Out-Null"
    ...    timeout_seconds=30
    ...    env=${env}
    ...    include_in_history=false