# Grafana Loki Query
This CodeBundle queries Loki (via Grafana) using relative times like 30m, 2h, or 2d, which are automatically converted to nanosecond timestamps. If HEADERS is provided, '-K ./HEADERS' is appended for authentication. If POST_PROCESS is provided, the command output is piped to that command (e.g., jq).


export GRAFANA_URL=https://mygrafana.company.net
export DATASOURCE_UID=logs-production
export LOKI_QUERY='{container="papi"}'
export LOKI_LIMIT=100
export LOKI_START=2h
