*** Settings ***
Documentation       Runs an ad-hoc user-provided command, and if the provided command outputs a non-empty string to stdout then an issue is generated with a configurable title and content.
...                 User commands should filter expected/healthy content (eg: with grep) and only output found errors.
Metadata            Author    jon-funk
Metadata            Display Name    GCP CLI Command with Issue

Library             BuiltIn
Library             RW.Core
Library             RW.platform
Library             OperatingSystem
Library             RW.CLI
Library             RW.DynamicIssues

Suite Setup         Suite Initialization


*** Tasks ***
${TASK_TITLE}
    [Documentation]    Runs a user provided gcloud command and adds the output to the report.
    ...                Supports multiple dynamic issue generation methods: stdout-based, file-based (issues.json/report.txt), and JSON query-based.
    [Tags]    stdout    gcloud    generic
    ${rsp}=    RW.CLI.Run Cli
    ...    cmd=gcloud auth activate-service-account --key-file=$GOOGLE_APPLICATION_CREDENTIALS && ${GCLOUD_COMMAND}
    ...    env=${env}
    ...    secret_file__gcp_credentials_json=${gcp_credentials_json}
    ...    timeout_seconds=1200
    ${history}=    RW.CLI.Pop Shell History
    ${STDOUT}=    Set Variable    ${rsp.stdout}
    
    # Check for report.txt and add to report if present
    ${report_file}=    Set Variable    ${CODEBUNDLE_TEMP_DIR}/report.txt
    ${report_exists}=    Run Keyword And Return Status    File Should Exist    ${report_file}
    IF    ${report_exists}
        ${report_content}=    Get File    ${report_file}
        RW.Core.Add Pre To Report    ${report_content}
    END
    
    # Method 1: File-based dynamic issue generation (issues.json)
    ${file_issues_created}=    RW.DynamicIssues.Process File Based Issues    ${CODEBUNDLE_TEMP_DIR}
    
    # Method 2: JSON query-based dynamic issue generation
    ${json_issues_created}=    Set Variable    0
    IF    """${ISSUE_JSON_QUERY_ENABLED}""" == "true" and """${rsp.stdout}""" != ""
        ${json_issues_created}=    RW.DynamicIssues.Process Json Query Issues
        ...    ${rsp.stdout}
        ...    ${ISSUE_JSON_TRIGGER_KEY}
        ...    ${ISSUE_JSON_TRIGGER_VALUE}
        ...    ${ISSUE_JSON_ISSUES_KEY}
    END
    
    # Method 3: Traditional stdout-based issue generation (if enabled)
    ${total_dynamic_issues}=    Evaluate    ${file_issues_created} + ${json_issues_created}
    IF    """${rsp.stdout}""" != "" and """${STDOUT_ISSUE_ENABLED}""" == "true"
        RW.Core.Add Issue
        ...    title=${ISSUE_TITLE}
        ...    severity=${ISSUE_SEVERITY}
        ...    expected=The command should produce no output, indicating no errors were found.
        ...    actual=Found stdout output produced by the configured command, indicating errors were found.
        ...    reproduce_hint=Run ${GCLOUD_COMMAND} to fetch the data that triggered this issue.
        ...    next_steps=${ISSUE_NEXT_STEPS}
        ...    details=${ISSUE_DETAILS}
        RW.Core.Add Pre To Report    Command stdout: ${rsp.stdout}
        RW.Core.Add Pre To Report    Command stderr: ${rsp.stderr}
        RW.Core.Add Pre To Report    Commands Used: ${history}
    ELSE IF    """${rsp.stdout}""" == ""
        RW.Core.Add Pre To Report    No output was returned from the command, indicating no errors were found.
        RW.Core.Add Pre To Report    Command stdout: ${rsp.stdout}
        RW.Core.Add Pre To Report    Command stderr: ${rsp.stderr}
        RW.Core.Add Pre To Report    Commands Used: ${history}
    ELSE
        # Stdout exists but traditional issue generation is disabled, just add to report
        RW.Core.Add Pre To Report    Command stdout: ${rsp.stdout}
        RW.Core.Add Pre To Report    Command stderr: ${rsp.stderr}
        RW.Core.Add Pre To Report    Commands Used: ${history}
    END
    
    # Add summary of dynamic issues
    IF    ${total_dynamic_issues} > 0
        RW.Core.Add Pre To Report    Dynamic Issue Generation Summary: Created ${file_issues_created} issues from files and ${json_issues_created} issues from JSON queries.
    END


*** Keywords ***
Suite Initialization
    ${gcp_credentials_json}=    RW.Core.Import Secret    gcp_credentials_json
    ...    type=string
    ...    description=GCP service account json used to authenticate with GCP APIs.
    ...    pattern=\w*
    ...    example={"type": "service_account","project_id":"myproject-ID", ... super secret stuff ...}
    ${TASK_TITLE}=    RW.Core.Import User Variable    TASK_TITLE
    ...    type=string
    ...    description=The name of the task to run. This is useful for helping find this generic task with RunWhen Digital Assistants. 
    ...    pattern=\w*
    ...    example="Count the number of pods in the namespace"
    ${ISSUE_TITLE}=    RW.Core.Import User Variable    ISSUE_TITLE
    ...    type=string
    ...    description=The title of the issue to raise if the command returns a non-empty string.
    ...    pattern=\w*
    ...    example="Found errors in the command output"
    ...    default="Found errors in the command output"
    ${ISSUE_NEXT_STEPS}=    RW.Core.Import User Variable    ISSUE_NEXT_STEPS
    ...    type=string
    ...    description=The next steps to take if the command returns a non-empty string.
    ...    pattern=\w*
    ...    example="Review the command output and take appropriate action."
    ...    default="Review the command output and take appropriate action."
    ${ISSUE_DETAILS}=    RW.Core.Import User Variable    ISSUE_DETAILS
    ...    type=string
    ...    description=The details of the issue to raise if the command returns a non-empty string.
    ...    pattern=\w*
    ...    example="The command returned the following output, indicating errors: \${STDOUT}"
    ...    default="The command returned the following output, indicating errors: \${STDOUT}"
    ${ISSUE_SEVERITY}=    RW.Core.Import User Variable    ISSUE_SEVERITY
    ...    type=string
    ...    description=An integer severity rating for the issue if raised, where 1 is critical, and 4 is informational.
    ...    pattern=\w*
    ...    example=3
    ...    default=3
    ${GCLOUD_COMMAND}=    RW.Core.Import User Variable    GCLOUD_COMMAND
    ...    type=string
    ...    description=The gcloud command to run. Make sure to pass along details such as the GCP Project ID. 
    ...    pattern=\w*
    ...    example="gcloud projects list"
    ${STDOUT_ISSUE_ENABLED}=    RW.Core.Import User Variable    STDOUT_ISSUE_ENABLED
    ...    type=string
    ...    description=Enable traditional stdout-based issue generation (true/false). When true, non-empty stdout creates an issue.
    ...    pattern=\w*
    ...    example=true
    ...    default=true
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
    Set Suite Variable    ${gcp_credentials_json}    ${gcp_credentials_json}
    Set Suite Variable
    ...    ${env}
    ...    {"GOOGLE_APPLICATION_CREDENTIALS":"./${gcp_credentials_json.key}","PATH":"$PATH:${OS_PATH}"}