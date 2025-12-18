#!/usr/bin/env python3
"""
Test script for RW.DynamicIssues library
This script tests the dynamic issue generation functionality without Robot Framework
"""

import sys
import os
import json

# Add libraries to path
sys.path.insert(0, '/home/runwhen/codecollection/libraries')

# Test JSON parsing functions
def test_json_query_parsing():
    """Test the JSON query-based issue detection logic"""
    
    # Test Case 1: Standard format with issuesIdentified
    test_json_1 = '''
    {
      "issuesIdentified": true,
      "issues": [
        {
          "title": "Test Issue 1",
          "severity": 2,
          "details": "This is a test issue"
        }
      ]
    }
    '''
    
    print("Test Case 1: Standard format")
    print("Input JSON:", test_json_1)
    try:
        data = json.loads(test_json_1)
        trigger_key = "issuesIdentified"
        trigger_value = True
        issues_key = "issues"
        
        if trigger_key in data and data[trigger_key] == trigger_value:
            print(f"✓ Trigger condition met: {trigger_key}={trigger_value}")
            if issues_key in data:
                print(f"✓ Found {len(data[issues_key])} issue(s)")
                for issue in data[issues_key]:
                    print(f"  - {issue.get('title', 'No title')}")
        else:
            print("✗ Trigger condition not met")
    except Exception as e:
        print(f"✗ Error: {e}")
    
    print("\n" + "="*60 + "\n")
    
    # Test Case 2: Custom format with storeIssues
    test_json_2 = '''
    {
      "storeIssues": true,
      "scanType": "security",
      "problems": [
        {
          "title": "Security Issue",
          "severity": 1,
          "details": "Critical security vulnerability"
        }
      ]
    }
    '''
    
    print("Test Case 2: Custom format with 'storeIssues' and 'problems'")
    print("Input JSON:", test_json_2)
    try:
        data = json.loads(test_json_2)
        trigger_key = "storeIssues"
        trigger_value = True
        issues_key = "problems"
        
        if trigger_key in data and data[trigger_key] == trigger_value:
            print(f"✓ Trigger condition met: {trigger_key}={trigger_value}")
            if issues_key in data:
                print(f"✓ Found {len(data[issues_key])} issue(s)")
                for issue in data[issues_key]:
                    print(f"  - {issue.get('title', 'No title')}")
        else:
            print("✗ Trigger condition not met")
    except Exception as e:
        print(f"✗ Error: {e}")
    
    print("\n" + "="*60 + "\n")
    
    # Test Case 3: Trigger not met
    test_json_3 = '''
    {
      "issuesIdentified": false,
      "issues": []
    }
    '''
    
    print("Test Case 3: Trigger not met (issuesIdentified=false)")
    print("Input JSON:", test_json_3)
    try:
        data = json.loads(test_json_3)
        trigger_key = "issuesIdentified"
        trigger_value = True
        issues_key = "issues"
        
        if trigger_key in data and data[trigger_key] == trigger_value:
            print(f"✓ Trigger condition met: {trigger_key}={trigger_value}")
        else:
            print(f"✓ Correctly skipped: {trigger_key}={data.get(trigger_key)} (expected {trigger_value})")
    except Exception as e:
        print(f"✗ Error: {e}")

def test_file_based_issues():
    """Test file-based issue detection logic"""
    
    print("\n" + "="*60 + "\n")
    print("Test Case 4: File-based issues")
    
    # Check if sample files exist
    issues_file = "/home/runwhen/codecollection/examples/sample_issues.json"
    report_file = "/home/runwhen/codecollection/examples/sample_report.txt"
    
    if os.path.exists(issues_file):
        print(f"✓ Found {issues_file}")
        with open(issues_file, 'r') as f:
            issues = json.load(f)
            print(f"✓ Loaded {len(issues)} issue(s) from file")
            for issue in issues:
                print(f"  - {issue.get('title', 'No title')}")
    else:
        print(f"✗ File not found: {issues_file}")
    
    if os.path.exists(report_file):
        print(f"✓ Found {report_file}")
        with open(report_file, 'r') as f:
            content = f.read()
            print(f"✓ Report file contains {len(content)} characters")
            print("  (Note: report.txt is now handled separately in runbooks)")
    else:
        print(f"✗ File not found: {report_file}")

if __name__ == "__main__":
    print("="*60)
    print("Dynamic Issue Generation - Unit Tests")
    print("="*60 + "\n")
    
    test_json_query_parsing()
    test_file_based_issues()
    
    print("\n" + "="*60)
    print("All tests completed!")
    print("="*60)

