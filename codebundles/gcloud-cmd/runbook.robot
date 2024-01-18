*** Settings ***
Documentation       Runs a user provided gcloud command
Metadata            Author    stewartshea
Metadata            Supports    GCP

Library             BuiltIn
Library             RW.Core
Library             RW.CLI
Library             RW.platform
Library             OperatingSystem

Suite Setup         Suite Initialization


*** Tasks ***
${TASK_TITLE}
    [Documentation]    Runs a user provided gcloud command and adds the output to the report.
    [Tags]    stdout    gcloud    generic
    ${rsp}=    RW.CLI.Run Cli
    ...    cmd=gcloud auth activate-service-account --key-file=$GOOGLE_APPLICATION_CREDENTIALS && ${GCLOUD_COMMAND}
    ...    env=${env}
    ...    secret_file__gcp_credentials_json=${gcp_credentials_json}
    ...    timeout_seconds=180
    ${history}=    RW.CLI.Pop Shell History
    RW.Core.Add Pre To Report    Command stdout: ${rsp.stdout}
    RW.Core.Add Pre To Report    Command stderr: ${rsp.stderr}
    RW.Core.Add Pre To Report    Commands Used: ${history}


*** Keywords ***
Suite Initialization
    ${gcp_credentials_json}=    RW.Core.Import Secret    gcp_credentials_json
    ...    type=string
    ...    description=GCP service account json used to authenticate with GCP APIs.
    ...    pattern=\w*
    ...    example={"type": "service_account","project_id":"myproject-ID", ... super secret stuff ...}
    ${OS_PATH}=    Get Environment Variable    PATH
    Set Suite Variable    ${gcp_credentials_json}    ${gcp_credentials_json}
    Set Suite Variable
    ...    ${env}
    ...    {"GOOGLE_APPLICATION_CREDENTIALS":"./${gcp_credentials_json.key}","PATH":"$PATH:${OS_PATH}"}
    ${TASK_TITLE}=    RW.Core.Import User Variable    TASK_TITLE
    ...    type=string
    ...    description=The name of the task to run. This is useful for helping find this generic task with RunWhen Digital Assistants. 
    ...    pattern=\w*
    ...    example="List all GCP Projects"
    ${GCLOUD_COMMAND}=    RW.Core.Import User Variable    GCLOUD_COMMAND
    ...    type=string
    ...    description=The gcloud command to run. Make sure to pass along details such as the GCP Project ID. 
    ...    pattern=\w*
    ...    example="gcloud projects list"


