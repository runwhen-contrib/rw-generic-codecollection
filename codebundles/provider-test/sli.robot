*** Settings ***
Documentation       Does the needful by testing provider secrets
Metadata            Author    jon-funk

Library             BuiltIn
Library             Process
Library             RW.Core
Library             RW.platform
Library             OperatingSystem
Library             RW.CLI

Suite Setup         Suite Initialization


*** Tasks ***
Test Secret Providers
    [Documentation]    Pushes the total score to the platform
    [Tags]    kubectl    cli    metric    sli    generic
    Log To Console    Run Finished

*** Keywords ***
Suite Initialization
    ${TOTAL_SCORE}=    Set Variable    0
    ${ENV_LIST}=    RW.Core.Import User Variable    ENV_LIST
    ...    type=string
    ...    description=ENV vars to check for testing
    ...    pattern=\w*
    ...    example=SpecialEnvCOnfigMap helloEnvSecret TEST_CASEEnvConfigMap
    ...    default=SpecialEnvCOnfigMap helloEnvSecret TEST_CASEEnvConfigMap
    ${FILE_LIST}=    RW.Core.Import User Variable    FILE_LIST
    ...    type=string
    ...    description=Files to check for testing
    ...    pattern=\w*
    ...    example=secrets/goodbyeFileConfigMap secrets/goodbyeFileSecret
    ...    default=secrets/goodbyeFileConfigMap secrets/goodbyeFileSecret
    Set Suite Variable
    ...    &{env_check_params}
    ...    ENV_LIST=${ENV_LIST}
    ...    FILE_LIST=${FILE_LIST}
    ${process}=    Run Process    ${CURDIR}/check_files_exist.sh    env=${env_check_params}
    Log To Console    ${process.stdout}
    IF    ${process.rc} == 0
        Set Variable    ${TOTAL_SCORE}=${TOTAL_SCORE}+0.4
    END
    ${process}=    Run Process    ${CURDIR}/validate_envs.sh    env=${env_check_params}
    Log To Console    ${process.stdout}
    IF    ${process.rc} == 0
        Set Variable    ${TOTAL_SCORE}=${TOTAL_SCORE}+0.4
    END

    ${kubeconfig}=    RW.Core.Import Secret
    ...    kubeconfig
    ...    type=string
    ...    description=The kubernetes kubeconfig yaml containing connection configuration used to connect to cluster(s).
    ...    pattern=\w*
    ...    example=For examples, start here https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/
    ${helloEnvSecret}=    RW.Core.Import Secret
    ...    helloEnvSecret
    ...    type=string
    ...    description=Provider Environment variable import from secret ref
    ...    pattern=\w*
    ${TEST_CASEEnvConfigMap}=    RW.Core.Import Secret
    ...    TEST_CASEEnvConfigMap
    ...    type=string
    ...    description=Provider Environment variable import from configmap
    ...    pattern=\w*
    ${goodbyeFileConfigMap}=    RW.Core.Import Secret
    ...    goodbyeFileConfigMap
    ...    type=string
    ...    description=Provider file import from configmap file
    ...    pattern=\w*
    ${goodbyeFileSecret}=    RW.Core.Import Secret
    ...    goodbyeFileSecret
    ...    type=string
    ...    description=Provider file import from secret ref into file
    ...    pattern=\w*
    ${specialEnvConfigMap}=    RW.Core.Import Secret
    ...    specialEnvConfigMap
    ...    type=string
    ...    description=Provider environment variable import from configmap
    ...    pattern=\w*
    # ${TASK_TITLE}=    RW.Core.Import User Variable    TASK_TITLE
    # ...    type=string
    # ...    description=The name of the task to run. This is useful for helping find this generic task with RunWhen Digital Assistants. 
    # ...    pattern=\w*
    # ...    example="Count the number of pods in the namespace"
    RW.Core.Push Metric    ${TOTAL_SCORE}
