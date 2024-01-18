Troubleshooting Tasks in Codecollection: **10**
Codebundles in Codecollection: **6**

![](docs/GitHub_Banner.jpg)

<p align="center">
  <a href="https://discord.gg/Ut7Ws4rm8Q">
    <img src="https://img.shields.io/discord/1131539039665791077?label=Join%20Discord&logo=discord&logoColor=white&style=for-the-badge" alt="Join Discord">
  </a>
  <br>
  <a href="https://runwhen.slack.com/join/shared_invite/zt-1l7t3tdzl-IzB8gXDsWtHkT8C5nufm2A">
    <img src="https://img.shields.io/badge/Join%20Slack-%23E01563.svg?&style=for-the-badge&logo=slack&logoColor=white" alt="Join Slack">
  </a>
</p>
<a href='https://codespaces.new/runwhen-contrib/rw-cli-codecollection?quickstart=1'><img src='https://github.com/codespaces/badge.svg' alt='Open in GitHub Codespaces' style='max-width: 100%;'></a>

# RunWhen Generic Codecollection
This repository is a codecollection that is to be used within the RunWhen platform. It contains codebundles that can be used in SLIs, and TaskSets. 

## Getting Started
Head on over to our centralized documentation [here](https://docs.runwhen.com/public/runwhen-authors/getting-started-with-codecollection-development) for detailed information on getting started.
## Codebundle Index
| Name | Supported Integrations | Tasks | Documentation |
|---|---|---|---|
| [cURL HTTP OK](https://github.com/runwhen-contrib/rw-generic-codecollection/blob/main/codebundles/curl-http-ok/sli.robot) | `Linux macOS Windows HTTP` | `Checking HTTP URL Is Available And Timely` | This taskset uses curl to validate the response code of the endpoint. Returns ascore of 1 if healthy, an 0 if unhealthy. [Docs](https://docs.runwhen.com/public/v/cli-codecollection/curl-http-ok) |
| [cli-test-taskset](https://github.com/runwhen-contrib/rw-generic-codecollection/blob/main/codebundles/cli-test/runbook.robot) | `cli` | `Run CLI and Parse Output For Issues`, `Exec Test`, `Local Process Test` | This taskset smoketests the CLI codebundle setup and run process [Docs](https://docs.runwhen.com/public/v/cli-codecollection/cli-test) |
| [cmd-test-taskset](https://github.com/runwhen-contrib/rw-generic-codecollection/blob/main/codebundles/cmd-test/runbook.robot) | `cmd` | `Run CLI Command`, `Run Bash File`, `Log Suggestion` | This taskset smoketests the CLI codebundle setup and run process by running a bare command [Docs](https://docs.runwhen.com/public/v/cli-codecollection/cmd-test) |
| [k8s-kubectl-cmd-sli](https://github.com/runwhen-contrib/rw-generic-codecollection/blob/main/codebundles/k8s-kubectl-cmd/sli.robot) | `k8s` | `${TASK_TITLE}` | This taskset runs a user provided kubectl command and pushes the metric. The supplied command must result in distinct single metric. Command line tools like jq are available. [Docs](https://docs.runwhen.com/public/v/cli-codecollection/k8s-kubectl-cmd) |
| [k8s-kubectl-cmd-taskset](https://github.com/runwhen-contrib/rw-generic-codecollection/blob/main/codebundles/k8s-kubectl-cmd/runbook.robot) | `k8s` | `${TASK_TITLE}` | This taskset runs a user provided kubectl command andadds the output to the report. Command line tools like jq are available. [Docs](https://docs.runwhen.com/public/v/cli-codecollection/k8s-kubectl-cmd) |

