#!/usr/bin/env python
"""
This file is intended as the primary executable on a codebundle container running
in one of our locations. It runs a .robot file (e.g., sli.robot or runbook.robot),
logs results, and pushes metrics to OTEL or (fallback) to the Prometheus Pushgateway.
"""

import robot
import requests
import os, sys, argparse, configparser, shlex, subprocess, time, traceback, json, datetime, re
from xml.dom import minidom
import http.server, socketserver
import socket
from urllib.parse import urlparse
import signal
import atexit
import hashlib

from RW import platform, fetchsecrets
import logging

logger = logging.getLogger(__name__)

# Import process metrics instead of runtime metrics server
try:
    from process_metrics import init_process_metrics, record_cleanup_metrics, finalize_process_metrics, get_process_metrics_recorder
    PROCESS_METRICS_AVAILABLE = True
except ImportError:
    PROCESS_METRICS_AVAILABLE = False
    logger.warning("Process metrics not available")



APP_NAME = "runrobot"
APP_VERSION = "v1"

logging.basicConfig(
    format="%(json_formatted)s",
    level=logging.DEBUG,
    handlers=[
        logging.StreamHandler(sys.stdout),
    ],
)

# Record factory for structured logging
_record_factory_bak = logging.getLogRecordFactory()
def record_factory(*args, **kwargs) -> logging.LogRecord:
    record = _record_factory_bak(*args, **kwargs)
    record_obj = {
        "level": record.levelname,
        "unixtime": record.created,
        "thread": record.thread,
        "location": f"{record.pathname}:{record.funcName}:{record.lineno}",
        "app": {
            "name": APP_NAME,
            "releaseId": APP_VERSION,
            "message": str(record.getMessage()),
        },
    }
    if record.exc_info:
        try:
            record_obj["exception"] = record.exc_info
            record_obj["traceback"] = traceback.format_exception(*record.exc_info)
        except TypeError:
            # Handle the case where traceback contains non-serializable objects
            record_obj["traceback"] = str(record.exc_info)
    
    try:
        record.json_formatted = json.dumps(record_obj)
    except TypeError:
        # Fallback if JSON serialization fails
        simplified_obj = {
            "level": record.levelname,
            "message": f"Error formatting log: {str(record.getMessage())}",
            "error": "Log contains non-serializable objects"
        }
        record.json_formatted = json.dumps(simplified_obj)

    # Prevent duplication from logging.exception
    record.exc_info = None
    record.exc_text = None
    return record
logging.setLogRecordFactory(record_factory)


# ----------------------------------------------------------------
# OTEL & Pushgateway references
# ----------------------------------------------------------------
from opentelemetry import metrics
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter

# Track whether OTEL is initialized
_otel_enabled = False
_otel_endpoint = None
_otel_provider = None
_otel_meter = None

# Metric types
GAUGE = "gauge"
COUNTER = "counter"
HISTOGRAM = "histogram"
UNTYPED = "untyped"

# ----------------------------------------------------------------
# Process Management / Cleanup
# ----------------------------------------------------------------

import psutil, signal, atexit

def _kill_descendants(sig=signal.SIGTERM, timeout=5.0):
    """
    Send *sig* to every child / grand‑child of this Python process
    and wait up to *timeout* s for them to vanish.
    Enhanced with metrics collection for cleanup operations.
    """
    cleanup_start = time.time()
    parent = psutil.Process()          # == current process
    children = parent.children(recursive=True)
    
    if not children:
        return

    for p in children:
        try:
            p.send_signal(sig)
        except psutil.NoSuchProcess:
            pass

    gone, alive = psutil.wait_procs(children, timeout=timeout)
    
    # Record cleanup metrics if available
    if PROCESS_METRICS_AVAILABLE:
        success_count = len(gone)
        failed_count = len(alive)
        duration = time.time() - cleanup_start
        record_cleanup_metrics(success_count, failed_count, duration)
    
    for p in alive:                    # still running?  shoot to kill.
        try:
            p.kill()
        except psutil.NoSuchProcess:
            pass
atexit.register(_kill_descendants, sig=signal.SIGKILL)


def check_platform_rvars():
    """Check to make sure that the platform-provided vars are all in the environment."""
    platform_var_names = [
        "RW_SLX_API_URL",
        "RW_WORKSPACE",
        "RW_WORKSPACE_API_URL",
        "RW_USER_API_URL",
        "RW_SECRETS_API_URL",
    ]
    ret = []
    for pvn in platform_var_names:
        pvval = os.getenv(pvn)
        if not pvval:
            raise AssertionError(pvn + " not found in the environment")
        ret.append(pvn + ":" + pvval)
    return ret

def init_otel():
    """
    Initialize OTEL pipeline only once, if environment variable is present
    or fallback to http://otel-collector:4318/v1/metrics, and if the hostname
    is resolvable. Otherwise skip OTEL.
    """
    global _otel_enabled, _otel_endpoint, _otel_provider, _otel_meter

    otel_endpoint = os.environ.get("RW_OTEL_COLLECTOR_ENDPOINT", "").strip()
    if not otel_endpoint:
        # Fallback to default
        otel_endpoint = "http://otel-collector:4318/v1/metrics"

    if not _is_collectord_host_resolvable(otel_endpoint):
        logger.debug(f"OTEL endpoint {otel_endpoint} not resolvable. Skipping OTEL init.")
        return  # OTEL remains disabled

    try:
        resource = Resource.create({"service.name": "rw_sli_service"})
        # Add timeout to the exporter
        exporter = OTLPMetricExporter(
            endpoint=otel_endpoint,
            timeout=5.0  # 5 second timeout
        )
        # Shorter export interval for quicker detection of issues
        reader = PeriodicExportingMetricReader(
            exporter, 
            export_interval_millis=10_000,
            export_timeout_millis=5_000  # 5 second timeout
        )

        provider = MeterProvider(resource=resource, metric_readers=[reader])
        metrics.set_meter_provider(provider)

        _otel_provider = provider
        _otel_meter = metrics.get_meter("rw_sli_meter")
        _otel_endpoint = otel_endpoint
        _otel_enabled = True
        logger.debug(f"Successfully initialized OTEL with endpoint: {otel_endpoint}")
    except Exception as ex:
        logger.warning(f"Error during OTEL init with endpoint {otel_endpoint}: {ex}")
        _otel_enabled = False


def _is_collectord_host_resolvable(endpoint: str) -> bool:
    """
    Quick check to see if the hostname in `endpoint` is resolvable.
    """
    parsed = urlparse(endpoint)
    if not parsed.hostname:
        logger.debug(f"Cannot parse a hostname from OTEL endpoint: {endpoint}")
        return False
    try:
        socket.gethostbyname(parsed.hostname)
        return True
    except Exception as ex:
        logger.debug(
            f"Failed to resolve hostname '{parsed.hostname}' from OTEL endpoint '{endpoint}': {ex}"
        )
        return False


def push_platform_metric(name, value, metric_type, description="a platform metric", **kwargs):
    """
    A method to push SLX-specific metrics relevant at the platform level. This version:
      - First tries OTEL (if initialized),
      - If OTEL is disabled or fails, falls back to Pushgateway.

    Use kwargs to add labels. The 'workspace' and 'robot_type' are appended automatically.
    """
    labels = kwargs if kwargs else {}

    slx_name = os.getenv("RW_SLX")
    workspace_name = os.getenv("RW_WORKSPACE")
    if not slx_name or not workspace_name:
        raise AssertionError(
            f"Expected RW_SLX and RW_WORKSPACE in env vars, but found {slx_name} and {workspace_name}"
        )

    # Must have a 'robot_type' from env
    robot_type = os.getenv("RW_RFNS")
    if not robot_type:
        raise AssertionError(f"Expected RW_RFNS in env vars, but found {robot_type}")

    # Build full metric name
    # for example, "my-slx__platform__my_metric"
    safe_slx_name = slx_name.replace("-", "_")
    full_name = f"{safe_slx_name}__platform__{name}"

    # Required labels
    labels["workspace"] = workspace_name
    labels["robot_type"] = robot_type

    # Attempt OTEL first
    if _otel_enabled and _otel_meter:
        try:
            push_platform_metric_otel(full_name, value, metric_type, description, labels=labels)
            return
        except Exception as ex:
            logger.warning(f"Error pushing metric to OTEL: {ex}. Falling back to pushgateway.")

    # Fallback
    push_platform_metric_pushgateway(full_name, value, metric_type, description, labels=labels)

def push_platform_metric_otel(name, value, metric_type, description="a platform metric", labels=None):
    """
    Record the metric in OTEL. We create or retrieve an instrument based on metric_type.
    """
    if labels is None:
        labels = {}

    # Create or retrieve a Counter / UpDownCounter
    if metric_type == COUNTER:
        metric = _otel_meter.create_counter(name)
        metric.add(value, attributes=labels)
    else:
        # Default to Gauge
        metric = _otel_meter.create_gauge(name)
        metric.set(value, attributes=labels)

    # Optional immediate flush
    # _otel_provider.force_flush()

    logger.info(
        f"Push platform metric to OTEL (endpoint={_otel_endpoint}): name={name}, "
        f"value={value}, labels={labels}, type={metric_type}"
    )


def push_platform_metric_pushgateway(name, value, metric_type, description="a platform metric", labels=None):
    """
    Original logic for pushing a metric to the Prometheus Pushgateway.
    """
    if labels is None:
        labels = {}

    pgh = os.getenv("RW_PUSHGWY_HOST")
    if not pgh:
        raise AssertionError(f"Expected RW_PUSHGWY_HOST in env vars, but found {pgh}")

    label_str = ",".join(f'{key}="{val}"' for (key, val) in labels.items())
    data = (
        f"# TYPE {name} {metric_type}\n"
        f"# HELP {name} {description}\n"
        f"{name}{{{label_str}}} {value}\n"
    )
    headers = {"Content-Type": "application/octet-stream"}
    job_name = "pushgateway"
    url = f"http://{pgh}/metrics/job/{job_name}/"
    rsp = requests.post(url=url, data=data, headers=headers)
    if not rsp.status_code == 200:
        raise AssertionError(f"Pushgateway post to {url} expected 200 but got {rsp.status_code}: {rsp.text}")
    logger.debug(f"Falling back to Pushgateway: name={name}, value={value}, labels={labels}, type={metric_type}")



def push_platform_metric_timestamp(name, description="a platform metric", **kwargs):
    """
    Push a UTC-timestamp-style metric (appends "_utc_timestamp" to the name).
    """
    push_platform_metric(
        name + "_utc_timestamp",
        datetime.datetime.utcnow().timestamp(),
        COUNTER,  # typically a monotonic gauge, but can store as counter
        description,
        **kwargs
    )

def push_platform_metric_elapsed_seconds(name, start_time, description, **kwargs):
    """
    Calculates the seconds since start_time (a datetime) and pushes the result.
    Appends "_elapsed_seconds" to the metric name.
    """
    elapsed = (datetime.datetime.now() - start_time).total_seconds()
    push_platform_metric(
        name + "_elapsed_seconds",
        elapsed,
        GAUGE,
        description,
        **kwargs
    )

def read_file_contents(file_path):
    """Read the contents of a file and return them as a string."""
    with open(file_path, "r", encoding="utf-8") as f:
        return f.read()


def post_results(
    logs_path, passed_titles=[], failed_titles=[], skipped_titles=[], exceptions=[]
):
    """Post the files found at logs_path back to the platform using the authenticated session"""
    # Read the contents of standard robot output files to strings (they are short)
    # Note the log.html and output.xml files may not be generated if there were exceptions, so
    # Treat them as optional.  The stdout file, however, may have useful exception info and is
    # required
    filenames = ["log.html", "stdout.txt", "report.jsonl", "issues.jsonl", "pip_install.log"]
    file_urls = {}
    try:
        run_request_id = platform.import_platform_variable("RW_RUNREQUEST_ID")
    except ImportError:  # this is the case when we have an SLI that has no runrequestid
        run_request_id = None

    for filename in filenames:
        file_path = os.path.join(logs_path, filename)
        is_file = os.path.isfile(file_path)

        # If report.jsonl or issues.jsonl do not exist, create and upload them with a single empty JSON object
        # TODO: This might be worth extending to make sure log.html and stdout.txt get uploaded.
        if filename in ["report.jsonl", "issues.jsonl"] and not is_file:
            contents = "{}\n"
        elif is_file:
            contents = read_file_contents(file_path)
        else:
            continue

        pf = f"{run_request_id}/" if run_request_id else ""
        try:
            platform.upload_session_file(f"{pf}{filename}", contents)
            get_url = platform.url_for_session_file(f"{pf}{filename}")
            file_urls[filename] = get_url
        except requests.exceptions.RequestException as re:
            exceptions.append(re)

    err_strs = []
    for e in exceptions:
        err_str = "\n".join(traceback.format_exception(type(e), e, e.__traceback__))
        err_str = err_str.replace("||", r"\|\|")
        err_strs.append(err_str)

    # Escape any || as we use this char combination as a separator
    passed_titles = [p.replace("||", r"\|\|") for p in passed_titles]
    failed_titles = [p.replace("||", r"\|\|") for p in failed_titles]
    skipped_titles = [p.replace("||", r"\|\|") for p in skipped_titles]

    data = {
        "robot_log_file": file_urls.get("log.html", "failed to read/upload"),
        "robot_stdout_file": file_urls.get("stdout.txt", "failed to read/upload"),
        "report_file": file_urls.get("report.jsonl", "failed to read/upload"),
        "issues_file": file_urls.get("issues.jsonl", "failed to read/upload"),
        "pip_install_file": file_urls.get("pip_install.log", ""),
        "passed_titles": "||".join(passed_titles),
        "failed_titles": "||".join(failed_titles),
        "skipped_titles": "||".join(skipped_titles),
        "errors": "||".join(err_strs),
    }
    url = os.getenv("RW_RUNRESULT_API_URL", None)
    if url:
        rsp = platform.get_authenticated_session().patch(
            url=url, json=data, verify=platform.REQUEST_VERIFY
        )
        logger.info(
            f"posted results back to platform, response: {rsp.text}, posted results: {data}"
        )

# Implemented robot listener interface to fish out results without parsing the entire xml file afterwards
# see https://robotframework.org/robotframework/latest/RobotFrameworkUserGuide.html#modifying-execution-and-results
class RobotResultsListener(object):
    ROBOT_LISTENER_API_VERSION = 3
    def __init__(self):
        self.ROBOT_LIBRARY_LISTENER = self
        self.test_passed_titles = []
        self.test_failed_titles = []
        self.test_skipped_titles = []

    def end_test(self, data, result):
        if result.passed:
            self.test_passed_titles.append(data.name)
        elif result.skipped:
            self.test_skipped_titles.append(data.name)
        elif result.failed:
            self.test_failed_titles.append(data.name)


def find_file(*paths):
    """Helper function to check if a file exists in the given paths."""
    for path in paths:
        if os.path.isfile(path):
            return path
    return None


def resolve_path_to_robot():
    # Environment variables
    runwhen_home = os.getenv("RUNWHEN_HOME", "").rstrip("/")
    home = os.getenv("HOME", "").rstrip("/")

    # Get the path to the robot file, ensure it's clean for concatenation
    repo_path_to_robot = os.getenv("RW_PATH_TO_ROBOT", "").lstrip("/")

    # Check if the path includes environment variable placeholders
    if "$(RUNWHEN_HOME)" in repo_path_to_robot:
        repo_path_to_robot = repo_path_to_robot.replace("$(RUNWHEN_HOME)", runwhen_home)
    if "$(HOME)" in repo_path_to_robot:
        repo_path_to_robot = repo_path_to_robot.replace("$(HOME)", home)

    # Prepare a list of paths to check
    paths_to_check = set(
        [
            os.path.join("/", repo_path_to_robot),  # Check as absolute path
            os.path.join(
                runwhen_home, repo_path_to_robot
            ),  # Path relative to RUNWHEN_HOME
            os.path.join(
                runwhen_home, "collection", repo_path_to_robot
            ),  # Further nested within RUNWHEN_HOME
            os.path.join(home, repo_path_to_robot),  # Path relative to HOME
            os.path.join(
                home, "collection", repo_path_to_robot
            ),  # Further nested within HOME
            os.path.join("/collection", repo_path_to_robot),  # Common collection path
        ]
    )

    # Try to find the file in any of the specified paths
    file_path = find_file(*paths_to_check)
    if file_path:
        return file_path

    # Final fallback to a default robot file or raise an error
    default_robot_file = os.path.join("/", "sli.robot")  # Default file path
    if os.path.isfile(default_robot_file):
        return default_robot_file

    raise FileNotFoundError("Could not find the robot file in any known locations.")

logger = logging.getLogger(__name__)

def _generate_credential_context_hash():
    """Generate a hash representing the current credential context.
    
    This ensures that different credential configurations (different Azure tenants,
    service principals, vault instances, etc.) get isolated cache directories.
    """
    context_data = []
    
    # Get secrets configuration to determine credential context
    secrets_keys_str = os.getenv('RW_SECRETS_KEYS', '{}')
    try:
        secrets_config = json.loads(secrets_keys_str)
    except json.JSONDecodeError:
        secrets_config = {}
    
    # Add relevant environment variables that affect credential context
    context_vars = [
        'RW_WORKSPACE',
        'RW_LOCATION', 
        'RW_VAULT_ADDR',
        'RW_VAULT_APPROLE_ROLE_ID',
        'RW_LOCATION_VAULT_AUTH_MOUNT_POINT'
    ]
    
    for var in context_vars:
        value = os.getenv(var, '')
        if value:
            context_data.append(f"{var}={value}")
    
    # Analyze secrets to identify credential-affecting patterns
    azure_contexts = []
    gcp_contexts = []
    aws_contexts = []
    custom_vault_contexts = []
    
    # Handle case where secrets_config might be a list or empty
    if not isinstance(secrets_config, dict):
        logger.info(f"No secrets configuration provided or invalid format, using default context")
        secrets_config = {}
    
    for secret_name, secret_key in secrets_config.items():
        if isinstance(secret_key, str):
            # Check for Azure contexts
            if 'azure:sp' in secret_key:
                # Azure Service Principal - extract resource info for context
                azure_contexts.append(f"azure_sp_{secret_key}")
            elif 'azure:identity' in secret_key:
                # Azure Managed Identity - extract resource info for context  
                azure_contexts.append(f"azure_identity_{secret_key}")
            elif 'az_clientId' in secret_name or 'az_tenantId' in secret_name:
                # Different Azure service principals should have different contexts
                if 'az_tenantId' in secret_name:
                    # This is a tenant ID - it defines a unique Azure context
                    azure_contexts.append(f"azure_tenant_{secret_key}")
                elif 'az_clientId' in secret_name:
                    # This is a client ID - it defines a unique Azure context
                    azure_contexts.append(f"azure_client_{secret_key}")
            
            # Check for GCP contexts
            if 'gcp:sa' in secret_key:
                # GCP Service Account - extract resource info for context
                gcp_contexts.append(f"gcp_sa_{secret_key}")
            elif 'gcp:adc' in secret_key:
                # GCP Application Default Credentials - extract resource info for context  
                gcp_contexts.append(f"gcp_adc_{secret_key}")
            elif 'gcp_projectId' in secret_name or 'gcp_serviceAccountKey' in secret_name:
                # Different GCP service accounts should have different contexts
                if 'gcp_projectId' in secret_name:
                    # This is a project ID - it defines a unique GCP context
                    gcp_contexts.append(f"gcp_project_{secret_key}")
                elif 'gcp_serviceAccountKey' in secret_name:
                    # This is a service account key - it defines a unique GCP context
                    gcp_contexts.append(f"gcp_sa_key_{secret_key}")
            
            # Check for AWS contexts
            if 'aws:irsa' in secret_key:
                aws_contexts.append(f"aws_irsa_{secret_key}")
            elif 'aws:access_key' in secret_key:
                aws_contexts.append(f"aws_access_key_{secret_key}")
            elif 'aws:assume_role' in secret_key:
                aws_contexts.append(f"aws_assume_role_{secret_key}")
            elif 'aws:default' in secret_key:
                aws_contexts.append(f"aws_default_{secret_key}")
            elif 'aws:workload_identity' in secret_key:
                aws_contexts.append(f"aws_workload_identity_{secret_key}")
            elif 'aws:cli' in secret_key:
                aws_contexts.append(f"aws_cli_{secret_key}")
            elif 'AWS_ACCESS_KEY_ID' in secret_name or 'AWS_ROLE_ARN' in secret_name:
                if 'AWS_ROLE_ARN' in secret_name:
                    aws_contexts.append(f"aws_role_{secret_key}")
                elif 'AWS_ACCESS_KEY_ID' in secret_name:
                    aws_contexts.append(f"aws_access_key_{secret_key}")
            
            # Check for custom vault contexts
            if '@' in secret_key and secret_key.split('@')[0] not in ['azure:identity', 'azure:sp', 'gcp:adc', 'gcp:sa', 'aws:irsa', 'aws:access_key', 'aws:assume_role', 'aws:default', 'aws:workload_identity', 'aws:cli', 'k8s:file', 'k8s:env', 'file', 'env']:
                # This is a custom provider
                provider = secret_key.split('@')[0]
                custom_vault_contexts.append(f"custom_vault_{provider}")
    
    # Add Azure contexts (deduplicated)
    for azure_context in set(azure_contexts):
        context_data.append(azure_context)
    
    # Add GCP contexts (deduplicated)
    for gcp_context in set(gcp_contexts):
        context_data.append(gcp_context)
    
    # Add AWS contexts (deduplicated)
    for aws_context in set(aws_contexts):
        context_data.append(aws_context)
    
    # Add custom vault contexts (deduplicated)  
    for vault_context in set(custom_vault_contexts):
        context_data.append(vault_context)
    
    # Sort for deterministic hashing
    context_data.sort()
    context_string = '|'.join(context_data)
    
    # Generate hash
    if context_string:
        context_hash = hashlib.sha256(context_string.encode()).hexdigest()[:12]  # 12 chars for readability
    else:
        context_hash = "default"
    
    logger.info(f"Generated credential context hash: {context_hash} from context: {context_string[:100]}...")
    return context_hash


def register_cleanup_for_execution_dir():
    """Register cleanup for execution-specific temporary directories"""
    execution_tmpdir = os.environ.get("RW_EXECUTION_TMPDIR")
    if execution_tmpdir and os.path.exists(execution_tmpdir):
        def cleanup_execution_dir():
            # Check if debug mode is enabled to keep artifacts
            if os.environ.get("RW_DEBUG_KEEP_ARTIFACTS") == "true":
                logger.info(f"DEBUG MODE: Python cleanup skipped - keeping execution directory {execution_tmpdir}")
                logger.info(f"DEBUG MODE: Artifacts preserved for debugging at: {execution_tmpdir}")
                logger.info(f"DEBUG MODE: To manually cleanup later, run: rm -rf {execution_tmpdir}")
                return
                
            try:
                import shutil
                logger.info(f"Python cleanup: removing execution directory {execution_tmpdir}")
                shutil.rmtree(execution_tmpdir, ignore_errors=True)
                logger.info(f"Python cleanup: completed for {execution_tmpdir}")
            except Exception as e:
                logger.warning(f"Python cleanup: failed to remove {execution_tmpdir}: {e}")
        
        atexit.register(cleanup_execution_dir)
        
        if os.environ.get("RW_DEBUG_KEEP_ARTIFACTS") == "true":
            logger.info(f"DEBUG MODE: Cleanup disabled - execution directory will be preserved: {execution_tmpdir}")
        else:
            logger.info(f"Registered Python cleanup for execution directory: {execution_tmpdir}")

def set_runwhen_workdir():
    """
    Creates working directories for runwhen-based tasks and sets environment variables.
    
    For credential caching efficiency, authentication state directories (Azure, gcloud) 
    are SHARED across codebundle executions but ISOLATED by credential context to prevent
    different credentials from interfering with each other.

    Returns:
        dict: containing the paths that were set
            {
                "RUNWHEN_WORKDIR": <execution-specific top-level directory>,
                "AZURE_CONFIG_DIR": <context-specific azure config dir for credential caching>,
                "CLOUDSDK_CONFIG": <context-specific gcloud config dir for credential caching>,
                "AWS_CONFIG_DIR": <context-specific aws config dir for credential caching>,
                "CODEBUNDLE_TEMP_DIR": <execution-specific temp dir>,
                "KUBECONFIG": <execution-specific kubeconfig>,
            }
    """
    try:
        # 1) Try to get execution-specific directory first
        execution_tmpdir = os.environ.get("RW_EXECUTION_TMPDIR")
        
        if execution_tmpdir:
            # Use execution-specific directory structure
            runwhen_workdir = os.path.join(execution_tmpdir, "workdir")
            logger.info("Using execution-specific directory structure based on RW_EXECUTION_TMPDIR")
        else:
            # Fallback to legacy behavior with enhanced hierarchical scoping
            slx = os.environ.get("RW_SLX", "unknown_slx")
            rfns = os.environ.get("RW_RFNS", "unknown_rfns")
            tmpdir = os.environ.get("TMPDIR", "/tmp/runwhen")
            
            # Build hierarchical path: session_id/runrequest_id
            session_id = None
            runrequest_id = None
            
            try:
                session_id = platform.import_platform_variable("RW_SESSION_ID")
                logger.info(f"Using session ID for scoping: {session_id}")
            except ImportError:
                session_id = f"session-{slx}-{rfns}"
                logger.info(f"No session ID available, generated: {session_id}")
                
            try:
                runrequest_id = platform.import_platform_variable("RW_RUNREQUEST_ID")
                logger.info(f"Using runrequest ID for scoping: {runrequest_id}")
            except ImportError:
                import time
                runrequest_id = f"runreq-{int(time.time())}"
                logger.info(f"No runrequest ID available, generated: {runrequest_id}")
            
            # Create hierarchical scoped directory: session_id/runrequest_id
            execution_scope = os.path.join(session_id, runrequest_id)
            runwhen_workdir = os.path.join(tmpdir, "scoped", execution_scope)

        os.makedirs(runwhen_workdir, exist_ok=True)
        logger.info("RUNWHEN_WORKDIR set to: %s", runwhen_workdir)

        # 2) Create shared vs execution-specific directories
        tmpdir_base = os.environ.get("TMPDIR", "/tmp/runwhen")
        shared_config_dir = os.path.join(tmpdir_base, "shared_config")
        
        # Generate credential context hash for isolation
        credential_context = _generate_credential_context_hash()
        context_specific_config_dir = os.path.join(shared_config_dir, credential_context)
        
        # SHARED directories for credential caching (isolated by credential context)
        azure_config_dir = os.path.join(context_specific_config_dir, ".azure")
        os.makedirs(azure_config_dir, exist_ok=True)

        gcloud_config_dir = os.path.join(context_specific_config_dir, ".gcloud")
        os.makedirs(gcloud_config_dir, exist_ok=True)

        aws_config_dir = os.path.join(context_specific_config_dir, ".aws")
        os.makedirs(aws_config_dir, exist_ok=True)

        # EXECUTION-SPECIFIC directories for temporary files
        codebundle_temp_dir = os.path.join(runwhen_workdir, "cb-temp")
        os.makedirs(codebundle_temp_dir, exist_ok=True)
        
        kube_config_dir = os.path.join(runwhen_workdir, ".kube")
        os.makedirs(kube_config_dir, exist_ok=True)
        kubeconfig_path = os.path.join(kube_config_dir, "config")

        # 3) Set environment variables
        #    - Azure CLI (SHARED for credential caching, isolated by context)
        os.environ["AZURE_CONFIG_DIR"] = azure_config_dir
        logger.info("AZURE_CONFIG_DIR set to CONTEXT-SPECIFIC directory: %s", azure_config_dir)

        #    - gcloud CLI (SHARED for credential caching, isolated by context)
        os.environ["CLOUDSDK_CONFIG"] = gcloud_config_dir
        logger.info("CLOUDSDK_CONFIG set to CONTEXT-SPECIFIC directory: %s", gcloud_config_dir)

        #    - AWS CLI (SHARED for credential caching, isolated by context)
        os.environ["AWS_CONFIG_DIR"] = aws_config_dir
        os.environ["AWS_CONFIG_FILE"] = os.path.join(aws_config_dir, "config")
        os.environ["AWS_SHARED_CREDENTIALS_FILE"] = os.path.join(aws_config_dir, "credentials")
        logger.info("AWS_CONFIG_DIR set to CONTEXT-SPECIFIC directory: %s", aws_config_dir)

        #    - codebundle temp
        os.environ["CODEBUNDLE_TEMP_DIR"] = codebundle_temp_dir
        logger.info("CODEBUNDLE_TEMP_DIR set to: %s", codebundle_temp_dir)

        #    - kubeconfig path
        os.environ["KUBECONFIG"] = kubeconfig_path
        logger.info("KUBECONFIG set to: %s", kubeconfig_path)

        # Optionally also record the top-level directory for referencing anywhere else
        os.environ["RUNWHEN_WORKDIR"] = runwhen_workdir

        return {
            "RUNWHEN_WORKDIR": runwhen_workdir,
            "AZURE_CONFIG_DIR": azure_config_dir,
            "CLOUDSDK_CONFIG": gcloud_config_dir,
            "AWS_CONFIG_DIR": aws_config_dir,
            "CODEBUNDLE_TEMP_DIR": codebundle_temp_dir,
            "KUBECONFIG": kubeconfig_path,
        }

    except Exception as e:
        logger.error("Failed to set runwhen environment directories: %s", str(e))
        raise

def main():
    """
    The main entry point
    """
    # Register cleanup for execution-specific directories 
    register_cleanup_for_execution_dir()

    # Set additional environment variables ***before*** you spawn anything
    os.environ.setdefault("AZURE_CORE_COLLECT_TELEMETRY", "false")
    os.environ.setdefault("CLOUDSDK_CORE_DISABLE_USAGE_REPORTING", "true")
    os.environ.setdefault("AWS_EC2_METADATA_DISABLED", "true") 


    # Set workdirs
    dirs = set_runwhen_workdir()
    # Initialize OTEL at startup
    init_otel()

    # Initialize process metrics recording
    if PROCESS_METRICS_AVAILABLE:
        try:
            session_id = os.environ.get('RW_SESSION_ID')
            runrequest_id = os.environ.get('RW_RUNREQUEST_ID')
            recorder = init_process_metrics(session_id=session_id, runrequest_id=runrequest_id)
            logger.info("Process metrics recording initialized")
        except Exception as e:
            logger.warning(f"Failed to initialize process metrics: {e}")
            recorder = None
    else:
        recorder = None

    # push start timestamp
    push_platform_metric_timestamp("runrobot_platform_start", description="runrobot code starting (utc timestamp)")

    parser = argparse.ArgumentParser()
    parser.add_argument("--rfile", default="./sli.robot")
    parser.add_argument("--logs", default="./robot_logs")
    args = parser.parse_args()

    rfile = resolve_path_to_robot()
    
    # Use execution-specific logs directory if provided, otherwise use command line arg or default
    execution_logs_dir = os.environ.get("RW_EXECUTION_LOGS_DIR")
    if execution_logs_dir:
        logs_path = os.path.abspath(execution_logs_dir)
        logger.info("Using execution-specific logs directory: %s", logs_path)
    else:
        logs_path = os.path.abspath(args.logs)
        logger.info("Using default logs directory: %s", logs_path)
    
    os.makedirs(logs_path, exist_ok=True)

    check_platform_rvars()

    interval_seconds = int(os.getenv("RW_INTERVAL_SECONDS", -1))
    stdout_file_path = os.path.join(logs_path, "stdout.txt")

    titles_str = os.getenv("RW_TASK_TITLES", None)
    logger.info(f"running task titles from RW_TASK_TITLES {titles_str}")
    if titles_str == "*":
        titles = ["*"]
    elif titles_str is None:
        titles = ["*"]
    else:
        titles = json.loads(titles_str)

    push_platform_metric_timestamp("runrobot_user_start", description="runrobot user-level code start (utc)")

    prior_pass_count = None
    prior_fail_count = None

    # Register signal handlers for graceful shutdown
    def signal_handler(sig, frame):
        logger.info(f"Received signal {sig}, shutting down gracefully...")
        
        # Finalize process metrics
        if PROCESS_METRICS_AVAILABLE:
            try:
                finalize_process_metrics(exit_code=128 + sig)  # Standard signal exit code
                logger.info("Process metrics finalized on signal")
            except Exception as e:
                logger.warning(f"Error finalizing process metrics on signal: {e}")
        
        # Force flush any pending metrics
        if _otel_provider:
            try:
                _otel_provider.force_flush(timeout_millis=1000)
                _otel_provider.shutdown(timeout_millis=1000)
            except Exception as e:
                logger.warning(f"Error during OTEL shutdown: {e}")
        sys.exit(0)
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    try:
        while True:
            start_time = datetime.datetime.now()
            push_platform_metric_timestamp("runrobot_user_start", description="user-level robot script starting")

            # Record initial process metrics
            if recorder:
                try:
                    recorder.record_process_metrics()
                    logger.debug("Initial process metrics recorded")
                except Exception as e:
                    logger.warning(f"Error recording initial process metrics: {e}")

            with open(stdout_file_path, "w") as stdoutfile:
                results_listener = RobotResultsListener()
                robot.run(
                    rfile,
                    test=titles,
                    listener=results_listener,
                    stdout=stdoutfile,
                    outputdir=logs_path,
                    loglevel="TRACE",
                    variable=[
                        f"AZURE_CONFIG_DIR:{dirs["AZURE_CONFIG_DIR"]}",
                        f"CLOUDSDK_CONFIG:{dirs["CLOUDSDK_CONFIG"]}",
                        f"AWS_CONFIG_DIR:{dirs["AWS_CONFIG_DIR"]}",
                        f"CODEBUNDLE_TEMP_DIR:{dirs["CODEBUNDLE_TEMP_DIR"]}",
                        f"KUBECONFIG:{dirs["KUBECONFIG"]}",
                    ]
                )
                stdoutfile.close()

                push_platform_metric_timestamp("runrobot_user_end", description="user-level robot script ended")
                push_platform_metric_elapsed_seconds("runrobot_user_code", start_time, "user-level robot script runtime")
                _kill_descendants()
                
                # Update process metrics after robot execution
                if recorder:
                    try:
                        recorder.record_process_metrics()
                    except Exception as e:
                        logger.warning(f"Error recording process metrics: {e}")
                
                pass_count = len(results_listener.test_passed_titles)
                fail_count = len(results_listener.test_failed_titles)

                post_results(
                    logs_path=logs_path,
                    passed_titles=results_listener.test_passed_titles,
                    failed_titles=results_listener.test_failed_titles,
                    skipped_titles=results_listener.test_skipped_titles,
                )

            push_platform_metric_timestamp("runrobot_platform_end", description="runrobot end (utc timestamp)")
            push_platform_metric("task_pass_count", pass_count, GAUGE, "user code total tasks executed")
            push_platform_metric("task_fail_count", fail_count, GAUGE, "user code total tasks executed")
            if interval_seconds > 0:
                time.sleep(interval_seconds)
            else:
                break

    except Exception as e:
        push_platform_metric_timestamp("runrobot_platform_exception", description="runrobot platform-level exception")
        logger.error(e)
        with open(stdout_file_path, "a") as stdoutfile:
            stdoutfile.write("Exception during execution: " + str(e))
            traceback.print_exc(file=stdoutfile)
        # Attempt to post the exception logs
        try:
            post_results(logs_path=logs_path, exceptions=[e])
        except Exception as ee:
            logger.warning(f"Unable to post exception details: {ee}")
        
        # Finalize process metrics with error code
        if PROCESS_METRICS_AVAILABLE:
            try:
                finalize_process_metrics(exit_code=1)
            except Exception as me:
                logger.warning(f"Error finalizing process metrics: {me}")
        
        raise e
    finally:
        # Clean shutdown of metrics server
        if PROCESS_METRICS_AVAILABLE:
            try:
                finalize_process_metrics(exit_code=0)
                logger.info("Process metrics finalized during cleanup")
            except Exception as e:
                logger.warning(f"Error finalizing process metrics during cleanup: {e}")

        # Force flush any pending metrics
        if _otel_provider:
            try:
                _otel_provider.force_flush(timeout_millis=1000)
                _otel_provider.shutdown(timeout_millis=1000)
            except Exception as e:
                logger.warning(f"Error during OTEL shutdown: {e}")


if __name__ == "__main__":
    main()

