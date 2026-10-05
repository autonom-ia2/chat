"""Bounded diagnostic collector. No authorization verdict and no cutover proof.

Only the official plugin completes the positive own-pair control. The custom
path sends one OpenDataChannelInput and observes bounded metadata; it does not
implement SSM ACK, HandshakeResponse, Resume or a binary protocol client.
"""
import datetime
import hashlib
import json
import os
from pathlib import Path
import socket
import stat
import subprocess
import time
import urllib.parse
import uuid

from ssm_metadata import MetadataObserver
from ssm_close_diagnostic import capture_invalid_close

MAX_FRAME = 64 * 1024
MAX_TOTAL = 256 * 1024
MAX_FRAMES = 32
PHASE_SECONDS = 10
PLUGIN = "/usr/local/bin/session-manager-plugin"
PLUGIN_VERSION = "1.2.835.0"
# Public metadata from auth-runtime-readonly-20261005T205522Z.json. The four
# Python sources also match upstream v1.7.0 byte for byte; the plugin binary's
# version/hash does not alone establish source or endpoint-behavior equivalence.
RUNTIME_PINS = {'websocket_version': '1.7.0', 'plugin_version': '1.2.835.0', 'plugin_sha256': 'f6002be08e5c57dc97eb9a0ef819d54f4c9a4a724c5818cec7d4baeaadfe4cbd', 'python_sources': {'websocket._abnf': {'path': '/usr/lib/python3/dist-packages/websocket/_abnf.py', 'sha256': 'e8a0a70adfd252ed56bface1e0126a36ca308e5a9e780ac41f7a60b81401248a'}, 'websocket._core': {'path': '/usr/lib/python3/dist-packages/websocket/_core.py', 'sha256': '79334775fff7339752d79be5aa2cdec8f40956a68037e6fb00a3926a14f94773'}, 'websocket._handshake': {'path': '/usr/lib/python3/dist-packages/websocket/_handshake.py', 'sha256': 'f4378e7bc4ebf46ea274c72f35f118e25e3a86e4f37a883313eeab21596e8541'}, 'websocket._socket': {'path': '/usr/lib/python3/dist-packages/websocket/_socket.py', 'sha256': '93027d7438e5ce22ff0a97e02112bd72bb1bd1c9112153db9750e48074f00677'}}}


class ObservationStopped(Exception):
    """Only fixed local reasons are ever exported; received text is discarded."""


STOP_REASONS = frozenset({
    "time_limit", "peer_eof", "fragmentation_not_supported", "extensions_not_supported",
    "masked_server_frame", "opcode_not_supported", "noncanonical_length",
    "frame_byte_limit", "total_byte_limit", "frame_count_limit",
    "control_frame_invalid", "channel_closed_observed", "protocol_metadata_observed",
    "frame_metadata_stopped", "transport_error", "http_upgrade_rejected",
    "upgrade_not_101", "send_failed", "runtime_incompatible", "shutdown_failed", "http_byte_limit",
})


def require(value, reason):
    if not value:
        raise RuntimeError(reason)


def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def file_sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as source:
        while True:
            chunk = source.read(64 * 1024)
            if not chunk:
                return digest.hexdigest()
            digest.update(chunk)


def verify_runtime():
    """No package install or fallback. Compare public code/binary metadata."""
    import websocket
    import websocket._abnf
    import websocket._core
    import websocket._handshake
    import websocket._socket
    require(RUNTIME_PINS and set(RUNTIME_PINS) == {
        "websocket_version", "plugin_version", "plugin_sha256", "python_sources"},
        "diagnostic_runtime_pin_missing")
    require(websocket.__version__ == RUNTIME_PINS["websocket_version"] and
            RUNTIME_PINS["plugin_version"] == PLUGIN_VERSION, "diagnostic_runtime_mismatch")
    sources = {
        "websocket._abnf": websocket._abnf.__file__,
        "websocket._core": websocket._core.__file__,
        "websocket._handshake": websocket._handshake.__file__,
        "websocket._socket": websocket._socket.__file__,
    }
    require(set(sources) == set(RUNTIME_PINS["python_sources"]), "diagnostic_runtime_mismatch")
    for name, path in sources.items():
        entry = RUNTIME_PINS["python_sources"][name]
        require(str(Path(path).resolve()) == entry["path"] and file_sha256(path) == entry["sha256"],
                "diagnostic_runtime_mismatch")
        info = Path(path).stat()
        require(stat.S_ISREG(info.st_mode) and info.st_uid == 0 and not info.st_mode & 0o022,
                "diagnostic_runtime_mismatch")
    require(file_sha256(PLUGIN) == RUNTIME_PINS["plugin_sha256"], "diagnostic_runtime_mismatch")
    version = subprocess.run([PLUGIN, "--version"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                             timeout=5)
    require(version.returncode == 0 and version.stdout.strip() == PLUGIN_VERSION.encode(),
            "diagnostic_runtime_mismatch")
    return {"websocket_version": websocket.__version__, "plugin_version": PLUGIN_VERSION,
            "plugin_sha256": RUNTIME_PINS["plugin_sha256"], "python_sources_exact": True}


class DeadlineSocket:
    """Bound HTTP headers/error body and use one deadline for every read.

    The library's pinned HTTP code otherwise reads an unbounded line or uses a
    server Content-Length directly. The wrapper is installed before handshake.
    It never captures, parses, exports or logs headers, credentials or bodies.
    """
    def __init__(self, sock, deadline, clock=time.monotonic):
        self.raw, self.deadline, self.clock = sock, deadline, clock
        self.http_remaining = 16 * 1024
        self.frames_started = False

    def remaining(self):
        left = self.deadline - self.clock()
        if left <= 0:
            raise ObservationStopped("time_limit")
        return left

    def recv(self, count):
        if not self.frames_started:
            if self.http_remaining <= 0:
                raise ObservationStopped("http_byte_limit")
            count = min(count, self.http_remaining)
        count = min(count, 8192)
        self.raw.settimeout(self.remaining())
        data = self.raw.recv(count)
        if not self.frames_started:
            self.http_remaining -= len(data)
        self.remaining()
        return data

    def start_frames(self):
        self.frames_started = True

    def settimeout(self, value):
        left = self.remaining()
        self.raw.settimeout(left if value is None else min(left, value))

    def gettimeout(self):
        left = self.remaining()
        value = self.raw.gettimeout()
        return left if value is None else min(left, value)

    def send(self, data):
        self.raw.settimeout(self.remaining())
        return self.raw.send(data)

    def close(self):
        return self.raw.close()

    def __getattr__(self, name):
        return getattr(self.raw, name)


def bounded_websocket_class(websocket, deadline):
    # create_connection's documented class_ hook, not a global monkeypatch.
    # _core assigns sock immediately after connect/TLS and before handshake.
    class BoundedWebSocket(websocket.WebSocket):
        @property
        def sock(self):
            return getattr(self, "_bounded_sock", None)

        @sock.setter
        def sock(self, value):
            self._bounded_sock = DeadlineSocket(value, deadline) if value is not None else None
    return BoundedWebSocket


class FrameReader:
    """Read physical frames only, rejecting lengths BEFORE reading payload.

    After a validated library upgrade, the pinned implementation leaves no
    prefetched WebSocket bytes. This reader uses its TLS socket directly and
    never calls recv_frame/recv_data, which could allocate/reassemble first.
    No decompression, fragmentation, resynchronization or retry is supported.
    """
    KINDS = {1: "text", 2: "binary", 8: "close", 9: "ping", 10: "pong"}

    def __init__(self, sock, deadline, clock=time.monotonic):
        self.sock, self.deadline, self.clock = sock, deadline, clock
        self.frames = 0
        self.payload_bytes = 0
        self.wire_bytes = 0
        self.control_rejection = None

    def remaining(self):
        left = self.deadline - self.clock()
        if left <= 0:
            raise ObservationStopped("time_limit")
        return left

    def exact(self, count):
        # The caller supplies 2/8-byte headers or a previously bounded payload.
        if not 0 <= count <= MAX_FRAME:
            raise ObservationStopped("frame_byte_limit")
        chunks = []
        left = count
        while left:
            self.sock.settimeout(self.remaining())
            try:
                data = self.sock.recv(min(left, 8192))
            except (socket.timeout, TimeoutError):
                raise ObservationStopped("time_limit") from None
            if not data:
                raise ObservationStopped("peer_eof")
            if len(data) > left:
                raise ObservationStopped("transport_error")
            chunks.append(data)
            left -= len(data)
            self.wire_bytes += len(data)
            self.remaining()
        return b"".join(chunks)

    def read(self):
        self.remaining()
        if self.frames >= MAX_FRAMES:
            raise ObservationStopped("frame_count_limit")
        if self.payload_bytes >= MAX_TOTAL:
            raise ObservationStopped("total_byte_limit")
        first, second = self.exact(2)
        opcode = first & 15
        if not first & 128 or opcode == 0:
            raise ObservationStopped("fragmentation_not_supported")
        if first & 112:
            raise ObservationStopped("extensions_not_supported")
        if opcode not in self.KINDS:
            raise ObservationStopped("opcode_not_supported")
        if second & 128:
            raise ObservationStopped("masked_server_frame")
        length = second & 127
        if length == 126:
            length = int.from_bytes(self.exact(2), "big")
            if length < 126:
                raise ObservationStopped("noncanonical_length")
        elif length == 127:
            length = int.from_bytes(self.exact(8), "big")
            if length < 65536 or length & (1 << 63):
                raise ObservationStopped("noncanonical_length")
        if opcode >= 8 and (length > 125 or (opcode == 8 and length == 1)):
            # Only validated header integers/enums. The same rejection still
            # happens before any payload read; this is not an access verdict.
            self.control_rejection = {
                "frame_kind": self.KINDS[opcode], "declared_payload_bytes": length,
                "reason": "close_payload_one_byte" if opcode == 8 and length == 1 else "control_payload_over_125",
            }
            raise ObservationStopped("control_frame_invalid")
        if length > MAX_FRAME:
            raise ObservationStopped("frame_byte_limit")
        if self.payload_bytes + length > MAX_TOTAL:
            raise ObservationStopped("total_byte_limit")
        data = self.exact(length)
        self.frames += 1
        self.payload_bytes += length
        return self.KINDS[opcode], data


def is_protocol_progress(row):
    # Partial compatibility only: no binary response, ACK or full handshake.
    return (row.get("parse_status") == "recognized" and row.get("schema_known") is True and
            row.get("payload_digest") == "valid" and row.get("message_type") == "output_stream_data" and
            row.get("payload_type") == "handshake_request" and row.get("handshake_session_type_actions") == 1)


def observe_channel(url, url_session_id, own, session, channel_url, checkpoint, phase):
    """One connection and one own-token send; no foreign token input exists."""
    import websocket
    from botocore.auth import SigV4Auth
    from botocore.awsrequest import AWSRequest
    result = {
        "phase": phase, "started_utc": utc(), "diagnostic_only": True,
        "time_bound_scope": "http_and_frames_after_tcp_tls", "outer_wrapper_timeout_seconds": 120,
        "authentication_classified": False, "access_classified": False,
        "http_status": 0, "own_token_send_attempted": False, "own_token_send_completed": False,
        "protocol_progress_observed": False, "stop_reason": "transport_error", "frames": [],
        "connection_attempts": 1, "foreign_token_used": False, "socket_closed": False,
    }
    checkpoint(result)
    channel = None
    reader = None
    start = time.monotonic()
    deadline = start + PHASE_SECONDS
    try:
        parsed = channel_url(url, url_session_id)
        require(own["SessionId"] and isinstance(own["TokenValue"], str) and
                0 < len(own["TokenValue"]) <= 16384, "diagnostic_own_pair_invalid")
        credentials = session.get_credentials().get_frozen_credentials()
        signed = urllib.parse.urlunsplit(("https", parsed.netloc, parsed.path, parsed.query, ""))
        request = AWSRequest(method="GET", url=signed)
        SigV4Auth(credentials, "ssmmessages", "us-east-1").add_auth(request)
        # No subprotocol/extension/compression is requested; redirects disabled.
        channel = websocket.create_connection(url, header=dict(request.headers), timeout=min(8, deadline-time.monotonic()),
                                              suppress_origin=True, redirect_limit=0,
                                              class_=bounded_websocket_class(websocket, deadline))
        status = channel.getstatus()
        require(type(status) is int and 100 <= status <= 599, "diagnostic_http_status_invalid")
        result["http_status"] = status
        checkpoint(result)
        if status != 101:
            raise ObservationStopped("upgrade_not_101")
        headers = channel.getheaders()
        require(not any(str(key).lower() == "sec-websocket-extensions" for key in headers),
                "diagnostic_extensions_negotiated")
        # The pinned library does not consume a data frame during its HTTP upgrade.
        require(not channel.frame_buffer.recv_buffer, "diagnostic_prefetched_data_unexpected")
        channel.sock.start_frames()
        reader = FrameReader(channel.sock, deadline)
        observer = MetadataObserver(own["SessionId"], None if phase == "C0" else url_session_id)
        payload = json.dumps({"MessageSchemaVersion": "1.0", "RequestId": str(uuid.uuid4()),
                              "TokenValue": own["TokenValue"], "ClientId": str(uuid.uuid4()),
                              "ClientVersion": PLUGIN_VERSION}, separators=(",", ":"))
        result["own_token_send_attempted"] = True
        checkpoint(result)
        channel.settimeout(reader.remaining())
        channel.send(payload, opcode=websocket.ABNF.OPCODE_TEXT)
        payload = None
        result["own_token_send_completed"] = True
        checkpoint(result)
        while True:
            kind, data = reader.read()
            row = observer.feed(kind, data, int((time.monotonic()-start)*1000))
            result["frames"].append(row)
            result["protocol_progress_observed"] = result["protocol_progress_observed"] or is_protocol_progress(row)
            checkpoint(result)
            if row["stopped"]:
                raise ObservationStopped("frame_metadata_stopped")
            if kind == "close" or row.get("message_type") == "channel_closed":
                raise ObservationStopped("channel_closed_observed")
            if phase == "C0" and result["protocol_progress_observed"]:
                raise ObservationStopped("protocol_metadata_observed")
            if kind == "ping":
                channel.settimeout(reader.remaining())
                channel.pong(data)
            data = None
    except ObservationStopped as error:
        result["stop_reason"] = str(error) if str(error) in STOP_REASONS else "transport_error"
        if reader is not None and reader.control_rejection is not None:
            result["rejected_control_header"] = dict(reader.control_rejection)
            checkpoint(result)
            if phase == "A_to_B":
                result["rejected_close_diagnostic"] = capture_invalid_close(
                    reader, own["SessionId"], url_session_id, max_frame=MAX_FRAME,
                    max_total=MAX_TOTAL, max_frames=MAX_FRAMES, stopped_type=ObservationStopped)
                checkpoint(result)
    except websocket.WebSocketBadStatusException as error:
        value = getattr(error, "status_code", None)
        if type(value) is int and 100 <= value <= 599:
            result["http_status"] = value
        result["stop_reason"] = "http_upgrade_rejected"
    except Exception:
        # Raw dependency exceptions can contain URL/token/body; never stringify.
        result["stop_reason"] = "transport_error"
    finally:
        if channel is not None:
            try:
                # close() may receive/reassemble while waiting for a close frame.
                # shutdown() closes the socket without any further network read.
                channel.shutdown()
                result["socket_closed"] = channel.sock is None
            except Exception:
                result["socket_closed"] = False
                result["stop_reason"] = "shutdown_failed"
        else:
            result["socket_closed"] = True
        result["finished_utc"] = utc()
        result["elapsed_ms"] = min(120000, max(0, int((time.monotonic()-start)*1000)))
        checkpoint(result)
    return result


class PluginApiGuard:
    """Reserved, non-listening loopback endpoint; never an HTTP/TLS server."""
    def __init__(self):
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.socket.bind(("127.0.0.1", 0))
        host, port = self.socket.getsockname()
        require(host == "127.0.0.1" and port > 0, "diagnostic_api_guard_invalid")
        self.endpoint = "https://127.0.0.1:" + str(port)
        # No listen, SO_REUSEADDR, proxy, TLS or credential-bearing request sink.

    def close(self):
        self.socket.close()


def stop_plugin(plugin):
    if plugin.poll() is None:
        plugin.terminate()
    try:
        plugin.wait(timeout=5)
    except subprocess.TimeoutExpired:
        plugin.kill()
        plugin.wait(timeout=2)
    require(plugin.poll() is not None, "plugin_still_running")


def official_original_pair(own, current, local_port, profile, lifecycle, listener_check, checkpoint):
    """Complete own plugin control, with the original response and API guard.

    The SSM endpoint guard is configured according to the reviewed source; its
    installed-binary semantics have not been observed in this diagnostic. The
    original StreamUrl is supplied unchanged. No equality of ClientId,
    credentials or attempt count is claimed. A successful process exit alone
    never completes the tunnel/banner observation below. This control does
    not authenticate SSH or verify an SSH host key.
    """
    result = {"started_utc": utc(), "complete": False, "original_pair_supplied": False,
              "ssm_endpoint_guard_configured": False, "api_guard_scope": "plugin_ssm_endpoint_only",
              "control_scope": "original_pair_input_and_tunnel_banner",
              "new_token_replacement_excluded_by_runtime_observation": False,
              "endpoint_guard_basis": "configured_endpoint_and_reviewed_source",
              "same_pair_websocket_retry_excluded": False, "client_id_equality_claimed": False,
              "credentials_equality_claimed": False, "loopback_listener_owned": False,
              "ssh_banner_ok": False, "plugin_stopped": False, "status": "inconclusive"}
    checkpoint(result)
    guard, plugin = None, None
    original = tuple(own[key] for key in ("SessionId", "StreamUrl", "TokenValue"))
    try:
        guard = PluginApiGuard()
        env = dict(os.environ)
        env["AWS_SSM_START_SESSION_RESPONSE"] = json.dumps(dict(zip(("SessionId", "StreamUrl", "TokenValue"), original)))
        parameters = {"Target": current, "DocumentName": "AWS-StartPortForwardingSession",
                      "Parameters": {"portNumber": ["22"], "localPortNumber": [str(local_port)]}}
        require(tuple(own[key] for key in ("SessionId", "StreamUrl", "TokenValue")) == original,
                "diagnostic_original_pair_changed")
        plugin = subprocess.Popen([PLUGIN, "AWS_SSM_START_SESSION_RESPONSE", "us-east-1", "StartSession", profile,
                                   json.dumps(parameters), guard.endpoint], env=env,
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        lifecycle.plugin = plugin
        env.pop("AWS_SSM_START_SESSION_RESPONSE", None)
        result.update(original_pair_supplied=True, ssm_endpoint_guard_configured=True)
        checkpoint(result)
        deadline = time.monotonic() + 12
        banner = None
        while time.monotonic() < deadline and plugin.poll() is None:
            try:
                listeners = subprocess.run(["/usr/bin/ss", "-ltnpH", "sport = :" + str(local_port)],
                                           capture_output=True, text=True, timeout=2)
                if listeners.returncode or not listener_check(listeners.stdout, plugin.pid, local_port):
                    time.sleep(0.2)
                    continue
                result["loopback_listener_owned"] = True
                with socket.create_connection(("127.0.0.1", local_port), timeout=0.4) as client:
                    client.settimeout(min(3, max(0.001, deadline-time.monotonic())))
                    banner = client.recv(256)
                    break
            except (ConnectionRefusedError, socket.timeout):
                time.sleep(0.2)
        result["ssh_banner_ok"] = banner is not None and banner.startswith(b"SSH-2.0-")
        result["complete"] = result["ssh_banner_ok"] and result["loopback_listener_owned"]
        result["status"] = "banner_observed_original_pair_supplied" if result["complete"] else "inconclusive"
    except Exception:
        result["complete"] = False
        result["status"] = "inconclusive"
    finally:
        try:
            if plugin is not None:
                stop_plugin(plugin)
                result["plugin_stopped"] = True
        finally:
            # Keep the reservation through plugin exit, including terminate/kill.
            # If stop failed, retain the bound socket for the outer lifecycle.
            if guard is not None:
                if plugin is None or plugin.poll() is not None:
                    guard.close()
                else:
                    lifecycle.diagnostic_api_guard = guard
            result["finished_utc"] = utc()
            checkpoint(result)
    return result


def run_mode(mode, foreign_url, foreign_id, session, ssm, lifecycle, evidence,
             current, profile, channel_url, listener_check):
    runtime = verify_runtime()
    result = {"schema": "ssm-auth-diagnostic-v1", "mode": mode, "diagnostic_only": True,
              "cutover_eligible": False, "foreign_access_classified": False, "foreign_token_used": False,
              "scope": "partial_protocol_observation" if mode == "protocol-control" else "auth_binding_observation",
              "runtime": runtime, "protocol_progress_observed": False, "current_stable": False,
              "diagnostic_status": "in_progress"}
    evidence["diagnostic"] = result

    def checkpoint():
        # All values originate from this module/parser; no raw payload/exception.
        if lifecycle.session_id:
            lifecycle.persist(lifecycle.public(evidence), initial=False)
            lifecycle.emit(lifecycle.public(evidence))

    def observed(value):
        result["observation"] = value
        result["protocol_progress_observed"] = value["protocol_progress_observed"]
        checkpoint()

    def controlled(value):
        result["official_plugin_original_pair_control"] = value
        checkpoint()

    if mode == "protocol-control":
        own = lifecycle.begin(current, 18995, evidence)
        observe_channel(own["StreamUrl"], own["SessionId"], own, session, channel_url, observed, "C0")
    else:
        require(mode == "auth-binding" and foreign_url and foreign_id, "foreign_synthetic_session_required")
        listener = socket.socket()
        try:
            listener.bind(("127.0.0.1", 0))
            local_port = listener.getsockname()[1]
        finally:
            listener.close()
        own = lifecycle.begin(current, local_port, evidence)
        require(own["SessionId"] != foreign_id, "diagnostic_sessions_not_distinct")
        # This is the first use of freshly returned token A. No token B exists
        # in the service input or wrapper-returned foreign response.
        result["own_token_unused_before_foreign_attempt"] = True
        observation = observe_channel(foreign_url, foreign_id, own, session, channel_url, observed, "A_to_B")
        require(observation["socket_closed"], "diagnostic_foreign_socket_not_closed")
        official_original_pair(own, current, local_port, profile, lifecycle, listener_check, controlled)
    after = ssm.get_parameter(Name="/chatwoot/prod/blue-green/current-instance-id")["Parameter"]["Value"]
    result["current_stable"] = after == current
    require(after == current, "current_changed_during_diagnostic")
    result["diagnostic_status"] = "observations_recorded"
    checkpoint()
