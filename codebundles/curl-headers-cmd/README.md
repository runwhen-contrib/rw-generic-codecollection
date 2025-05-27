# Curl cmd
A generic codebundle used for running bare curl commands in a bash shell. 

## SLI
The command provided must provide a single metric that is pushed to the RunWhen Platform. 

Example: `curl -X POST https://postman-echo.com/post --fail --silent --show-error | jq -r '.json | length'`

## TaskSet
The command has all output added to the report for review during a RunSession. 

Example: `curl -X POST https://postman-echo.com/post --fail --silent --show-error | jq -r '.json'`

## Requirements
- A curl command string of your choosing