# Dynamic Issue Generation - Examples

This directory contains examples and documentation for dynamic issue generation in RunWhen codebundles.

## Quick Start

### Method 1: File-Based Issues (No Config Needed)

Create `issues.json` in your script (can be in any subdirectory):
```bash
# Can be in root or any subdirectory - searches recursively!
cat > $CODEBUNDLE_TEMP_DIR/issues.json << EOF
[
  {
    "title": "High CPU Usage",
    "severity": 2,
    "expected": "CPU below 80%",
    "actual": "CPU at 95%",
    "details": "CPU exceeded threshold for 15 minutes"
  }
]
EOF
```

**That's it!** Issues are created automatically.

### Method 2: JSON Query (Configurable)

**Step 1:** Configure your codebundle:
```yaml
ISSUE_JSON_QUERY_ENABLED: true
ISSUE_JSON_TRIGGER_KEY: issuesIdentified    # or your custom key
ISSUE_JSON_TRIGGER_VALUE: true              # or your custom value
ISSUE_JSON_ISSUES_KEY: issues               # or your custom key
```

**Step 2:** Output JSON from your command:
```bash
echo '{"issuesIdentified": true, "issues": [{"title": "Problem", "severity": 2}]}'
```

### Report Content

To add report content, create `report.txt` (can be in any subdirectory):
```bash
# Can be in root or any subdirectory - searches recursively!
cat > $CODEBUNDLE_TEMP_DIR/report.txt << EOF
System analysis completed.
Found 3 issues requiring attention.
EOF
```

## Configuration Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ISSUE_JSON_QUERY_ENABLED` | `false` | Enable JSON query method |
| `ISSUE_JSON_TRIGGER_KEY` | `issuesIdentified` | JSON key to check |
| `ISSUE_JSON_TRIGGER_VALUE` | `true` | Value that triggers issues |
| `ISSUE_JSON_ISSUES_KEY` | `issues` | Key containing issues array |
| `STDOUT_ISSUE_ENABLED` | `true` | Enable traditional stdout issues |
| `RETURNCODE_ISSUE_ENABLED` | `true` | Enable return code issues (git-script-cmd-env) |

## Issue JSON Format

All fields are optional except `title`:

```json
{
  "title": "Issue Title",           // Required
  "severity": 2,                     // 1=critical, 2=high, 3=medium, 4=info (default: 3)
  "expected": "What should happen",  // Default: "No issues should be present"
  "actual": "What actually happened",// Default: "Issue was detected"
  "reproduce_hint": "How to verify", // Default: "Review the issue details"
  "next_steps": "What to do",        // Default: "Investigate and resolve the issue"
  "details": "Additional info"       // Default: ""
}
```

## Examples

### Standard JSON Format
```bash
bash sample_json_output.sh
```
Uses: `issuesIdentified` → `issues`

### Custom JSON Format
```bash
bash sample_custom_json_output.sh
```
Uses: `storeIssues` → `problems`

Configure with:
```yaml
ISSUE_JSON_TRIGGER_KEY: storeIssues
ISSUE_JSON_ISSUES_KEY: problems
```

## Supported Codebundles

**Recommended (with full dynamic issue support):**
- `aws-cmd` ⭐
- `azure-cmd` ⭐
- `gcloud-cmd` ⭐
- `k8s-kubectl-cmd` ⭐
- `curl-cmd` ⭐
- `curl-headers-cmd` ⭐
- `git-script-cmd-json`
- `git-script-cmd-env`

**Legacy (simple stdout-based issues only):**
- `aws-stdout-issue` - For backward compatibility
- `azure-stdout-issue` - For backward compatibility
- `k8s-stdout-issue` - For backward compatibility
- `gcloud-stdout-issue` - For backward compatibility
- `curl-stdout-issue` - For backward compatibility
- `curl-headers-stdout-issue` - For backward compatibility

## Files in This Directory

**Documentation:**
- `README.md` - This file

**Examples:**
- `sample_issues.json` - File-based issues example
- `sample_report.txt` - Report content example
- `sample_json_output.sh` - Standard JSON query format
- `sample_custom_json_output.sh` - Custom JSON query format

**Testing:**
- `test_dynamic_issues.py` - Unit tests

Run tests:
```bash
python3 test_dynamic_issues.py
```

## Common Use Cases

### Use Case 1: Script with Complex Analysis
Your script analyzes the system and creates multiple issues:
```bash
#!/bin/bash
# Run analysis
results=$(analyze_system)

# Create issues.json with findings
cat > $CODEBUNDLE_TEMP_DIR/issues.json << EOF
[
  {"title": "Issue 1", "severity": 1},
  {"title": "Issue 2", "severity": 2}
]
EOF
```

### Use Case 2: Third-Party Tool Integration
Wrap a tool that outputs JSON:
```bash
# Tool outputs: {"hasErrors": true, "errors": [...]}
my_security_scanner --json

# Configure:
# ISSUE_JSON_TRIGGER_KEY=hasErrors
# ISSUE_JSON_ISSUES_KEY=errors
```

### Use Case 3: Simple + Dynamic
Use traditional method for failures, dynamic for details:
```bash
#!/bin/bash
# Traditional: script fails on error (return code creates issue)

# Dynamic: create detailed issues for warnings
if [ "$warnings" -gt 0 ]; then
    echo '{"issuesIdentified": true, "issues": [...]}'
fi
```

## Tips

💡 **Start Simple**: Use file-based issues first (no config needed)  
💡 **JSON Query**: Best for wrapping existing tools with JSON output  
💡 **Combine Methods**: All three methods work together  
💡 **Disable Traditional**: Set `STDOUT_ISSUE_ENABLED=false` to use only dynamic methods

## Need More Help?

- **Library Code**: `../libraries/RW/DynamicIssues.py`
- **Implementation Details**: `../IMPLEMENTATION_SUMMARY.md`
- **Sample Codebundles**: `../codebundles/*/runbook.robot`

## Quick Reference

**File-Based:**
```bash
# issues.json → creates issues (automatic)
# report.txt → adds to report (automatic)
```

**JSON Query:**
```bash
# Enable + configure → output JSON → issues created
```

**Traditional:**
```bash
# Non-empty stdout → issue (if enabled)
# Non-zero exit → issue (git-script-cmd-env, if enabled)
```
