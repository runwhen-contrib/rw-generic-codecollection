# Grafana Prometheus Query

Query a **Prometheus-compatible** datasource (Prometheus, **Mimir**, Cortex, Thanos, …) **via Grafana**, with relative times like `30m`, `2h`, `2d` (auto-converted to the right epoch units).

This is the metrics counterpart of [`grafana-loki-query`](../grafana-loki-query/README.md) and follows the same patterns: pick a `QUERY_MODE` (`proxy` / `ds_query`) plus a `QUERY_TYPE` (`range` / `instant`), provide your `DATASOURCE_UID` and PromQL, and you're done.

## Which mode should I use?

| Mode | API path | When to use |
|---|---|---|
| `proxy` *(default)* | `GET /api/datasources/proxy/{uid\|id}/api/v1/query[_range]` | Default. Works on most Grafana installations. **Try this first.** |
| `ds_query` | `POST /api/ds/query` | Use if `proxy` fails — e.g. you see `tls: failed to verify certificate: x509: certificate signed by unknown authority` in Grafana logs while **Grafana Explore can run the same query**. This is the same API Explore uses, so it tends to behave like the UI. |

## Range vs. instant

| `QUERY_TYPE` | Returns | Required time params |
|---|---|---|
| `range` *(default)* | A time series sampled at `PROM_STEP` between `PROM_START` and `PROM_END` | `PROM_START`, `PROM_END`, `PROM_STEP` |
| `instant` | A single evaluation at `PROM_END` (or "now" if empty) | `PROM_END` |

`PROMQL_QUERY` (and the JSON body in `ds_query` mode) is built with Python `json.dumps` and piped to `curl` via `base64 -d`, so PromQL containing quotes, braces, or other shell-special characters is handled safely without manual escaping.

If `HEADERS` is provided, `-K ./HEADERS` is appended for authentication. If `POST_PROCESS` is provided, the output is piped to that command (e.g., `jq`).

## Required variables

- `GRAFANA_URL` — base Grafana URL (e.g. `https://my-grafana.org`).
- `DATASOURCE_UID` — UID of your Prometheus / Mimir / Cortex / Thanos datasource.
- `PROMQL_QUERY` — PromQL expression.
- `HEADERS` *(secret)* — file in cURL `-K` format with your auth header(s).

## Optional variables

- `QUERY_MODE` — `proxy` (default) or `ds_query`.
- `QUERY_TYPE` — `range` (default) or `instant`.
- `DATASOURCE_ID` — numeric datasource ID. Only used in `proxy` mode if explicitly set; otherwise the UID-based proxy URL is used.
- `PROM_START` — relative (`30m`, `2h`, `2d`) or absolute. Default `1h`. Range only.
- `PROM_END` — relative or absolute. Empty = "now". For `instant` this is the evaluation time.
- `PROM_STEP` — sample resolution for range queries (`15s`, `30s`, `1m`). Default `15s`. Sent as-is in `proxy` mode; converted to `intervalMs` in `ds_query` mode.
- `POST_PROCESS` — command to pipe output to, e.g. `jq -r '.data.result[].metric'`.
- `TASK_TITLE` — display name for the task.

## Example: `proxy` + `range` (default)

```bash
export GRAFANA_URL=https://mygrafana.company.net
export DATASOURCE_UID=metrics-mimir
export PROMQL_QUERY='sum(rate(http_requests_total{job="api"}[5m])) by (status)'
export PROM_START=1h
export PROM_STEP=30s
```

`HEADERS` file:

```
header = "Authorization: Bearer GRAFANA_TOKEN"
header = "X-Grafana-Org-Id: 1"
```

## Example: `proxy` + `instant`

```bash
export QUERY_MODE=proxy
export QUERY_TYPE=instant
export GRAFANA_URL=https://mygrafana.company.net
export DATASOURCE_UID=metrics-mimir
export PROMQL_QUERY='up{job="api"}'
# PROM_END empty = "now"
```

## Example: `ds_query` (Explore-equivalent fallback)

```bash
export QUERY_MODE=ds_query
export QUERY_TYPE=range
export GRAFANA_URL=https://mygrafana.company.net
export DATASOURCE_UID=metrics-mimir
export PROMQL_QUERY='sum(rate(http_requests_total[5m]))'
export PROM_START=2h
export PROM_STEP=1m
```

`ds_query` mode hits the same API Grafana Explore uses, which is the recommended workaround when datasource-proxy TLS verification is failing on the Grafana → datasource hop while Explore itself works.

## Mimir notes

- Mimir requires the tenant (`X-Scope-OrgID`) header on direct calls, but when querying through Grafana the datasource configuration injects that automatically — no need to add it to `HEADERS`.
- Both `proxy` and `ds_query` modes work against Mimir without modification; it implements the standard Prometheus HTTP API at `/prometheus/api/v1/...`, but Grafana datasources of type `prometheus` strip/add the prefix as configured, so you address them the same way as a vanilla Prometheus.
