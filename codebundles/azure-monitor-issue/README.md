# Azure Monitor Metric Issue Detection
A generic codebundle used for fetching and checking a Azure Monitor metric value in a timeseries and raising an issue if it's not the expected value.

## TaskSet
Checks a general azure monitor metric and raises an issue when it doesn't match the expected value indicated by an operand and value.


## SLI
Similar to the taskset, except a 0 is raised when the value is not within the expected range, and 1 (healthy) when it's within the expected range.
