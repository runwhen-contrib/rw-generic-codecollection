# GCloud Stdout Issue Detection
A generic codebundle used for running a gcloud command, commonly with grep, that raises an issue when the command output is non-empty, implying that an error was found via grepping the output.

## TaskSet
The generalized user-provided command that can raise a configurable issue if the return is non-empty

Example: `gcloud projects list`

## SLI
A generalized SLI that pushes a 1 when the output is empty, indicating no errors were found. Pushes a 0 (unhealthy) metric when output is produced.

Example: `gcloud projects list`

## Requirements
- A kubeconfig for authentication