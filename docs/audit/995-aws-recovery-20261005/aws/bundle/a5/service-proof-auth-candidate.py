#!/usr/bin/env python3
"""Run only as igpub-STACK; output is deliberately limited to public evidence."""
import argparse
import base64
import datetime
import hashlib
import json
import os
from pathlib import Path
import pwd
import shlex
import signal
import socket
import subprocess
import time
import urllib.parse
import uuid

ACCOUNTS = {"hub2you": ("354307071110", "hub2you"), "autonomia": ("140023375763", "financial")}
PUBLIC_AWS_ERROR_CODES = frozenset({
    "AccessDenied", "AccessDeniedException", "ExpiredToken", "ExpiredTokenException",
    "InvalidClientTokenId", "InvalidSessionId", "InvalidSessionIdException",
    "ParameterNotFound", "TargetNotConnected", "TargetNotConnectedException",
    "Throttling", "ThrottlingException", "ValidationException",
})
PUBLIC_ERROR_TYPES = frozenset({
    "RuntimeError", "OSError", "FileNotFoundError", "FileExistsError", "PermissionError",
    "TimeoutError", "ValueError", "TypeError", "KeyError", "JSONDecodeError", "ClientError",
    "EndpointConnectionError", "ConnectTimeoutError", "ReadTimeoutError", "ConnectionClosedError",
    "ConnectionError", "NoCredentialsError", "PartialCredentialsError", "CredentialRetrievalError",
    "ProfileNotFound", "ConfigParseError", "WebSocketBadStatusException", "WebSocketTimeoutException",
    "WebSocketConnectionClosedException", "WebSocketAddressException", "WebSocketProxyException",
    "SSLError", "ProxyConnectionError", "BrokenPipeError", "CalledProcessError", "TimeoutExpired",
})
PUBLIC_FAILURE_REASONS = frozenset({
    "current_changed_during_transport_proof", "data_channel_url_session_mismatch",
    "foreign_channel_upgrade_not_403", "foreign_session_termination_unexpectedly_allowed",
    "foreign_synthetic_session_required", "foreign_synthetic_stream_url_required",
    "foreign_terminate_unexpected_error", "host_key_command_failed_or_timed_out",
    "host_key_plugin_count", "host_public_key_format",
    "http_observation_receipt_failed_public_cleanup_handle_emitted",
    "initial_session_receipt_failed_public_cleanup_handle_emitted", "invalid_public_http_observation",
    "must_run_as_exact_publisher_uid", "own_channel_upgrade_not_101", "own_session_not_terminated",
    "plugin_listener_not_loopback", "plugin_still_running", "proof_id_must_be_uuid_hex",
    "publisher_public_fingerprint_failed", "session_receipt_owner_mode", "ssh_banner_not_received",
    "start_session_id_missing", "sts_role_not_exact", "temporary_credentials_duration",
    "temporary_credentials_expiry_missing", "unexpected_mode",
    "foreign_session_id_invalid", "foreign_session_must_be_outside_own_prefix",
    "diagnostic_runtime_pin_missing", "diagnostic_runtime_mismatch", "diagnostic_own_pair_invalid",
    "diagnostic_foreign_socket_not_closed", "diagnostic_original_pair_changed",
    "diagnostic_sessions_not_distinct", "current_changed_during_diagnostic",
})
PUBLIC_CLEANUP_FAILURES = frozenset({
    "own_session_cleanup_failed_admin_cleanup_required", "final_session_receipt_failed", "plugin_cleanup_failed",
})
def require(value, reason):
    if not value: raise RuntimeError(reason)
def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()
def error_code(error):
    try:
        response = getattr(error, "response", None)
        detail = response.get("Error") if isinstance(response, dict) else None
        if isinstance(detail, dict) and "Code" in detail:
            code = detail["Code"]
            return code if isinstance(code, str) and code in PUBLIC_AWS_ERROR_CODES else "details_suppressed"
    except Exception:
        return "details_suppressed"
    name = type(error).__name__
    return name if name in PUBLIC_ERROR_TYPES else "details_suppressed"

def public_failure_reason(error):
    if not isinstance(error, RuntimeError):
        return "details_suppressed"
    try:
        reason = str(error)
    except Exception:
        return "details_suppressed"
    if reason in PUBLIC_FAILURE_REASONS:
        return reason
    parts = reason.split(",")
    if 1 <= len(parts) <= 3 and len(set(parts)) == len(parts) and all(part in PUBLIC_CLEANUP_FAILURES for part in parts):
        return reason
    return "details_suppressed"
class SessionLifecycle:
    """Capture a public cleanup handle before any fallible receipt write."""
    def __init__(self, ssm, directory, reason, emit=None):
        self.ssm, self.directory, self.reason = ssm, directory, reason
        self.response, self.session_id, self.plugin = None, None, None
        self.created_utc = None
        self.emit = emit or (lambda value: print(json.dumps(value), flush=True))

    def public(self, evidence, failure=None):
        result = {
            "session_id": self.session_id, "reason": self.reason, "created_utc": self.created_utc,
            "own_session_terminated": evidence.get("own_session_terminated", False),
            "admin_cleanup_required": not evidence.get("own_session_terminated", False),
            "utc": now(),
        }
        for key in ("stack", "account", "role_arn", "instance_id", "termination_error",
                    "receipt_error", "plugin_cleanup_error", "plugin_stopped", "foreign_session_id",
                    "foreign_session_terminate_error_code", "foreign_session_terminate_denied", "diagnostic"):
            if key in evidence:
                result[key] = evidence[key]
        for key in ("own_channel_http", "foreign_channel_http"):
            value = evidence.get(key)
            if type(value) is int and 100 <= value <= 599:
                result[key] = value
        if failure:
            result["failure"] = failure
        return result

    def observe_http(self, evidence, key, status):
        require(key in ("own_channel_http", "foreign_channel_http") and
                type(status) is int and 100 <= status <= 599, "invalid_public_http_observation")
        evidence[key] = status
        try:
            self.persist(self.public(evidence), initial=False)
        except Exception as error:
            evidence["receipt_error"] = error_code(error)
            self.emit(self.public(evidence, "http_observation_receipt_failed"))
            raise RuntimeError("http_observation_receipt_failed_public_cleanup_handle_emitted")
        self.emit(self.public(evidence))

    def persist(self, value, initial):
        # A hashed filename keeps a returned SessionId out of filesystem path syntax.
        name = "proof-session-" + hashlib.sha256(self.session_id.encode()).hexdigest() + ".json"
        path = self.directory / name
        flags = os.O_WRONLY | os.O_NOFOLLOW
        flags |= os.O_CREAT | os.O_EXCL if initial else 0
        fd = os.open(str(path), flags, 0o600)
        with os.fdopen(fd, "w") as record:
            info = os.fstat(record.fileno())
            require(info.st_uid == os.getuid() and info.st_nlink == 1 and info.st_mode & 0o777 == 0o600,
                    "session_receipt_owner_mode")
            if not initial:
                os.ftruncate(record.fileno(), 0)
            json.dump(value, record)
            record.flush()
            os.fsync(record.fileno())

    def begin(self, target, port, evidence):
        self.response = self.ssm.start_session(
            Target=target, DocumentName="AWS-StartPortForwardingSession",
            Parameters={"portNumber": ["22"], "localPortNumber": [str(port)]}, Reason=self.reason)
        # Assign before validation or disk access so an error cannot lose the cleanup handle.
        self.session_id = self.response.get("SessionId")
        self.created_utc = now()
        require(isinstance(self.session_id, str) and self.session_id, "start_session_id_missing")
        evidence.update({"session_id": self.session_id, "reason": self.reason})
        try:
            self.persist(self.public(evidence), initial=True)
        except Exception as error:
            evidence["receipt_error"] = error_code(error)
            self.emit(self.public(evidence, "initial_session_receipt_failed"))
            raise RuntimeError("initial_session_receipt_failed_public_cleanup_handle_emitted")
        self.emit(self.public(evidence))
        return self.response

    def finish(self, evidence):
        failures = []
        try:
            if self.session_id:
                try:
                    self.ssm.terminate_session(SessionId=self.session_id)
                    evidence["own_session_terminated"] = True
                except Exception as error:
                    evidence["own_session_terminated"] = False
                    evidence["termination_error"] = error_code(error)
                    failures.append("own_session_cleanup_failed_admin_cleanup_required")
                try:
                    self.persist(self.public(evidence), initial=False)
                except Exception as error:
                    evidence["receipt_error"] = error_code(error)
                    failures.append("final_session_receipt_failed")
        finally:
            # Receipt and API failures must never prevent stopping our exact child process.
            if self.plugin is not None:
                try:
                    if self.plugin.poll() is None:
                        self.plugin.terminate()
                    try:
                        self.plugin.communicate(timeout=5)
                    except subprocess.TimeoutExpired:
                        self.plugin.kill()
                        self.plugin.communicate(timeout=2)
                    evidence["plugin_stopped"] = self.plugin.poll() is not None
                    require(evidence["plugin_stopped"], "plugin_still_running")
                except Exception as error:
                    evidence["plugin_cleanup_error"] = error_code(error)
                    failures.append("plugin_cleanup_failed")
            if self.session_id or failures:
                self.emit(self.public(evidence, ",".join(failures) if failures else None))
        return failures

def channel_url(url, session_id):
    parsed = urllib.parse.urlsplit(url)
    expected_path = "/v1/data-channel/" + urllib.parse.quote(session_id, safe="-_.~")
    try:
        query = urllib.parse.parse_qsl(parsed.query, keep_blank_values=True, strict_parsing=True)
    except ValueError:
        raise RuntimeError("data_channel_url_session_mismatch")
    values = dict(query)
    require(parsed.scheme == "wss" and parsed.netloc == "ssmmessages.us-east-1.amazonaws.com" and
            parsed.path == expected_path and not parsed.fragment and
            len(values) == len(query) and set(values) in ({"role"}, {"role", "cell-number"}) and
            values.get("role") == "publish_subscribe" and all(value for key, value in query),
            "data_channel_url_session_mismatch")
    # cell-number is opaque AWS routing data. Do not decode/re-encode it or
    # rebuild the query: the original URL is used unchanged for signing/opening.
    return parsed

def plugin_loopback_listener(output, pid, port):
    marker = "pid=" + str(pid) + ","
    rows = [line.split() for line in output.splitlines()]
    own = [row for row in rows if len(row) >= 6 and marker in " ".join(row[5:])]
    if not own:
        return False
    allowed = {"127.0.0.1:" + str(port), "[::1]:" + str(port), "::1:" + str(port)}
    require(all(row[3] in allowed for row in own), "plugin_listener_not_loopback")
    return any(row[3] == "127.0.0.1:" + str(port) for row in own)

def run():
    parser = argparse.ArgumentParser()
    parser.add_argument("--stack", required=True, choices=ACCOUNTS)
    parser.add_argument("--mode", required=True, choices=("identity", "start-session", "transport", "channel-matrix", "termination-matrix", "protocol-control", "auth-binding"))
    parser.add_argument("--foreign-session-id")
    parser.add_argument("--proof-id")
    parser.add_argument("--foreign-stream-url-env", choices=("IGPUB_FOREIGN_STREAM_URL",))
    args = parser.parse_args()
    foreign_stream_url = None
    if args.mode in ("channel-matrix", "auth-binding"):
        require(args.foreign_stream_url_env and args.foreign_session_id, "foreign_synthetic_session_required")
        foreign_stream_url = os.environ.pop(args.foreign_stream_url_env, None)
        require(foreign_stream_url, "foreign_synthetic_stream_url_required")
        channel_url(foreign_stream_url, args.foreign_session_id)
        if args.mode == "auth-binding":
            require(len(args.foreign_session_id) <= 96 and
                    all(c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_" for c in args.foreign_session_id),
                    "foreign_session_id_invalid")
            require(not args.foreign_session_id.startswith("igpub-" + args.stack + "-vps-"),
                    "foreign_session_must_be_outside_own_prefix")
    elif args.mode == "termination-matrix":
        require(args.foreign_session_id and not args.foreign_stream_url_env, "foreign_synthetic_session_required")
        require(len(args.foreign_session_id) <= 256 and
                all(c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_" for c in args.foreign_session_id),
                "foreign_session_id_invalid")
        require(not args.foreign_session_id.startswith("igpub-" + args.stack + "-vps-"),
                "foreign_session_must_be_outside_own_prefix")
    if args.proof_id:
        require(uuid.UUID(args.proof_id).hex == args.proof_id, "proof_id_must_be_uuid_hex")
    stack = args.stack
    account, profile = ACCOUNTS[stack]
    owner = pwd.getpwnam("igpub-" + stack)
    require(os.getuid() == owner.pw_uid, "must_run_as_exact_publisher_uid")
    home = Path("/var/lib/instagram-publisher-" + stack)
    directory = home / "publisher"
    os.environ.clear()
    os.environ.update({
        "HOME": str(home), "PATH": "/usr/local/bin:/usr/bin:/bin",
        "AWS_CONFIG_FILE": str(directory / "aws-config"), "AWS_SHARED_CREDENTIALS_FILE": "/dev/null",
        "AWS_EC2_METADATA_DISABLED": "true", "AWS_PAGER": "", "AWS_DEFAULT_REGION": "us-east-1",
    })
    import boto3
    from botocore.config import Config
    session = boto3.Session(profile_name=profile, region_name="us-east-1")
    config = Config(connect_timeout=5, read_timeout=8, retries={"total_max_attempts": 1})
    sts = session.client("sts", config=config)
    ssm = session.client("ssm", config=config)
    start_time = time.monotonic()
    identity = sts.get_caller_identity()
    role_name = "chatwoot-instagram-publisher-" + stack + "-vps"
    role_arn = "arn:aws:iam::" + account + ":role/" + role_name
    fixed = "igpub-" + stack + "-vps"
    expected = "arn:aws:sts::" + account + ":assumed-role/" + role_name + "/" + fixed
    require(identity["Account"] == account and identity["Arn"] == expected, "sts_role_not_exact")
    expiry = getattr(session.get_credentials(), "_expiry_time", None)
    require(expiry is not None, "temporary_credentials_expiry_missing")
    seconds = (expiry - datetime.datetime.now(datetime.timezone.utc)).total_seconds()
    require(0 < seconds <= 905, "temporary_credentials_duration")
    evidence = {
        "utc": now(), "stack": stack, "account": account, "role_arn": role_arn,
        "assumed_role_arn": identity["Arn"], "fixed_session_name": fixed, "sts_role_exact": True,
        "credentials_expire_in_seconds": round(seconds), "requested_session_seconds": 900,
        "expiry_clock_tolerance_seconds": 5, "sts_latency_ms": round((time.monotonic() - start_time) * 1000),
    }
    if args.mode == "identity":
        print(json.dumps(evidence))
        return
    current = ssm.get_parameter(Name="/chatwoot/prod/blue-green/current-instance-id")["Parameter"]["Value"]
    evidence["instance_id"] = current
    reason = "InstagramRuntime995:" + stack + ":" + (args.proof_id or uuid.uuid4().hex)
    lifecycle = SessionLifecycle(ssm, directory, reason)
    if args.mode == "start-session":
        # Initial policy intentionally lacks TerminateSession; public receipt/output is
        # the administrative cleanup handle on both success and persistence failure.
        response = lifecycle.begin(current, 18995, evidence)
        evidence.update({"fixed_session_name": fixed, "admin_cleanup_confirmed": False})
        print(json.dumps(evidence))
        return
    own = None
    plugin = None
    cleanup_failures = []
    try:
        if args.mode in ("protocol-control", "auth-binding"):
            import auth_diagnostic
            if args.mode == "auth-binding":
                evidence["foreign_session_id"] = args.foreign_session_id
            auth_diagnostic.run_mode(args.mode, foreign_stream_url, args.foreign_session_id,
                                     session, ssm, lifecycle, evidence, current, profile,
                                     channel_url, plugin_loopback_listener)
        elif args.mode == "termination-matrix":
            evidence["foreign_session_id"] = args.foreign_session_id
            own = lifecycle.begin(current, 18995, evidence)
            try:
                ssm.terminate_session(SessionId=args.foreign_session_id)
            except Exception as error:
                code = error_code(error)
                evidence["foreign_session_terminate_error_code"] = code
                require(code in ("AccessDenied", "AccessDeniedException"), "foreign_terminate_unexpected_error")
                evidence["foreign_session_terminate_denied"] = True
            else:
                evidence["foreign_session_terminate_denied"] = False
                raise RuntimeError("foreign_session_termination_unexpectedly_allowed")
        elif args.mode == "channel-matrix":
            import websocket
            from botocore.auth import SigV4Auth
            from botocore.awsrequest import AWSRequest
            # Freeze once; both requests below use this exact credential set.
            credentials = session.get_credentials().get_frozen_credentials()
            own = lifecycle.begin(current, 18995, evidence)
            def upgrade(url, session_id, field):
                parsed = channel_url(url, session_id)
                signed_url = urllib.parse.urlunsplit(("https", parsed.netloc, parsed.path, parsed.query, ""))
                request = AWSRequest(method="GET", url=signed_url)
                SigV4Auth(credentials, "ssmmessages", "us-east-1").add_auth(request)
                try:
                    channel = websocket.create_connection(url, header=dict(request.headers), timeout=8, suppress_origin=True)
                except websocket.WebSocketBadStatusException as error:
                    lifecycle.observe_http(evidence, field, error.status_code)
                    return error.status_code
                try:
                    status = channel.getstatus()
                    lifecycle.observe_http(evidence, field, status)
                    return status
                finally:
                    channel.close()
            own_status = upgrade(own["StreamUrl"], own["SessionId"], "own_channel_http")
            require(own_status == 101, "own_channel_upgrade_not_101")
            other_status = upgrade(foreign_stream_url, args.foreign_session_id, "foreign_channel_http")
            require(other_status == 403, "foreign_channel_upgrade_not_403")
            terminated_foreign = False
            try:
                ssm.terminate_session(SessionId=args.foreign_session_id)
                terminated_foreign = True
            except Exception as error:
                require(error_code(error) in ("AccessDenied", "AccessDeniedException"), "foreign_terminate_unexpected_error")
            require(not terminated_foreign, "foreign_session_termination_unexpectedly_allowed")
            evidence.update({"own_channel_http": own_status, "foreign_channel_http": other_status,
                             "foreign_session_terminate_denied": True, "same_frozen_credentials_used": True, "foreign_token_used": False})
        elif args.mode == "transport":
            started = time.monotonic()
            command = ssm.send_command(InstanceIds=[current], DocumentName="ChatwootInstagramPublisherHostKey")
            invocation = None
            until = time.monotonic() + 12
            while time.monotonic() < until:
                rows = ssm.list_command_invocations(CommandId=command["Command"]["CommandId"], Details=True)["CommandInvocations"]
                if rows and rows[0]["Status"] not in ("Pending", "InProgress", "Delayed"):
                    invocation = rows[0]
                    break
                time.sleep(0.5)
            require(invocation is not None and invocation["Status"] == "Success", "host_key_command_failed_or_timed_out")
            outputs = invocation.get("CommandPlugins", [])
            require(len(outputs) == 1, "host_key_plugin_count")
            words = outputs[0]["Output"].strip().split()
            require(len(words) in (2, 3) and words[0] == "ssh-ed25519", "host_public_key_format")
            host_fingerprint = "SHA256:" + base64.b64encode(hashlib.sha256(base64.b64decode(words[1])).digest()).decode().rstrip("=")
            listener = socket.socket()
            listener.bind(("127.0.0.1", 0))
            local_port = listener.getsockname()[1]
            listener.close()
            own = lifecycle.begin(current, local_port, evidence)
            env = dict(os.environ)
            env["AWS_SSM_START_SESSION_RESPONSE"] = json.dumps({k: own[k] for k in ("SessionId", "StreamUrl", "TokenValue")})
            parameters = {"Target": current, "DocumentName": "AWS-StartPortForwardingSession", "Parameters": {"portNumber": ["22"], "localPortNumber": [str(local_port)]}}
            plugin = subprocess.Popen(["/usr/local/bin/session-manager-plugin", "AWS_SSM_START_SESSION_RESPONSE",
                                       "us-east-1", "StartSession", profile, json.dumps(parameters), "https://ssm.us-east-1.amazonaws.com"],
                                      env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            lifecycle.plugin = plugin
            env.pop("AWS_SSM_START_SESSION_RESPONSE", None)
            banner = None
            deadline = time.monotonic() + 12
            while time.monotonic() < deadline and plugin.poll() is None:
                try:
                    listeners = subprocess.run(["/usr/bin/ss", "-ltnpH", "sport = :" + str(local_port)], capture_output=True, text=True, timeout=2)
                    if not plugin_loopback_listener(listeners.stdout, plugin.pid, local_port):
                        time.sleep(0.2)
                        continue
                    with socket.create_connection(("127.0.0.1", local_port), timeout=0.4) as client:
                        client.settimeout(3)
                        banner = client.recv(256)
                        break
                except (ConnectionRefusedError, socket.timeout):
                    time.sleep(0.2)
            require(banner is not None and banner.startswith(b"SSH-2.0-"), "ssh_banner_not_received")
            fingerprint = subprocess.run(["/usr/bin/ssh-keygen", "-lf", str(directory / "id_ed25519.pub"), "-E", "sha256"],
                                         capture_output=True, text=True, timeout=5)
            require(fingerprint.returncode == 0, "publisher_public_fingerprint_failed")
            after = ssm.get_parameter(Name="/chatwoot/prod/blue-green/current-instance-id")["Parameter"]["Value"]
            require(after == current, "current_changed_during_transport_proof")
            evidence.update({"public_key_fingerprint": fingerprint.stdout.split()[1], "current_stable": True,
                             "ssm_host_key_document_ok": True, "host_public_key_fingerprint": host_fingerprint,
                             "ssm_channel_open_ok": True, "ssh_banner_ok": True,
                             "transport_scope": "ssm_tunnel_and_ssh_banner_only",
                             "transport_latency_ms": round((time.monotonic() - started) * 1000)})
        else:
            raise RuntimeError("unexpected_mode")
    finally:
        try:
            cleanup_failures = lifecycle.finish(evidence)
        finally:
            guard = getattr(lifecycle, "diagnostic_api_guard", None)
            if guard is not None and (lifecycle.plugin is None or lifecycle.plugin.poll() is not None):
                guard.close()
    require(not cleanup_failures, ",".join(cleanup_failures))
    require(evidence.get("own_session_terminated") is True, "own_session_not_terminated")
    print(json.dumps(evidence))
def main():
    try:
        run()
    except Exception as error:
        print(json.dumps({"status": "failed", "error_type": error_code(error), "reason": public_failure_reason(error)}), flush=True)
        return 1
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
