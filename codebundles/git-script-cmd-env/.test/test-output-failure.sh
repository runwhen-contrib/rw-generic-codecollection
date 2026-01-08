#!/bin/bash
# Test script that outputs a metric but fails (tests METRIC_MODE=output with failure)
# Usage: METRIC_MODE=output SCRIPT_COMMAND="bash .test/test-output-failure.sh"

echo "99"
exit 1
