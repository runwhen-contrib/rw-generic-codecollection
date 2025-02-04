*** Settings ***
Documentation       This taskset runs a user provided kubectl command and adds the output to the report. Command line tools like jq are available.
Metadata            Author    stewartshea
Metadata            Display Name    Kubernetes CLI Command
Metadata            Supports    K8s    Kubernetes

Library             BuiltIn
Library             RW.Core
Library             RW.platform
Library             OperatingSystem
Library             RW.CLI

Suite Setup         Suite Initialization


*** Tasks ***
Run Kubectl Command in `${KUBECTL_COMMAND}`
    [Documentation]    Runs a user provided kubectl command and adds the output to the report.
    [Tags]    kubectl    cli    generic
    ${rsp}=    RW.CLI.Run Cli
    ...    cmd=${KUBECTL_COMMAND}
    ...    env={"KUBECONFIG":"./${kubeconfig.key}"}
    ...    secret_file__kubeconfig=${kubeconfig}
    ${history}=    RW.CLI.Pop Shell History
    RW.Core.Add Pre To Report    Command stdout: ${rsp.stdout}
    RW.Core.Add Pre To Report    Command stderr: ${rsp.stderr}
    RW.Core.Add Pre To Report    Commands Used: ${history}


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
    Run Kubectl Command in `${KUBECTL_COMMAND}`=    RW.Core.Import User Variable    TASK_TITLE
    ...    type=string
    ...    description=The name of the task to run. This is useful for helping find this generic task with RunWhen Digital Assistants. 
    ...    pattern=\w*
    ...    example="Count the number of pods in the namespace"
