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

Suite Setup         Suite Initialization


*** Tasks ***
Run User Provided GCloud Command in `${GCLOUD_COMMAND}` and Add Output to Report
    [Documentation]    Runs a user provided gcloud command and adds the output to the report.
    [Tags]    stdout    gcloud    generic
    ${rsp}=    RW.CLI.Run Cli
    ...    cmd=gcloud auth activate-service-account --key-file=$GOOGLE_APPLICATION_CREDENTIALS && ${GCLOUD_COMMAND}
    ...    env=${env}
    ...    secret_file__gcp_credentials_json=${gcp_credentials_json}
    ...    timeout_seconds=180
    ${history}=    RW.CLI.Pop Shell History
    ${STDOUT}=    Set Variable    ${rsp.stdout}
    IF    """${rsp.stdout}""" != ""
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

    ELSE
        RW.Core.Add Pre To Report    No output was returned from the command, indicating no errors were found.
        RW.Core.Add Pre To Report    Command stdout: ${rsp.stdout}
        RW.Core.Add Pre To Report    Command stderr: ${rsp.stderr}
        RW.Core.Add Pre To Report    Commands Used: ${history}
    END


*** Keywords ***
Suite Initialization
    ${gcp_credentials_json}=    RW.Core.Import Secret    gcp_credentials_json
    ...    type=string
    ...    description=GCP service account json used to authenticate with GCP APIs.
    ...    pattern=\w*
    ...    example={"type": "service_account","project_id":"myproject-ID", ... super secret stuff ...}
    Run User Provided GCloud Command in `${GCLOUD_COMMAND}` and Add Output to Report=    RW.Core.Import User Variable    TASK_TITLE
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
    ${OS_PATH}=    Get Environment Variable    PATH
    Set Suite Variable    ${gcp_credentials_json}    ${gcp_credentials_json}
    Set Suite Variable
    ...    ${env}
    ...    {"GOOGLE_APPLICATION_CREDENTIALS":"./${gcp_credentials_json.key}","PATH":"$PATH:${OS_PATH}"}