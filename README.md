Troubleshooting Tasks in Codecollection: **6**
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
| [curl-cmd-sli](https://github.com/runwhen-contrib/rw-generic-codecollection/blob/main/codebundles/curl-cmd/sli.robot) | `curl` | `${TASK_TITLE}` | This SLI runs a user provided curl command and can push the result as a metric. Command line tools like jq are available. [Docs](https://docs.runwhen.com/public/v/cli-codecollection/curl-cmd) |
| [curl-cmd-taskset](https://github.com/runwhen-contrib/rw-generic-codecollection/blob/main/codebundles/curl-cmd/runbook.robot) | `curl` | `${TASK_TITLE}` | This taskset runs a user provided curl command and adds the output to the report. Command line tools like jq are available. [Docs](https://docs.runwhen.com/public/v/cli-codecollection/curl-cmd) |
| [gcloud-cmd-sli](https://github.com/runwhen-contrib/rw-generic-codecollection/blob/main/codebundles/gcloud-cmd/sli.robot) | `GCP` | `${TASK_TITLE}` | Runs a user provided gcloud command and pushes the metric to the RunWhen Platform. The supplied command must result in distinct single metric. Command line tools like jq are available. [Docs](https://docs.runwhen.com/public/v/cli-codecollection/gcloud-cmd) |
| [gcloud-cmd-taskset](https://github.com/runwhen-contrib/rw-generic-codecollection/blob/main/codebundles/gcloud-cmd/runbook.robot) | `GCP` | `${TASK_TITLE}` | Runs a user provided gcloud command [Docs](https://docs.runwhen.com/public/v/cli-codecollection/gcloud-cmd) |
| [k8s-kubectl-cmd-sli](https://github.com/runwhen-contrib/rw-generic-codecollection/blob/main/codebundles/k8s-kubectl-cmd/sli.robot) | `k8s` | `${TASK_TITLE}` | This taskset runs a user provided kubectl command and pushes the metric. The supplied command must result in distinct single metric. Command line tools like jq are available. [Docs](https://docs.runwhen.com/public/v/cli-codecollection/k8s-kubectl-cmd) |
| [k8s-kubectl-cmd-taskset](https://github.com/runwhen-contrib/rw-generic-codecollection/blob/main/codebundles/k8s-kubectl-cmd/runbook.robot) | `k8s` | `${TASK_TITLE}` | This taskset runs a user provided kubectl command andadds the output to the report. Command line tools like jq are available. [Docs](https://docs.runwhen.com/public/v/cli-codecollection/k8s-kubectl-cmd) |

