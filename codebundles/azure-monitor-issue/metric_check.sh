#!/bin/bash


# ENV:
# JQ_EXPRESSION: jq expression to filter the metric, eg: .value[].timeseries[].data[-1].average < 80
# RESOURCE_UID: resource uid in azure
# METRIC_NAME: metric name to check, like 'Percentage CPU'
# METRIC_VALUE: metric value to check
# METRIC_TOP: top value to check
# METRIC_INTERVAL: interval to check
# METRIC_AGGREGATION: average
if [ -z "$JQ_EXPRESSION" ]; then
    echo "JQ_EXPRESSION is not set, defaulting to .value[].timeseries[].data[-1].average < 80"
    JQ_EXPRESSION=".value[].timeseries[].data[-1].average < 80"
fi
if [ -z "$RESOURCE_UID" ]; then
  echo "RESOURCE_UID is not set"
  exit 1
fi
if [ -z "$METRIC_NAME" ]; then
  echo "METRIC_NAME is not set, defaulting to 'Percentage CPU'"
  METRIC_NAME="Percentage CPU"
fi
if [ -z "$METRIC_TOP" ]; then
  echo "METRIC_TOP is not set, defaulting to 100"
  METRIC_TOP=100
fi
if [ -z "$METRIC_INTERVAL" ]; then
  echo "METRIC_INTERVAL is not set, defaulting to 5m"
  METRIC_INTERVAL=5m
fi
if [ -z "$METRIC_AGGREGATION" ]; then
  echo "METRIC_AGGREGATION is not set, defaulting to average"
  METRIC_AGGREGATION=average
fi
metric_json=$(az monitor metrics list --resource $RESOURCE_UID --metric "$METRIC_NAME" --interval 5m --aggregation $METRIC_AGGREGATION --top $METRIC_TOP)
echo "Metric Data:"
echo "$metric_json"
echo "Applying Expression: $JQ_EXPRESSION"
result=$(echo $metric_json | jq -r "$JQ_EXPRESSION")
echo "Got result: $result"
if [ "$result" != "true" ]; then
    echo "Metric check failed"
    exit 1
fi
echo "Metric check passed"
exit 0