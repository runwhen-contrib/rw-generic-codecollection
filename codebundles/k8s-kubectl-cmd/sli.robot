*** Settings ***
Documentation       This taskset runs a user provided kubectl command and pushes the metric. The supplied command must result in distinct single metric. Command line tools like jq are available. 
Metadata            Author    stewartshea
Metadata            Display Name    Metric from Kubernetes CLI Command
Metadata            Supports    K8s    Kubernetes

Library             BuiltIn
Library             RW.Core
Library             RW.platform
Library             OperatingSystem
Library             RW.CLI

Suite Setup         Suite Initialization


*** Tasks ***
Run Kubectl Command and Push Metric as SLI in `${WHERE}`
    [Documentation]    Runs a user provided kubectl command and pushes the metric as an SLI
    [Tags]    kubectl    cli    metric    sli    generic
    ${rsp}=    RW.CLI.Run Cli
    ...    cmd=${KUBECTL_COMMAND}
    ...    env={"KUBECONFIG":"./${kubeconfig.key}"}
    ...    secret_file__kubeconfig=${kubeconfig}
    RW.Core.Push Metric    ${rsp.stdout}

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
    ...    description=The kubectl command to run. Must produce a single value that can be pushed as a metric. Can use tools like jq. 
    ...    pattern=\w*
    ...    example="kubectl get pods -n online-boutique -o json | jq '[.items[]] | length'"
    Run Kubectl Command and Push Metric as SLI in `${WHERE}`=    RW.Core.Import User Variable    TASK_TITLE
    ...    type=string
    ...    description=The name of the task to run. This is useful for helping find this generic task with RunWhen Digital Assistants. 
    ...    pattern=\w*
    ...    example="Count the number of pods in the namespace"
