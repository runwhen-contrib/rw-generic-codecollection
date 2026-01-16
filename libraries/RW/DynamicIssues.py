"""
RW.DynamicIssues - Library for dynamically generating issues from files and JSON output

This library provides two methods for issue generation:
1. File-based: Check for issues.json and report.txt files
2. JSON query-based: Search for configurable patterns in JSON output

Author: RunWhen
"""

import json
import os
from robot.api import logger
from robot.libraries.BuiltIn import BuiltIn


class DynamicIssues:
    """Library for dynamically generating issues from multiple sources"""
    
    ROBOT_LIBRARY_SCOPE = 'GLOBAL'
    
    def __init__(self):
        self.builtin = BuiltIn()
    
    def process_file_based_issues(self, temp_dir=None, report_data=None):
        """
        Check for issues.json file and create issues from it.
        
        This method searches recursively for issues.json files under temp_dir
        and creates one issue per item found. This handles cases where users
        git clone repos and issues.json is in a subdirectory.
        
        Args:
            temp_dir: Directory to search for files (defaults to CODEBUNDLE_TEMP_DIR)
            report_data: Optional report data (stdout, stderr, history) to append to issue details
        
        Returns:
            Number of issues created
        """
        if temp_dir is None:
            temp_dir = os.environ.get('CODEBUNDLE_TEMP_DIR', '.')
        
        issues_created = 0
        
        # Search recursively for all issues.json files
        issues_files = []
        for root, dirs, files in os.walk(temp_dir):
            if 'issues.json' in files:
                issues_files.append(os.path.join(root, 'issues.json'))
        
        # Process each issues.json file found
        for issues_file in issues_files:
            try:
                with open(issues_file, 'r') as f:
                    issues_data = json.load(f)
                    
                    # Handle both list and single object
                    if isinstance(issues_data, dict):
                        issues_data = [issues_data]
                    
                    for issue in issues_data:
                        if isinstance(issue, dict):
                            # Create issue with provided fields or defaults
                            title = issue.get('title', 'Issue Detected')
                            severity = issue.get('severity', 3)
                            expected = issue.get('expected', 'No issues should be present')
                            actual = issue.get('actual', 'Issue was detected')
                            reproduce_hint = issue.get('reproduce_hint', 'Review the issue details')
                            next_steps = issue.get('next_steps', 'Investigate and resolve the issue')
                            details = issue.get('details', '')
                            
                            # Append report data if provided
                            if report_data:
                                if details:
                                    details = f"{details}\n\n--- Command Output ---\n{report_data}"
                                else:
                                    details = f"--- Command Output ---\n{report_data}"
                            
                            self.builtin.run_keyword(
                                'RW.Core.Add Issue',
                                f'title={title}',
                                f'severity={severity}',
                                f'expected={expected}',
                                f'actual={actual}',
                                f'reproduce_hint={reproduce_hint}',
                                f'next_steps={next_steps}',
                                f'details={details}'
                            )
                            issues_created += 1
                            logger.info(f"Created issue from {issues_file}: {title}")
                    
            except json.JSONDecodeError as e:
                logger.warn(f"Failed to parse {issues_file}: {str(e)}")
            except Exception as e:
                logger.warn(f"Failed to process {issues_file}: {str(e)}")
        
        if issues_files:
            logger.info(f"Processed {len(issues_files)} issues.json file(s), created {issues_created} issue(s)")
        
        return issues_created
    
    def process_json_query_issues(self, output_text, trigger_key, trigger_value, issues_key, report_data=None):
        """
        Search for configurable patterns in JSON output and create issues.
        
        This method searches for a trigger pattern (e.g., "issuesIdentified":"true")
        and then looks for an issues array/object under the specified key.
        
        Args:
            output_text: The text output to search (usually stdout)
            trigger_key: The JSON key to check (e.g., "issuesIdentified" or "storeIssues")
            trigger_value: The value that triggers issue creation (e.g., "true" or True)
            issues_key: The JSON key containing the issues list (e.g., "issues")
            report_data: Optional report data (stdout, stderr, history) to append to issue details
        
        Returns:
            Number of issues created
        """
        if not output_text or not output_text.strip():
            logger.info("No output text provided for JSON query processing")
            return 0
        
        issues_created = 0
        
        try:
            # Try to parse the entire output as JSON
            data = json.loads(output_text)
            
            # Convert trigger_value to appropriate type
            if isinstance(trigger_value, str):
                if trigger_value.lower() == 'true':
                    trigger_value = True
                elif trigger_value.lower() == 'false':
                    trigger_value = False
                else:
                    # Try to convert to number (int or float)
                    try:
                        # Try integer first
                        if '.' not in trigger_value:
                            trigger_value = int(trigger_value)
                        else:
                            trigger_value = float(trigger_value)
                    except ValueError:
                        # Keep as string if not a valid number
                        pass
            
            # Check if trigger condition is met
            if trigger_key in data and data[trigger_key] == trigger_value:
                logger.info(f"Trigger condition met: {trigger_key}={trigger_value}")
                
                # Look for issues
                if issues_key in data:
                    issues_data = data[issues_key]
                    
                    # Handle both list and single object
                    if isinstance(issues_data, dict):
                        issues_data = [issues_data]
                    
                    if isinstance(issues_data, list):
                        for issue in issues_data:
                            if isinstance(issue, dict):
                                # Create issue with provided fields or defaults
                                title = issue.get('title', 'Issue Detected from JSON Query')
                                severity = issue.get('severity', 3)
                                expected = issue.get('expected', 'No issues should be present')
                                actual = issue.get('actual', 'Issue was detected in output')
                                reproduce_hint = issue.get('reproduce_hint', 'Review the command output')
                                next_steps = issue.get('next_steps', 'Investigate and resolve the issue')
                                details = issue.get('details', json.dumps(issue, indent=2))
                                
                                # Append report data if provided
                                if report_data:
                                    if details:
                                        details = f"{details}\n\n--- Command Output ---\n{report_data}"
                                    else:
                                        details = f"--- Command Output ---\n{report_data}"
                                
                                self.builtin.run_keyword(
                                    'RW.Core.Add Issue',
                                    f'title={title}',
                                    f'severity={severity}',
                                    f'expected={expected}',
                                    f'actual={actual}',
                                    f'reproduce_hint={reproduce_hint}',
                                    f'next_steps={next_steps}',
                                    f'details={details}'
                                )
                                issues_created += 1
                                logger.info(f"Created issue from JSON query: {title}")
                    else:
                        logger.warn(f"Issues key '{issues_key}' does not contain a list or object")
                else:
                    logger.info(f"Trigger met but no '{issues_key}' key found in JSON output")
            else:
                logger.info(f"Trigger condition not met: {trigger_key} != {trigger_value}")
                    
        except json.JSONDecodeError:
            # Try to find JSON objects in the text
            logger.info("Output is not valid JSON, attempting to find JSON objects in text")
            issues_created = self._extract_json_from_text(output_text, trigger_key, trigger_value, issues_key, report_data)
        except Exception as e:
            logger.warn(f"Failed to process JSON query: {str(e)}")
        
        return issues_created
    
    def _extract_json_from_text(self, text, trigger_key, trigger_value, issues_key, report_data=None):
        """Helper method to extract JSON objects from text that may contain non-JSON content"""
        issues_created = 0
        
        # Look for JSON-like structures in the text
        lines = text.split('\n')
        for line in lines:
            line = line.strip()
            if line.startswith('{') or line.startswith('['):
                try:
                    data = json.loads(line)
                    
                    # Convert trigger_value to appropriate type
                    if isinstance(trigger_value, str):
                        if trigger_value.lower() == 'true':
                            trigger_value = True
                        elif trigger_value.lower() == 'false':
                            trigger_value = False
                        else:
                            # Try to convert to number (int or float)
                            try:
                                # Try integer first
                                if '.' not in trigger_value:
                                    trigger_value = int(trigger_value)
                                else:
                                    trigger_value = float(trigger_value)
                            except ValueError:
                                # Keep as string if not a valid number
                                pass
                    
                    # Check trigger condition
                    if isinstance(data, dict) and trigger_key in data and data[trigger_key] == trigger_value:
                        if issues_key in data:
                            issues_data = data[issues_key]
                            
                            if isinstance(issues_data, dict):
                                issues_data = [issues_data]
                            
                            if isinstance(issues_data, list):
                                for issue in issues_data:
                                    if isinstance(issue, dict):
                                        title = issue.get('title', 'Issue Detected from JSON Query')
                                        severity = issue.get('severity', 3)
                                        expected = issue.get('expected', 'No issues should be present')
                                        actual = issue.get('actual', 'Issue was detected in output')
                                        reproduce_hint = issue.get('reproduce_hint', 'Review the command output')
                                        next_steps = issue.get('next_steps', 'Investigate and resolve the issue')
                                        details = issue.get('details', json.dumps(issue, indent=2))
                                        
                                        # Append report data if provided
                                        if report_data:
                                            if details:
                                                details = f"{details}\n\n--- Command Output ---\n{report_data}"
                                            else:
                                                details = f"--- Command Output ---\n{report_data}"
                                        
                                        self.builtin.run_keyword(
                                            'RW.Core.Add Issue',
                                            f'title={title}',
                                            f'severity={severity}',
                                            f'expected={expected}',
                                            f'actual={actual}',
                                            f'reproduce_hint={reproduce_hint}',
                                            f'next_steps={next_steps}',
                                            f'details={details}'
                                        )
                                        issues_created += 1
                                        logger.info(f"Created issue from extracted JSON: {title}")
                except json.JSONDecodeError:
                    continue
                except Exception as e:
                    logger.debug(f"Error processing line as JSON: {str(e)}")
                    continue
        
        return issues_created

