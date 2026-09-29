"""Only fixed operations; no user-supplied shell, credentials, database URLs or file paths."""
import base64
import json
import gzip
import io
import os
from pathlib import Path
import shlex
import subprocess
import time

ACTIONS = {"preflight", "enable", "verify", "disable"}
ACCOUNTS = {"hub2you": "354307071110", "autonomia": "140023375763"}
PREFIX = "/chatwoot/prod/blue-green/"
MARKER = "RELATIONSHIPS_OPS_RESULT "


def aws(*args):
    result = subprocess.run(["aws", "--region", "us-east-1", *args, "--output", "json"],
                            capture_output=True, text=True, timeout=45, check=True)
    return json.loads(result.stdout)


def validate(action, tenant, account, sha):
    if action not in ACTIONS or ACCOUNTS.get(tenant) != account:
        raise ValueError("Unsupported action or stack")
    if len(sha) != 40 or any(char not in "0123456789abcdef" for char in sha):
        raise ValueError("Expected an exact lower-case 40-character commit")


def preflight(account):
    if aws("sts", "get-caller-identity")["Account"] != account:
        raise RuntimeError("AWS account does not match the selected stack")
    keys = ["current-instance-id", "previous-instance-id", "current-target-group-arn", "previous-target-group-arn"]
    parameters = aws("ssm", "get-parameters", "--names", *[PREFIX + key for key in keys])
    if parameters.get("InvalidParameters"):
        raise RuntimeError("Rollback metadata is missing")
    values = {p["Name"].split("/")[-1]: p["Value"] for p in parameters["Parameters"]}
    ids = [values["current-instance-id"], values["previous-instance-id"]]
    instances = aws("ec2", "describe-instances", "--instance-ids", *ids)
    states = {i["InstanceId"]: i["State"]["Name"] for r in instances["Reservations"] for i in r["Instances"]}
    if ids[0] == ids[1] or states.get(ids[0]) != "running" or states.get(ids[1]) not in {"running", "stopped"}:
        raise RuntimeError("Current instance or previous rollback is unavailable")
    health = aws("elbv2", "describe-target-health", "--target-group-arn", values["current-target-group-arn"])
    if not any(i["Target"]["Id"] == ids[0] and i["TargetHealth"]["State"] == "healthy" for i in health["TargetHealthDescriptions"]):
        raise RuntimeError("Current load-balancer target is not healthy")
    previous = aws("elbv2", "describe-target-health", "--target-group-arn", values["previous-target-group-arn"])
    if not any(i["Target"]["Id"] == ids[1] for i in previous["TargetHealthDescriptions"]):
        raise RuntimeError("Previous instance is not registered in the rollback target group")
    lb = aws("elbv2", "describe-load-balancers", "--names", "chatwoot-autonomia-prod-ec2")["LoadBalancers"][0]
    listeners = aws("elbv2", "describe-listeners", "--load-balancer-arn", lb["LoadBalancerArn"])["Listeners"]
    https = next(item for item in listeners if item["Port"] == 443)
    if https["DefaultActions"][0].get("TargetGroupArn") != values["current-target-group-arn"]:
        raise RuntimeError("HTTPS target and SSM current pointer disagree")
    return {**values, "instance_states": states, "https_target_confirmed": True}


def decode_report(text):
    envelope = json.loads(text)
    if envelope.get("encoding") != "gzip-base64":
        raise ValueError("Unsupported report encoding")
    compressed = base64.b64decode(envelope["payload"], validate=True)
    with gzip.GzipFile(fileobj=io.BytesIO(compressed)) as stream:
        content = stream.read(1_000_001)
    if len(content) > 1_000_000:
        raise ValueError("Runtime report exceeds its decoded size limit")
    return json.loads(content)


def invoke(instance, action, sha, on_command=None):
    source = Path(".github/scripts/relationships_runtime_ops.rb").read_bytes()
    payload = base64.b64encode(source).decode("ascii")
    command = "\n".join([
        "set -eu",
        "sudo systemctl is-active --quiet chatwoot-web.service",
        "sudo systemctl is-active --quiet chatwoot-worker.service",
        "test \"$(sudo docker exec chatwoot-web cat /app/.git_sha)\" = " + shlex.quote(sha),
        "test \"$(sudo docker exec chatwoot-worker cat /app/.git_sha)\" = " + shlex.quote(sha),
        "printf '%s' " + shlex.quote(payload) + " | base64 --decode | sudo docker exec -i "
        + "-e RELATIONSHIPS_OP_ACTION=" + shlex.quote(action) + " -e RELATIONSHIPS_EXPECTED_SHA=" + shlex.quote(sha)
        + " chatwoot-web bundle exec rails runner -",
    ])
    sent = aws("ssm", "send-command", "--instance-ids", instance, "--document-name", "AWS-RunShellScript",
               "--timeout-seconds", "300", "--comment", "Issue757 controlled relationships " + action,
               "--parameters", json.dumps({"commands": [command], "executionTimeout": ["240"]}))
    command_id = sent["Command"]["CommandId"]
    if on_command:
        on_command(command_id)
    deadline = time.monotonic() + 310
    while time.monotonic() < deadline:
        time.sleep(3)
        try:
            result = aws("ssm", "get-command-invocation", "--command-id", command_id, "--instance-id", instance)
        except subprocess.CalledProcessError:
            continue
        if result["Status"] in {"Pending", "InProgress", "Delayed"}:
            continue
        # Never publish raw Rails output, request bodies, user data or credentials.
        matches = [line[len(MARKER):] for line in result.get("StandardOutputContent", "").splitlines() if line.startswith(MARKER)]
        if result["Status"] != "Success" or len(matches) != 1:
            print(json.dumps({"command_id": command_id, "status": result["Status"], "operation_failed": True}))
            raise RuntimeError("Runtime operation failed; inspect the scoped SSM command securely")
        return {"command_id": command_id, "application": decode_report(matches[0])}
    raise TimeoutError("SSM operation did not complete in its bounded window")


def main():
    action, tenant, account, sha = [os.environ[key] for key in ["OP_ACTION", "OP_TENANT", "OP_ACCOUNT", "OP_EXPECTED_SHA"]]
    validate(action, tenant, account, sha)
    report = {"tenant": tenant, "action": action, "expected_sha": sha, "status": "started"}
    Path("artifacts").mkdir(exist_ok=True)
    output = Path(f"artifacts/relationships-operations-{tenant}-{action}.json")

    def persist_command(command_id):
        report["command_id"] = command_id
        output.write_text(json.dumps(report, indent=2))

    try:
        report["before"] = preflight(account)
        output.write_text(json.dumps(report, indent=2))
        report.update(invoke(report["before"]["current-instance-id"], action, sha, persist_command))
        output.write_text(json.dumps(report, indent=2))
        report["after"] = preflight(account)
        if report["before"]["current-instance-id"] != report["after"]["current-instance-id"]:
            raise RuntimeError("A concurrent deployment changed the current instance")
        report["status"] = "success"
    except Exception as error:
        report["status"] = "failed"
        report["error_type"] = type(error).__name__
        raise
    finally:
        output.write_text(json.dumps(report, indent=2))
        print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
