#!/bin/bash
# Sample script that outputs JSON with issues
# This demonstrates the JSON query-based issue generation

echo '{
  "issuesIdentified": true,
  "timestamp": "2025-12-17T10:30:00Z",
  "system": "production-cluster",
  "issues": [
    {
      "title": "Pod Restart Loop Detected",
      "severity": 2,
      "expected": "Pods should restart less than 3 times per hour",
      "actual": "Pod web-server-abc123 has restarted 15 times in the last hour",
      "reproduce_hint": "kubectl describe pod web-server-abc123 -n production",
      "next_steps": "1. Check pod logs for errors\n2. Review resource limits\n3. Investigate liveness/readiness probe configuration",
      "details": "Pod: web-server-abc123\nNamespace: production\nRestart Count: 15\nLast Restart: 2025-12-17T10:28:00Z"
    },
    {
      "title": "High Error Rate on API Endpoint",
      "severity": 3,
      "expected": "API error rate should be below 1%",
      "actual": "API error rate is 5.2% for /api/users endpoint",
      "reproduce_hint": "Check API logs and monitoring dashboard",
      "next_steps": "1. Review API logs for error patterns\n2. Check database connectivity\n3. Verify authentication service is working",
      "details": "Endpoint: /api/users\nError Rate: 5.2%\nTotal Requests: 10,000\nErrors: 520\nTime Window: Last 1 hour"
    }
  ]
}'

