# Azure CLI CMD Generic
A generic codebundle used for running a azure cli command, commonly with grep, that raises an issue when the command output is non-empty, implying that an error was found via grepping the output.

## TaskSet
The generalized user-provided command that can raise a configurable issue if the return is non-empty

Example: `az monitor metrics list --resource myapp --resource-group myrg  --resource-type Microsoft.Web/sites --metric "HealthCheckStatus" --interval 5m | -r '.value[].timeseries[].data[].average'`

## SLI
A generalized SLI that pushes a 1 when the output is empty, indicating no errors were found. Pushes a 0 (unhealthy) metric when output is produced.

Example: `az monitor metrics list --resource myapp --resource-group myrg  --resource-type Microsoft.Web/sites --metric "HealthCheckStatus" --interval 5m | -r '.value[].timeseries[].data[].average'`

## Requirements
- AZ_RESOURCE_GROUP
- AZ_USERNAME
- AZ_SECRET_VALUE
- AZ_TENANT
- AZ_SUBSCRIPTION