*** Settings ***
Documentation       This taskset runs a user provided awscli command and adds the output to the report. Command line tools like jq are available.

Metadata            Author    jon-funk
Metadata            DisplayName    AWS CLI Command
Metadata            Supports    AWS
Library             BuiltIn
Library             RW.Core
Library             RW.platform
Library             OperatingSystem
Library             RW.CLI

Suite Setup         Suite Initialization


*** Tasks ***
${TASK_TITLE}
    [Documentation]    Runs a user provided aws cli command and adds the output to the report.
    [Tags]    aws    cli    generic
    ${rsp}=    RW.CLI.Run Cli
    ...    cmd=${AWS_COMMAND}
    ...    env={"AWS_REGION":"${AWS_REGION}"}
    ...    secret__AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
    ...    secret__AWS_ACCESS_KEY_ID=${secret__AWS_ACCESS_KEY_ID}
    ${history}=    RW.CLI.Pop Shell History
    RW.Core.Add Pre To Report    Command stdout: ${rsp.stdout}
    RW.Core.Add Pre To Report    Command stderr: ${rsp.stderr}
    RW.Core.Add Pre To Report    Commands Used: ${history}


*** Keywords ***
Suite Initialization
    ${AWS_SECRET_ACCESS_KEY}=    RW.Core.Import Secret
    ...    AWS_SECRET_ACCESS_KEY
    ...    type=string
    ...    description=The secret access key used for authenticating the aws cli.
    ...    pattern=\w*
    ...    example=
    ${AWS_ACCESS_KEY_ID}=    RW.Core.Import Secret
    ...    AWS_ACCESS_KEY_ID
    ...    type=string
    ...    description=The access key for authenticating the aws cli.
    ...    pattern=\w*
    ...    example=
    ${AWS_REGION}=    RW.Core.Import User Variable    AWS_REGION
    ...    type=string
    ...    description=The aws region that actions are performed in.
    ...    pattern=\w*
    ...    example=us-west-1
    ...    default=us-west-1
    ${AWS_COMMAND}=    RW.Core.Import User Variable    AWS_COMMAND
    ...    type=string
    ...    description=The aws cli command to run. Can use tools like jq.
    ...    pattern=\w*
    ...    example=aws logs filter-log-events --log-group-name /aws/lambda/hello-error --filter-pattern "ERROR" | jq -r '.events[].message'
    ${TASK_TITLE}=    RW.Core.Import User Variable    TASK_TITLE
    ...    type=string
    ...    description=The name of the task to run. This is useful for helping find this generic task with RunWhen Digital Assistants. 
    ...    pattern=\w*
    ...    example="Count the number of pods in the namespace"