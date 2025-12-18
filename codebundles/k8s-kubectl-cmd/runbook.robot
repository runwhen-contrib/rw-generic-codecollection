*** Settings ***
Documentation       This taskset runs a user provided kubectl command and adds the output to the report. Command line tools like jq are available.
Metadata            Author    stewartshea
Metadata            Display Name    Kubernetes CLI Command
Metadata            Supports    K8s    Kubernetes

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
    [Documentation]    Runs a user provided kubectl command and adds the output to the report.
    ...                Supports dynamic issue generation via issues.json, report.txt, and JSON query patterns.
    [Tags]    kubectl    cli    generic
    ${rsp}=    RW.CLI.Run Cli
    ...    cmd=${KUBECTL_COMMAND}
    ...    env={"KUBECONFIG":"./${kubeconfig.key}"}
    ...    secret_file__kubeconfig=${kubeconfig}
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
    ${kubeconfig}=    RW.Core.Import Secret
    ...    kubeconfig
    ...    type=string
    ...    description=The kubernetes kubeconfig yaml containing connection configuration used to connect to cluster(s).
    ...    pattern=\w*
    ...    example=For examples, start here https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/
    ${KUBECTL_COMMAND}=    RW.Core.Import User Variable    KUBECTL_COMMAND
    ...    type=string
    ...    description=The kubectl command to run. Can use tools like jq.
    ...    pattern=\w*
    ...    example="kubectl describe pods -n online-boutique"
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
    
    ${CODEBUNDLE_TEMP_DIR}=    Get Environment Variable    CODEBUNDLE_TEMP_DIR
    Set Suite Variable    ${CODEBUNDLE_TEMP_DIR}