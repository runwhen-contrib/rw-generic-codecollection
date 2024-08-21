# Curl Stdout Issue Detection
A generic codebundle used for running a curl command, commonly with grep, that raises an issue when the command output is non-empty, implying that an error was found via grepping the output.

## TaskSet
The generalized user-provided command that can raise a configurable issue if the return is non-empty

Example: `curl -X POST https://postman-echo.com/post --fail --silent --show-error | jq -r '.json'`
