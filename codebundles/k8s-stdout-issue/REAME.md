# K8s Stdout Issue Detection
A generic codebundle used for running a kubectl command, commonly with grep, that raises an issue when the command output is non-empty, implying that an error was found via grepping the output.

## TaskSet
The generalized user-provided command that can raise a configurable issue if the return is non-empty

Example: `kubectl get events | grep -i warning`

## Requirements
- A kubeconfig for authentication