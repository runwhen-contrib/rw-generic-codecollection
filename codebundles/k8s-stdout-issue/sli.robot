*** Settings ***
Documentation       Runs an ad-hoc user-provided command, and if the provided command outputs a non-empty string to stdout then a health score of 0 (unhealthy) is pushed, otherwise if there is no output, indicating no issues, then a 1 is pushed.
...                 User commands should filter expected/healthy content (eg: with grep) and only output found errors.

Metadata            Author    jon-funk
Metadata            Display Name    Metric from Kubernetes CLI Command
Metadata            Supports    K8s    Kubernetes

Library             BuiltIn
Library             RW.Core
Library             RW.platform
Library             OperatingSystem
Library             RW.CLI

Suite Setup         Suite Initialization


*** Tasks ***
${TASK_TITLE}
    [Documentation]    Runs a user provided kubectl command and if the return string is non-empty it indicates an error was found, pushing a health score of 0, otherwise pushes a 1.
    [Tags]    kubectl    cli    generic
    ${rsp}=    RW.CLI.Run Cli
    ...    cmd=${KUBECTL_COMMAND}
    ...    env={"KUBECONFIG":"./${kubeconfig.key}"}
    ...    secret_file__kubeconfig=${kubeconfig}
    ...    timeout_seconds=${TIMEOUT_SECONDS}
    ${history}=    RW.CLI.Pop Shell History
    ${STDOUT}=    Set Variable    ${rsp.stdout}
    IF    """${rsp.stdout}""" != ""
        RW.Core.Push Metric     0
    ELSE
        RW.Core.Push Metric     1
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
    ...    example="kubectl get events -n online-boutique | grep -i warning"
    ${TASK_TITLE}=    RW.Core.Import User Variable    TASK_TITLE
    ...    type=string
    ...    description=The name of the task to run. This is useful for helping find this generic task with RunWhen Digital Assistants. 
    ...    pattern=\w*
    ...    example="Count the number of pods in the namespace"
    ${TIMEOUT_SECONDS}=    RW.Core.Import User Variable    TIMEOUT_SECONDS
    ...    type=string
    ...    description=The amount of seconds before the command is killed. 
    ...    pattern=\w*
    ...    example=120
    ...    default=120

