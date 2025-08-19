# Environment Script Command
A generic codebundle designed for safely executing scripts with configurable environment variables from secrets. This provides the most flexible and secure approach for loading arbitrary secrets as environment variables.

## Features
- **Maximum Flexibility**: Load any number of secrets as individual environment variables
- **Private Git Support**: Secure git operations with SSH keys or tokens
- **Script Execution**: Execute any script with full environment context
- **Individual Secret Control**: Each secret is configured separately for maximum security
- **No JSON Parsing**: Avoids complexity and security issues of JSON parsing

## SLI
The command provided must provide a single metric that is pushed to the RunWhen Platform. 

Example: `git clone https://$GIT_TOKEN@github.com/private/repo.git /tmp/repo && /tmp/repo/scripts/health-check.sh | jq -r '.metric'`

## TaskSet
The command has all output added to the report for review during a RunSession. 

Example: `git clone git@github.com:private/repo.git /tmp/repo && bash /tmp/repo/scripts/deploy.sh`

## Requirements
- **SCRIPT_COMMAND**: The script/command to execute
- **Individual Secrets**: Configure each secret separately (ENV_VAR_1, ENV_VAR_2, etc.)
- **Optional SSH_PRIVATE_KEY**: SSH private key for git operations
- **Optional kubeconfig**: Kubernetes config file for cluster access

## Configuration Approach

This codebundle uses individual secret imports rather than JSON parsing, making it:
- **Safer**: No risk of JSON injection or parsing errors
- **More Flexible**: Each secret can have its own description and validation
- **Easier to Configure**: Clear separation of each environment variable
- **More Secure**: Each secret is handled individually by RunWhen's secret management

## Usage Examples

### Basic Usage with Multiple Environment Variables
```bash
# Configure secrets individually:
# - ENV_VAR_DATABASE_URL (secret)
# - ENV_VAR_API_KEY (secret)
# - ENV_VAR_SLACK_TOKEN (secret)

SCRIPT_COMMAND="echo 'Database: $DATABASE_URL' && echo 'API Key configured: ${API_KEY:0:8}...' && curl -X POST $SLACK_WEBHOOK"
```

### Private Git Repository with SSH
```bash
# Configure SSH_PRIVATE_KEY secret, then:
SCRIPT_COMMAND="git clone git@github.com:private/repo.git ./repo && bash ./repo/scripts/deploy.sh"
```

### Private Git Repository with Token
```bash
# Configure ENV_VAR_GIT_TOKEN secret, then:
SCRIPT_COMMAND="git clone https://$GIT_TOKEN@github.com/private/repo.git ./repo && bash ./repo/scripts/deploy.sh"
```

### Private Git + Kubernetes Operations
```bash
# Configure secrets:
# - SSH_PRIVATE_KEY (secret) - for git access
# - kubeconfig (secret) - for K8s access
# - ENV_VAR_1_NAME = "NAMESPACE" 
# - ENV_VAR_1_VALUE = "production" (secret)

SCRIPT_COMMAND="git clone git@github.com:private/k8s-repo.git ./repo && kubectl apply -f ./repo/manifests/ -n $NAMESPACE"
```

## Security Features
- Individual secret management through RunWhen's secure secret system
- SSH keys handled automatically by RunWhen platform, permissions fixed to 600
- Uses `GIT_SSH_COMMAND` to specify SSH key location for git operations
- Works in shared runner environments without requiring home directory access
- Creates local known_hosts file for GitHub SSH verification
- Environment variables isolated to command execution context
- No secret values logged or exposed in reports
- Each secret can be individually validated and managed 