#!/bin/bash
# Sample script with custom JSON keys
# This demonstrates flexible configuration for JSON query-based issue generation

echo '{
  "storeIssues": true,
  "checkType": "security-scan",
  "scanDate": "2025-12-17",
  "problems": [
    {
      "title": "Outdated Container Image Detected",
      "severity": 2,
      "expected": "All container images should be updated within 30 days",
      "actual": "Container nginx:1.18 is 180 days old",
      "reproduce_hint": "Review container image versions in deployment manifests",
      "next_steps": "1. Update to nginx:1.25 or later\n2. Test in staging environment\n3. Deploy to production",
      "details": "Image: nginx:1.18\nAge: 180 days\nCVE Count: 23\nSeverity: 3 High, 20 Medium"
    }
  ]
}'

