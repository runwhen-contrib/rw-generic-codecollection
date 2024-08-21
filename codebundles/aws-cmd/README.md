# AWS CMD Generic
A generic codebundle used for running a aws cli command and adding the output to a report

## TaskSet
The generalized user-provided command that can raise a configurable issue if the return is non-empty

Example: `aws logs filter-log-events --log-group-name /aws/lambda/hello-world --filter-pattern "ERROR" | jq -r '.events[].message'`

## SLI
A generalized SLI that pushes a 1 when the output is empty, indicating no errors were found. Pushes a 0 (unhealthy) metric when output is produced.

Example: `aws logs filter-log-events --log-group-name /aws/lambda/hello-world --filter-pattern "ERROR" | jq -r '.events[].message'`

## Requirements
- AWS_SECRET_ACCESS_KEY
- AWS_ACCESS_KEY_ID
- AWS_REGION