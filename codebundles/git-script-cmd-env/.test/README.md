# Test Scripts for git-script-cmd-env

These are simple test scripts to validate the METRIC_MODE functionality.

## Test Cases

### 1. Output Mode - Success
Tests parsing metric from stdout with successful execution:
```bash
METRIC_MODE=output
SCRIPT_COMMAND="bash codebundles/git-script-cmd-env/.test/test-output-mode.sh"
```
Expected: Metric value of 42, no issues

### 2. Output Mode - With Failure
Tests parsing metric from stdout with failed execution:
```bash
METRIC_MODE=output
SCRIPT_COMMAND="bash codebundles/git-script-cmd-env/.test/test-output-failure.sh"
```
Expected: Metric value of 99, issue raised for failed execution

### 3. Returncode Mode - Success
Tests default returncode-based metric (success):
```bash
METRIC_MODE=returncode
SCRIPT_COMMAND="bash codebundles/git-script-cmd-env/.test/test-returncode-mode.sh"
```
Expected: Metric value of 1, no issues

### 4. Returncode Mode - Failure
Tests default returncode-based metric (failure):
```bash
METRIC_MODE=returncode
SCRIPT_COMMAND="false"
```
Expected: Metric value of 0, issue raised

## Running Tests

Set the user variables in your RunWhen platform configuration:
- `SCRIPT_COMMAND`: Path to test script
- `METRIC_MODE`: Either `returncode` (default) or `output`
- `TASK_TITLE`: Descriptive name for the test

Execute the SLI task and verify the metric is pushed correctly.
