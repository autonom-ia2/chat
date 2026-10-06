#!/usr/bin/env python3
"""Run reviewed VPS identity probes and reconcile only sessions created by this proof."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import shlex
import stat
import subprocess
import time
import uuid

BASE = Path(__file__).resolve().parent
AWS = "/Users/rodrigosilva/.local/bin/aws"
ACCOUNTS = {"hub2you": ("354307071110", "hub2you"), "autonomia": ("140023375763", "financial")}
ALLOWED_PUBLIC = {
    "utc", "stack", "account", "role_arn", "assumed_role_arn", "sts_role_exact", "fixed_session_name",
    "credentials_expire_in_seconds", "requested_session_seconds", "expiry_clock_tolerance_seconds", "sts_latency_ms",
    "instance_id", "session_id", "reason", "admin_cleanup_confirmed", "created_utc", "own_session_terminated",
    "admin_cleanup_required", "termination_error", "receipt_error", "plugin_cleanup_error", "plugin_stopped", "failure",
    "own_channel_http", "foreign_channel_http", "foreign_session_terminate_denied", "same_frozen_credentials_used",
    "foreign_token_used", "public_key_fingerprint", "current_stable", "ssm_host_key_document_ok",
    "host_public_key_fingerprint", "ssm_channel_open_ok", "ssh_banner_ok", "transport_scope", "transport_latency_ms",
    "status", "error_type", "foreign_session_id", "foreign_session_terminate_error_code", "diagnostic",
}
DIAGNOSTIC_MODES = ("protocol-control", "auth-binding")
def diagnostic_terminal(record):
    return (record.get("mode") in DIAGNOSTIC_MODES and record.get("state") == "diagnostic_complete" and
            record.get("cutover_eligible") is False and record.get("operation_completion_conclusive") is True and
            record.get("cleanup", {}).get("all_proof_sessions_inactive") is True and
            record.get("evidence", {}).get("own_session_terminated") is True and
            record.get("evidence", {}).get("diagnostic", {}).get("cutover_eligible") is False)

def read_c0(path, directory, stack, account, role_arn, current, sources):
    require(path is not None, "fresh_c0_receipt_required")
    path = Path(path)
    require(path.parent.resolve() == directory.resolve() and path.name.startswith("proof-protocol-control-") and
            path.suffix == ".json", "c0_receipt_path_scope")
    fd = os.open(str(path), os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, "rb") as handle:
        info = os.fstat(handle.fileno())
        require(stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid() and info.st_nlink == 1 and
                stat.S_IMODE(info.st_mode) == 0o600 and info.st_size <= 512*1024, "c0_receipt_owner_mode")
        data = handle.read(512*1024+1)
    record = json.loads(data)
    require(diagnostic_terminal(record) and record["mode"] == "protocol-control" and
            record.get("stack") == stack and record.get("account") == account and
            record.get("role_arn") == role_arn and record.get("instance_id_before") == current and
            record.get("source_sha256") == sources, "c0_context_or_sources_mismatch")
    evidence = record["evidence"]
    diagnostic = evidence.get("diagnostic", {})
    observed = diagnostic.get("observation", {})
    require(evidence.get("instance_id") == current and evidence.get("sts_role_exact") is True and
            diagnostic.get("current_stable") is True and diagnostic.get("protocol_progress_observed") is True and
            diagnostic.get("scope") == "partial_protocol_observation" and observed.get("phase") == "C0" and
            observed.get("http_status") == 101 and observed.get("own_token_send_completed") is True and
            observed.get("socket_closed") is True, "c0_partial_protocol_not_observed")
    stamps = [record["utc"], evidence["utc"], observed["started_utc"], observed["finished_utc"], record["cleanup"]["utc"]]
    values = [datetime.datetime.fromisoformat(value) for value in stamps]
    current_time = datetime.datetime.now(datetime.timezone.utc)
    require(all(value.tzinfo is not None and 0 <= (current_time-value).total_seconds() <= 900 for value in values),
            "c0_not_fresh")
    return {"receipt": path.name, "sha256": hashlib.sha256(data).hexdigest(), "oldest_utc": min(values).isoformat(),
            "instance_id": current, "scope": "partial_protocol_observation"}

def require(value, reason):
    if not value:
        raise RuntimeError(reason)
def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()
def save(path, data, initial=False):
    flags = os.O_WRONLY | os.O_NOFOLLOW
    flags |= os.O_CREAT | os.O_EXCL if initial else 0
    fd = os.open(str(path), flags, 0o600)
    with os.fdopen(fd, "w") as handle:
        info = os.fstat(handle.fileno())
        require(stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid() and info.st_nlink == 1 and
                stat.S_IMODE(info.st_mode) == 0o600, "proof_receipt_owner_mode")
        if not initial:
            os.ftruncate(handle.fileno(), 0)
        json.dump(data, handle, indent=2)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())

class Runner:
    def __init__(self, stack):
        self.stack = stack
        self.account, self.profile = ACCOUNTS[stack]
        self.directory = BASE / stack
        self.role = "chatwoot-instagram-publisher-" + stack + "-vps"
        self.role_arn = "arn:aws:iam::" + self.account + ":role/" + self.role
        self.assumed = "arn:aws:sts::" + self.account + ":assumed-role/" + self.role + "/igpub-" + stack + "-vps"
        self.admin = None

    def aws(self, args):
        require(args[:2] != ["ssm", "start-session"], "start_session_must_use_sdk_without_cli_plugin")
        result = subprocess.run([AWS, "--profile", self.profile, "--region", "us-east-1", "--no-cli-pager",
                                 *args, "--output", "json"], capture_output=True, text=True, timeout=30)
        require(result.returncode == 0, "aws_operation_failed:" + ":".join(args[:2]) + ":" + str(result.returncode))
        return json.loads(result.stdout) if result.stdout.strip() else {}

    def admin_identity(self):
        self.admin = self.aws(["sts", "get-caller-identity"])
        require(self.admin["Account"] == self.account, "admin_account_mismatch")

    def start_foreign(self, target, reason):
        # Use the SDK on the Mac; AWS CLI StartSession would launch its plugin.
        # Administrator credentials remain on the Mac and the bearer token stays in memory.
        import boto3
        from botocore.config import Config
        local = boto3.Session(profile_name=self.profile, region_name="us-east-1")
        config = Config(connect_timeout=5, read_timeout=8, retries={"total_max_attempts": 1})
        identity = local.client("sts", config=config).get_caller_identity()
        require(identity["Account"] == self.account and identity["Arn"] == self.admin["Arn"], "sdk_admin_identity_mismatch")
        response = local.client("ssm", config=config).start_session(
            Target=target, DocumentName="AWS-StartPortForwardingSession",
            Parameters={"portNumber": ["22"], "localPortNumber": ["18996"]}, Reason=reason)
        return {"SessionId": response["SessionId"], "StreamUrl": response["StreamUrl"]}

    def sessions(self):
        # Full automatic CLI pagination stays in memory; only exact proof Reasons are retained.
        return self.aws(["ssm", "describe-sessions", "--state", "Active"])["Sessions"]

    def reconcile(self, record):
        require(record["account"] == self.account and record["role_arn"] == self.role_arn, "proof_identity_mismatch")
        allowed = {record["own_reason"]: self.assumed}
        if record.get("foreign_reason"):
            require(record["admin_arn"] == self.admin["Arn"], "foreign_admin_identity_changed")
            allowed[record["foreign_reason"]] = self.admin["Arn"]
        targets = {}
        if record.get("own_session_id"):
            targets[record["own_session_id"]] = {
                "session_id": record["own_session_id"], "reason": record["own_reason"], "owner": self.assumed,
                "termination_confirmed": record.get("own_service_termination_confirmed") is True,
                "source": "validated_service_response",
            }
        if record.get("foreign_session_id"):
            targets[record["foreign_session_id"]] = {
                "session_id": record["foreign_session_id"], "reason": record["foreign_reason"], "owner": self.admin["Arn"],
                "termination_confirmed": False, "source": "validated_admin_sdk_response",
            }
        for item in self.sessions():
            if item.get("Reason") not in allowed:
                continue
            require(item["Owner"] == allowed[item["Reason"]], "proof_reason_owner_mismatch_no_termination")
            sid = item["SessionId"]
            if sid in targets:
                require(targets[sid]["reason"] == item["Reason"] and targets[sid]["owner"] == item["Owner"],
                        "known_session_metadata_mismatch")
            else:
                targets[sid] = {"session_id": sid, "reason": item["Reason"], "owner": item["Owner"],
                                "termination_confirmed": False, "source": "exact_reason_owner_discovery"}
        result = []
        for sid, row in targets.items():
            # A returned ID is a cleanup target even before DescribeSessions lists it.
            if not row["termination_confirmed"]:
                row["admin_termination_attempted"] = True
                try:
                    answer = self.aws(["ssm", "terminate-session", "--session-id", sid])
                    require(answer.get("SessionId") == sid, "termination_response_mismatch")
                    row["termination_confirmed"] = True
                    row["termination_confirmation"] = "terminate_session_response"
                except Exception as error:
                    row["error_type"] = type(error).__name__
                    # An earlier attempt may already have completed. History is a
                    # positive confirmation; an empty Active list alone is insufficient.
                    history = self.aws(["ssm", "describe-sessions", "--state", "History", "--filters",
                                        json.dumps([{"key": "SessionId", "value": sid}])])["Sessions"]
                    exact = [item for item in history if item.get("SessionId") == sid and item.get("Reason") == row["reason"]
                             and item.get("Owner") == row["owner"] and item.get("Status") == "Terminated"]
                    if len(exact) == 1:
                        row["termination_confirmed"] = True
                        row["termination_confirmation"] = "exact_terminated_history"
            result.append(row)
        remaining = []
        for attempt in range(6):
            remaining = [{"session_id": item["SessionId"], "reason": item.get("Reason")}
                         for item in self.sessions() if item.get("Reason") in allowed]
            if not remaining:
                break
            if attempt < 5:
                time.sleep(0.5)
        return {"utc": now(), "sessions": result, "remaining": remaining, "all_proof_sessions_inactive": not remaining and all(row["termination_confirmed"] for row in result)}

    def execute(self, mode, c0_receipt=None):
        for path in self.directory.glob("proof-*.json"):
            old = json.loads(path.read_text())
            if old.get("executor") == "probe-client-from-mac-v1":
                require(old.get("state") in ("passed", "failed_reconciled") or diagnostic_terminal(old), "unresolved_proof_requires_reconciliation:" + path.name)
        if mode == "start-session":
            require(not (self.directory / "session-prefix-proof.json").exists(), "prefix_proof_exists_no_repeat_needed")
        identity = json.loads((self.directory / "provisioned-disabled.json").read_text())
        require(identity["account"] == self.account and identity["role_arn"] == self.role_arn, "iam_receipt_identity")
        profile = self.aws(["rolesanywhere", "get-profile", "--profile-id", identity["profile_id"]])["profile"]
        require(profile["enabled"] is True and profile["profileArn"] == identity["profile_arn"] and
                profile["roleArns"] == [self.role_arn], "profile_not_enabled_for_approved_probe")
        current = self.aws(["ssm", "get-parameter", "--name", "/chatwoot/prod/blue-green/current-instance-id"])["Parameter"]["Value"]
        nonce = uuid.uuid4().hex
        source = (BASE / "service-proof.py").read_text()
        modules = {}
        sources = {"service-proof.py": hashlib.sha256(source.encode()).hexdigest(),
                   "probe-client-from-mac.py": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
        if mode in DIAGNOSTIC_MODES:
            for name in ("ssm_metadata", "ssm_close_diagnostic", "auth_diagnostic"):
                modules[name] = (BASE / (name + ".py")).read_text()
                sources[name + ".py"] = hashlib.sha256(modules[name].encode()).hexdigest()
        c0 = read_c0(c0_receipt, self.directory, self.stack, self.account, self.role_arn, current, sources) if mode == "auth-binding" else None
        require(c0_receipt is None or mode == "auth-binding", "c0_receipt_only_for_auth_binding")
        path = self.directory / ("proof-" + mode + "-" + nonce + ".json")
        record = {
            "executor": "probe-client-from-mac-v1", "utc": now(), "stack": self.stack, "account": self.account,
            "role_arn": self.role_arn, "admin_arn": self.admin["Arn"], "instance_id_before": current,
            "mode": mode, "proof_id": nonce, "own_reason": "InstagramRuntime995:" + self.stack + ":" + nonce,
            "service_source_sha256": hashlib.sha256(source.encode()).hexdigest(), "state": "intent_recorded_before_remote_action",
        }
        if mode in DIAGNOSTIC_MODES:
            record["source_sha256"] = sources
            record["cutover_eligible"] = False
            record["diagnostic_only"] = True
            if c0:
                record["c0"] = c0
        if mode in ("channel-matrix", "termination-matrix", "auth-binding"):
            record["foreign_reason"] = "InstagramRuntime995:foreign:" + self.stack + ":" + nonce
        save(path, record, initial=True)
        primary, process_code, failure = None, None, None
        remote_source = source
        if modules:
            bootstrap = "import sys, types\n"
            for name, content in modules.items():
                bootstrap += "_module = types.ModuleType(" + repr(name) + ")\n"
                bootstrap += "sys.modules[" + repr(name) + "] = _module\n"
                bootstrap += "exec(compile(" + repr(content) + ", " + repr(name + ".py") + ", 'exec'), _module.__dict__)\n"
            remote_source = bootstrap + source
        try:
            argv = ["/usr/sbin/runuser", "-u", "igpub-" + self.stack, "--", "/usr/bin/python3", "-",
                    "--stack", self.stack, "--mode", mode, "--proof-id", nonce]
            if mode in ("channel-matrix", "termination-matrix", "auth-binding"):
                record["creation_outcome"] = "pending"
                save(path, record)
                foreign = self.start_foreign(current, record["foreign_reason"])
                record["creation_outcome"] = "returned"
                record["foreign_session_id"] = foreign["SessionId"]
                if mode in ("channel-matrix", "auth-binding"):
                    stream = foreign["StreamUrl"]
                    record["foreign_stream_url_sha256"] = hashlib.sha256(stream.encode()).hexdigest()
                foreign.pop("TokenValue", None)
                if mode == "termination-matrix":
                    foreign.pop("StreamUrl", None)
                save(path, record)
                argv += ["--foreign-session-id", foreign["SessionId"]]
                if mode in ("channel-matrix", "auth-binding"):
                    argv += ["--foreign-stream-url-env", "IGPUB_FOREIGN_STREAM_URL"]
                    # The opaque AWS cell-number stays off argv and out of receipts.
                    # SSH stdin sets one temporary environment value; the service
                    # consumes it before identity setup and before clearing its env.
                    remote_source = "import os\nos.environ['IGPUB_FOREIGN_STREAM_URL'] = " + repr(stream) + "\n" + remote_source
            ssh = ["/usr/bin/ssh", "-T", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
                   "-o", "HostKeyAlgorithms=ssh-ed25519", "-o", "ForwardAgent=no", "-o", "UpdateHostKeys=no",
                   "-o", "ConnectTimeout=8", "n8n", shlex.join(argv)]
            record["remote_outcome"] = "pending"
            if mode != "identity":
                record["own_creation_outcome"] = "pending"
            save(path, record)
            proc = subprocess.run(ssh, input=remote_source, capture_output=True, text=True, timeout=120)
            process_code = proc.returncode
            if process_code != 255:
                record["remote_outcome"] = "returned"
            public = []
            for line in proc.stdout.splitlines():
                if not line.strip():
                    continue
                row = json.loads(line)
                require(isinstance(row, dict) and set(row).issubset(ALLOWED_PUBLIC), "unexpected_public_output_shape")
                if row.get("session_id"):
                    require(row.get("stack") == self.stack and row.get("account") == self.account and
                            row.get("role_arn") == self.role_arn and row.get("reason") == record["own_reason"],
                            "returned_session_identity_reason_mismatch")
                    sid = row["session_id"]
                    require(isinstance(sid, str) and all(c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-" for c in sid),
                            "returned_session_id_format")
                    require(not record.get("own_session_id") or record["own_session_id"] == sid, "multiple_own_session_ids")
                    record["own_session_id"] = sid
                    record["own_creation_outcome"] = "returned"
                    if row.get("own_session_terminated") is True:
                        record["own_service_termination_confirmed"] = True
                if mode in DIAGNOSTIC_MODES and "diagnostic" in row:
                    diagnostic = row["diagnostic"]
                    require(isinstance(diagnostic, dict) and diagnostic.get("diagnostic_only") is True and
                            diagnostic.get("cutover_eligible") is False, "invalid_diagnostic_output")
                public.append(row)
                if row.get("sts_role_exact") is True:
                    primary = row
            record["public_results"] = public
            record["process_exit"] = process_code
            if primary:
                require(primary["account"] == self.account and primary["role_arn"] == self.role_arn, "service_proof_identity_mismatch")
                require(primary.get("reason", record["own_reason"]) == record["own_reason"], "service_proof_reason_mismatch")
            record["state"] = "remote_returned"
            save(path, record)
            require(process_code == 0 and primary is not None, "service_proof_failed")
            require(primary.get("assumed_role_arn") == self.assumed and primary.get("sts_role_exact") is True,
                    "service_assumed_role_not_exact")
            if mode in DIAGNOSTIC_MODES:
                diagnostic = primary.get("diagnostic", {})
                require(primary.get("own_session_terminated") is True and diagnostic.get("diagnostic_only") is True and
                        diagnostic.get("cutover_eligible") is False and diagnostic.get("foreign_access_classified") is False and
                        diagnostic.get("foreign_token_used") is False and diagnostic.get("mode") == mode and
                        diagnostic.get("diagnostic_status") == "observations_recorded" and
                        diagnostic.get("current_stable") is True and primary.get("instance_id") == current,
                        "diagnostic_contract_incomplete")
                require(diagnostic.get("observation", {}).get("socket_closed") is True, "diagnostic_socket_cleanup_incomplete")
                if mode == "auth-binding":
                    require(primary.get("foreign_session_id") == record["foreign_session_id"] and
                            diagnostic.get("own_token_unused_before_foreign_attempt") is True and
                            diagnostic.get("official_plugin_original_pair_control", {}).get("plugin_stopped") is True,
                            "auth_diagnostic_control_cleanup_incomplete")
                # The diagnostic remains unclassified even with a complete A
                # control. No failed/missing positive control becomes a denial.
            elif mode == "start-session":
                require(primary.get("session_id") and primary.get("fixed_session_name") == "igpub-" + self.stack + "-vps",
                        "prefix_proof_incomplete")
            elif mode in ("transport", "channel-matrix", "termination-matrix"):
                require(primary.get("own_session_terminated") is True, "service_itself_must_terminate_own_session")
                if mode == "transport":
                    require(all(primary.get(key) is True for key in
                                ("current_stable", "ssm_host_key_document_ok", "ssm_channel_open_ok", "ssh_banner_ok")),
                            "transport_proof_incomplete")
                elif mode == "channel-matrix":
                    require(primary.get("own_channel_http") == 101 and primary.get("foreign_channel_http") == 403 and
                            primary.get("foreign_session_terminate_denied") is True and
                            primary.get("same_frozen_credentials_used") is True and primary.get("foreign_token_used") is False,
                            "channel_matrix_proof_incomplete")
                else:
                    require(primary.get("foreign_session_id") == record["foreign_session_id"] and
                            primary.get("foreign_session_terminate_denied") is True and
                            primary.get("foreign_session_terminate_error_code") in ("AccessDenied", "AccessDeniedException"),
                            "termination_matrix_proof_incomplete")
            record["evidence_validated"] = True
        except Exception as error:
            failure = str(error) if isinstance(error, RuntimeError) else type(error).__name__
            record["failure"] = failure
        finally:
            try:
                cleanup = self.reconcile(record)
                record["cleanup"] = cleanup
                conclusive = all(record.get(key) != "pending" for key in ("creation_outcome", "remote_outcome", "own_creation_outcome", "host_command_outcome"))
                record["operation_completion_conclusive"] = conclusive
                if not conclusive:
                    record["completion_evidence_required"] = "verify_remote_executor_exit_or_ambiguous_sdk_creation_outcome"
                record["state"] = ("failed_reconciled" if failure else "ready_to_finalize") if (
                    cleanup["all_proof_sessions_inactive"] and conclusive) else "cleanup_unresolved"
            except Exception as error:
                record["state"] = "cleanup_unresolved"
                record["cleanup_error"] = str(error) if isinstance(error, RuntimeError) else type(error).__name__
            save(path, record)
        require(record["state"] == "ready_to_finalize" and record.get("evidence_validated") is True,
                "probe_not_passed_reconcile_receipt:" + path.name)
        if mode == "start-session":
            primary["admin_cleanup_confirmed"] = True
            primary["utc"] = now()
            save(self.directory / "session-prefix-proof.json", primary, initial=True)
        record["evidence"] = primary
        record["state"] = "diagnostic_complete" if mode in DIAGNOSTIC_MODES else "passed"
        save(path, record)
        print(json.dumps({"state": record["state"], "receipt": str(path), "evidence": primary, "cleanup": record["cleanup"]}))

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--stack", required=True, choices=ACCOUNTS)
    parser.add_argument("--mode", choices=("identity", "start-session", "transport", "channel-matrix", "termination-matrix", "protocol-control", "auth-binding"))
    parser.add_argument("--reconcile-receipt", type=Path)
    parser.add_argument("--c0-receipt", type=Path)
    args = parser.parse_args()
    require(bool(args.mode) != bool(args.reconcile_receipt), "choose_mode_or_reconciliation")
    runner = Runner(args.stack)
    runner.admin_identity()
    if args.reconcile_receipt:
        path = args.reconcile_receipt.resolve()
        require(path.parent == runner.directory.resolve() and path.name.startswith("proof-"), "reconciliation_path_scope")
        record = json.loads(path.read_text())
        require(record.get("executor") == "probe-client-from-mac-v1", "reconciliation_receipt_type")
        record["cleanup"] = runner.reconcile(record)
        # Cleanup alone cannot conclude a timed-out SSH/SDK creation. Keep that gate
        # unresolved until its actual completion is independently established.
        conclusive = all(record.get(key) != "pending" for key in ("creation_outcome", "remote_outcome", "own_creation_outcome", "host_command_outcome"))
        record["state"] = "failed_reconciled" if (record["cleanup"]["all_proof_sessions_inactive"] and conclusive) else "cleanup_unresolved"
        save(path, record)
        print(json.dumps({"state": record["state"], "receipt": str(path), "cleanup": record["cleanup"]}))
        require(record["state"] == "failed_reconciled", "proof_session_cleanup_still_unresolved")
    else:
        runner.execute(args.mode, args.c0_receipt)

if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(json.dumps({"status": "failed", "reason": str(error) if isinstance(error, RuntimeError) else type(error).__name__}))
        raise SystemExit(1)
