# Grafana Loki Query

This CodeBundle queries Loki **via Grafana**, supporting relative times like `30m`, `2h`, or `2d` (auto-converted to the right epoch units). It runs in one of two modes via `QUERY_MODE`.

## Which mode should I use?

| Mode | API path | When to use |
|---|---|---|
| `proxy` *(default)* | `GET /api/datasources/proxy/{uid\|id}/loki/api/v1/query_range` | Default. Works on most Grafana installations. **Try this first.** |
| `ds_query` | `POST /api/ds/query` | Use if `proxy` fails — e.g. you see `tls: failed to verify certificate: x509: certificate signed by unknown authority` in Grafana logs while **Grafana Explore can run the same query**. This is the same API Explore uses, so it tends to behave like the UI. |

If `HEADERS` is provided, `-K ./HEADERS` is appended for authentication. If `POST_PROCESS` is provided, the output is piped to that command (e.g., `jq`).

`LOKI_QUERY` (and the JSON body in `ds_query` mode) is constructed in Python (`json.dumps`) and piped into `curl` via `base64 -d`, so LogQL containing quotes, backticks, `$`, or other shell-special characters is handled safely without manual escaping.

## Required variables

- `GRAFANA_URL` — base Grafana URL (e.g. `https://my-grafana.org`).
- `DATASOURCE_UID` — UID of your Loki datasource in Grafana. Easier to find than the numeric ID and stable across environments.
- `LOKI_QUERY` — Loki LogQL expression.
- `HEADERS` *(secret)* — file in cURL `-K` format with your auth header(s).

## Optional variables

- `QUERY_MODE` — `proxy` (default) or `ds_query`.
- `DATASOURCE_ID` — numeric datasource ID. Only used in `proxy` mode if explicitly set; otherwise the UID-based proxy URL is used.
- `LOKI_LIMIT` — `limit` in `proxy` mode, `maxLines` in `ds_query` mode (defaults to 100 in `ds_query` if unset).
- `LOKI_START` — relative time (`30m`, `2h`, `2d`) or absolute timestamp. Default `30m`.
- `LOKI_END` — relative or absolute. Empty = "now" (in `ds_query` mode this is sent as the current time).
- `POST_PROCESS` — command to pipe output to, e.g. `jq -r '.data.result[].values[][1]'`.
- `TASK_TITLE` — display name for the task.

## Example: `proxy` mode (default, UID-only config)

```bash
export GRAFANA_URL=https://mygrafana.company.net
export DATASOURCE_UID=logs-production
export LOKI_QUERY='{container="papi"}'
export LOKI_LIMIT=100
export LOKI_START=2h
```

`HEADERS` file:

```
header = "Authorization: Bearer GRAFANA_TOKEN"
header = "X-Grafana-Org-Id: 1"
```

## Example: `ds_query` mode (fallback when proxy TLS fails)

```bash
export QUERY_MODE=ds_query
export GRAFANA_URL=https://mygrafana.company.net
export DATASOURCE_UID=logs-production
export LOKI_QUERY='{container="papi"}'
export LOKI_LIMIT=100
export LOKI_START=2h
```

Use the same `HEADERS` file as above. `ds_query` mode hits the same API Grafana Explore uses, which is the recommended workaround when datasource-proxy TLS verification is failing on the Grafana → Loki hop while Explore itself works.
