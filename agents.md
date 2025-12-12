# Codebundles Directory - General Cursor Rules

## Overview

This directory contains **generic** RunWhen codebundles for various cloud platforms and services. These codebundles are highly configurable templates that allow users to add their own custom commands, scripts, and configurations. Each generic codebundle provides a flexible framework for health monitoring, troubleshooting, and operational tasks that users customize to their specific needs.

## Directory Structure

### Codebundle Organization

- Each codebundle is in its own subdirectory

- Subdirectory names follow pattern: `[platform]-[tool]-[purpose]`

- Examples: `aws-cmd`, `k8s-kubectl-cmd`, `azure-cmd`, `curl-cmd`, `gcloud-cmd`, `git-script-cmd-env`

- These are **generic codebundles** - users provide their own commands/scripts via configuration variables

- Each codebundle should have its own `.cursorrules` file for specific patterns

### Common Files

- **runbook.robot**: Main Robot Framework execution file that executes user-provided commands/scripts

- **sli.robot**: Service Level Indicator definitions that process command output for metrics

- **meta.yaml**: Codebundle metadata and configuration (optional, not all codebundles have this)

- **README.md**: Documentation with usage examples, configuration requirements, and command examples

- **.test/**: Testing infrastructure and validation scripts (optional)

## Universal Standards

### Generic Codebundle Philosophy

- **User-Provided Commands**: These codebundles execute user-provided commands/scripts, not hardcoded operations

- **Configuration-Driven**: All user commands are provided via user variables (e.g., `AWS_COMMAND`, `KUBECTL_COMMAND`, `SCRIPT_COMMAND`)

- **Flexible Output Processing**: Codebundles capture command output and make it available for reporting and SLI metrics

- **Platform-Agnostic Execution**: Commands run in bash shells with appropriate CLI tools available (aws, az, kubectl, gcloud, curl, jq, etc.)

- **Secret Management**: Use RunWhen's secret management for authentication credentials, never hardcode

### Issue Reporting

- **Issue Titles**: Must include entity name, resource type, and scope (when applicable)

- **Issue Details**: Must provide context, metrics, and actionable next steps

- **Severity Levels**: Use 1-4 scale (1=Critical, 2=High, 3=Medium, 4=Low)

- **Portal Links**: Include direct links to cloud provider portals (when applicable)

### Script Development

- **User Command Variables**: All codebundles must accept user-provided commands via user variables

- **Command Execution**: Execute commands in bash shells with proper error handling

- **Output Format**: Capture both stdout and stderr, provide both human-readable and machine-readable outputs

- **Environment Variables**: Validate required variables at script start, support configurable environment variables from secrets

- **Logging**: Include meaningful progress indicators and error messages

- **Tool Availability**: Document which CLI tools are available (jq, grep, awk, etc.)

### Robot Framework

- **Task Naming**: Use user-configurable task titles via `TASK_TITLE` variable for discoverability

- **Documentation**: Include proper docstrings explaining that commands are user-provided

- **Variables**: Import and validate all required user variables (commands) and secrets (authentication)

- **Error Handling**: Use proper try-catch patterns, capture command exit codes and output

- **Output Capture**: Always capture and report command stdout, stderr, and shell history

## Platform-Specific Patterns

### Azure Codebundles (`azure-cmd`)

- Execute user-provided Azure CLI commands via `AZ_COMMAND` variable

- Require Azure authentication secrets: `AZ_USERNAME`, `AZ_SECRET_VALUE`, `AZ_TENANT`, `AZ_SUBSCRIPTION`

- Common user variables: `AZ_RESOURCE_GROUP` for context

- Users provide their own `az` commands (e.g., `az monitor metrics list ... | jq ...`)

- Output is captured and added to reports

### Kubernetes Codebundles (`k8s-kubectl-cmd`)

- Execute user-provided kubectl commands via `KUBECTL_COMMAND` variable

- Require kubeconfig secret for cluster authentication

- Users provide their own `kubectl` commands (e.g., `kubectl get pods -n namespace -o json | jq ...`)

- Support for namespace and cluster context via user commands

- Output is captured and added to reports

### AWS Codebundles (`aws-cmd`)

- Execute user-provided AWS CLI commands via `AWS_COMMAND` variable

- Require AWS authentication secrets: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`

- Common user variables: `AWS_REGION` for context

- Users provide their own `aws` commands (e.g., `aws logs filter-log-events ... | jq ...`)

- Output is captured and added to reports

### GCP Codebundles (`gcloud-cmd`)

- Execute user-provided gcloud commands via `GCLOUD_COMMAND` variable

- Require GCP service account JSON secret for authentication

- Users provide their own `gcloud` commands (e.g., `gcloud projects list --format="json" | jq ...`)

- Support for project and region context via user commands

- Output is captured and added to reports

### Generic Command Codebundles

- **`curl-cmd`**: Execute user-provided curl commands for HTTP/API operations

- **`git-script-cmd-env`**: Execute user-provided scripts with configurable environment variables from secrets

- **`git-script-cmd-json`**: Execute user-provided scripts with JSON-based secret configuration

- All support user-provided commands with flexible output processing

## Code Quality Standards

### Documentation

- **README.md**: Must include:
  - Clear explanation that this is a generic codebundle
  - Required user variables (especially the command variable)
  - Required secrets for authentication
  - Example commands users can provide
  - SLI and TaskSet behavior explanation
  - Configuration examples

- **Comments**: Include meaningful comments explaining user variable usage

- **Examples**: Provide multiple real-world command examples showing different use cases

- **Troubleshooting**: Include common issues and solutions related to command execution

### Testing

- **Syntax Validation**: All scripts must pass syntax checks

- **Mock Testing**: Test with mock data when possible

- **Integration Testing**: Test with real resources when available

- **Error Scenarios**: Test error handling and edge cases

### Security

- **Authentication**: Use service principals or IAM roles

- **Secrets**: Never hardcode credentials

- **Permissions**: Use least privilege access

- **Data Handling**: Sanitize sensitive information

## Development Workflow

### Creating New Generic Codebundles

1. Follow the naming convention: `[platform]-[tool]-[purpose]` (e.g., `aws-cmd`, `k8s-kubectl-cmd`)

2. Create the basic file structure:
   - `runbook.robot`: Execute user-provided commands via user variable
   - `sli.robot`: Process command output for metrics
   - `README.md`: Document user variables, secrets, and example commands

3. Implement user variable for command:
   - Import user variable for the command (e.g., `AWS_COMMAND`, `KUBECTL_COMMAND`)
   - Import required secrets for authentication
   - Import optional context variables (region, namespace, etc.)
   - Import optional `TASK_TITLE` for task naming

4. Execute and capture output:
   - Use `RW.CLI.Run Cli` to execute user command
   - Capture stdout, stderr, and shell history
   - Add output to report using `RW.Core.Add Pre To Report`

5. Add comprehensive documentation with multiple command examples

6. Test with various user-provided commands to ensure flexibility

### Modifying Existing Codebundles

1. Review existing patterns and conventions

2. Maintain backward compatibility when possible

3. Update documentation for new features

4. Test changes thoroughly

5. Update version information

### Code Review Checklist

- [ ] Accepts user-provided commands via user variable (not hardcoded)

- [ ] Follows platform-specific patterns for generic codebundles

- [ ] Includes proper error handling and output capture

- [ ] Provides meaningful output and logging

- [ ] Includes comprehensive documentation with example commands

- [ ] Passes all tests and validations

- [ ] Uses secure authentication methods via secrets

- [ ] Follows naming conventions (`[platform]-[tool]-[purpose]`)

- [ ] Supports configurable task titles for discoverability

- [ ] Captures both stdout and stderr from user commands

## Best Practices

### Performance

- Minimize API calls and resource usage

- Use appropriate timeouts and retries

- Cache results when possible

- Handle large datasets efficiently

### Maintainability

- Use consistent code style and formatting

- Include meaningful variable names

- Document complex logic and algorithms

- Follow DRY (Don't Repeat Yourself) principles

### Reliability

- Implement proper error handling

- Use idempotent operations where possible

- Include fallback mechanisms

- Test edge cases and failure scenarios

### Usability

- Provide clear and actionable output from user commands

- Include helpful error messages when commands fail

- Use consistent terminology across all generic codebundles

- Provide multiple examples showing different use cases and command patterns

- Document available CLI tools and their usage (jq, grep, awk, etc.)

- Make it easy for users to understand what commands they can provide

## Integration Guidelines

### RunWhen Platform

- Follow RunWhen task patterns and conventions

- Support configurable task titles via `TASK_TITLE` variable for Digital Assistant discoverability

- Use consistent issue reporting formats (when applicable)

- Include proper portal links and navigation (when applicable)

- Provide meaningful next steps and reproduce hints based on command output

- Support both SLI (metrics) and TaskSet (reporting) use cases

### Cloud Provider APIs

- Use official SDKs and CLI tools

- Follow API best practices and rate limits

- Handle authentication and authorization properly

- Use appropriate resource naming and tagging

### Monitoring and Observability

- Include comprehensive logging

- Provide metrics and performance data

- Use appropriate alerting and notification

- Include health checks and status reporting

