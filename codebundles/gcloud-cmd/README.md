# Generic gcloud command
A generic codebundle used for running user provided gcloud commands in a bash shell. 

## SLI
The command provided must provide a single metric that is pushed to the RunWhen Platform. 

Example: `gcloud projects list --format="json" | jq '. | length'`

## TaskSet
The command has all output added to the report for review during a RunSession. 

Example: `gcloud projects list`

## Requirements
- A GCP service account json with appropriate RBAC permissions to perform the desired command.