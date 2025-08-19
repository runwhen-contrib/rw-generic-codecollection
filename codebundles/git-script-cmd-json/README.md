# Git Script Command
A generic codebundle designed for safely executing scripts with arbitrary environment variables, particularly useful for private git repository operations and script execution with secrets.

## Features
- **Flexible Secret Management**: Load any number of secrets as environment variables
- **Private Git Support**: Securely handle git credentials for private repository access
- **Script Execution**: Execute scripts with full environment context
- **SSH Key Support**: Handle SSH keys for git operations
- **Multi-Environment**: Support for complex deployment scenarios requiring multiple secrets

## SLI
The SLI pushes a health metric to the RunWhen Platform: 1 for success (healthy), 0 for failure (unhealthy). The metric is based on the script's exit code, not its output.

Example: `git clone https://github.com/private/repo.git /tmp/repo && /tmp/repo/scripts/health-check.sh`

## TaskSet
The command has all output added to the report for review during a RunSession. 

Example: `git clone git@github.com:private/repo.git /tmp/repo && bash /tmp/repo/scripts/deploy.sh`

## Requirements
- **SCRIPT_COMMAND**: The script/command to execute
- **Secrets**: Any number of secrets that will be loaded as environment variables
- **Optional SSH_PRIVATE_KEY**: SSH private key for git operations
- **Optional GIT_USERNAME/GIT_TOKEN**: HTTPS git credentials

## Common Use Cases

### Private Git Repository with SSH
```bash
# Set SSH_PRIVATE_KEY secret, then:
SCRIPT_COMMAND="git clone git@github.com:private/repo.git /tmp/repo && bash /tmp/repo/scripts/deploy.sh"
```

### Private Git Repository with HTTPS Token
```bash
# Set GIT_USERNAME and GIT_TOKEN secrets, then:
SCRIPT_COMMAND="git clone https://\$GIT_USERNAME:\$GIT_TOKEN@github.com/private/repo.git /tmp/repo && bash /tmp/repo/scripts/deploy.sh"
```

### Multiple Environment Secrets
```bash
# Set DATABASE_URL, API_KEY, SLACK_TOKEN secrets, then:
SCRIPT_COMMAND="git clone https://github.com/private/repo.git /tmp/repo && bash /tmp/repo/scripts/check-services.sh"
```

## Security Features
- All secrets are handled securely through RunWhen's secret management
- SSH keys are written to temporary files with appropriate permissions
- Environment variables are isolated to the command execution context
- No secrets are logged or exposed in reports 