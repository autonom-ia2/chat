#!/usr/bin/env python3
"""Read-only preflight. Plan-mode provisioner rejects any attempted IAM mutation."""
import argparse
import datetime
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
BASE=Path(__file__).resolve().parent
parser=argparse.ArgumentParser()
parser.add_argument("--stack",choices=("hub2you","autonomia"),required=True)
args=parser.parse_args()
expected={'service-proof.py': 'd878ffe456d30d77b871added475961a3b94d647a997aa2799c7ef56923e3bc3', 'probe-client-from-mac.py': 'e299c0e5d7ad4915185333034ce796cbedd9ebfbb96460078232a16b8b1b52f8', 'auth_diagnostic.py': '161ba3c6235acf2f7b2e7080b38fc77c55e4cbc3b4ccb348d1035543628b961f', 'ssm_close_diagnostic.py': 'b6eb8f232b88a9880e80d39e83bf4caa30044382e69476028c4185066641b4f1', 'ssm_metadata.py': '49866b1cab65ad28f8ed75da20d0ef5223ea3bf23a89b09f9fbf6771c846d2f7', 'provision-identity.py': '5280a18bc67ee5c2be881591415e1971fd0cc458d057ab06f01dfa49bedf7273'}
for name,digest in expected.items():
    if hashlib.sha256((BASE/name).read_bytes()).hexdigest()!=digest:
        raise RuntimeError("reviewed_source_hash_changed")
spec=importlib.util.spec_from_file_location("readonly_provisioner",BASE/"provision-identity.py")
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
p=module.Provisioner(args.stack,"plan",Path("/Users/rodrigosilva/dev/chat2you/.codex/instagram-vps-pki/public"))
snapshot=p.snapshot(include_current=True)
profile=p.set_profile(True)
remote="""import json,subprocess
result={}
for stack in ("hub2you","autonomia"):
    for kind in ("manager","publisher"):
        unit="instagram-vps-"+kind+"@"+stack+".service"
        value=subprocess.run(["/usr/bin/systemctl","show","--property=ActiveState","--value",unit],capture_output=True,text=True,timeout=5)
        if value.returncode or value.stdout.strip()!="inactive":
            raise RuntimeError("VPS_producer_not_inactive")
        result[unit]="inactive"
print(json.dumps(result))
"""
result=subprocess.run(["/usr/bin/ssh","-T","-o","BatchMode=yes","-o","StrictHostKeyChecking=yes",
 "-o","HostKeyAlgorithms=ssh-ed25519","-o","ForwardAgent=no","-o","UpdateHostKeys=no","-o","ConnectTimeout=8",
 "n8n","/usr/bin/python3 -"],input=remote,capture_output=True,text=True,timeout=30)
if result.returncode:
    raise RuntimeError("VPS_inactive_preflight_failed")
receipt={"utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),"stack":args.stack,
 "account":p.account,"role_arn":p.role_arn,"profile_enabled":profile["profile_enabled"],
 "current":snapshot["current"]["instance"],"current_stack_tags_verified":True,
 "trust_inline_and_mappings_exact":True,"source_sha256":expected,"VPS_units":json.loads(result.stdout),
 "AWS_mutations":[]}
stamp=datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
path=BASE/args.stack/("live-proof-preflight-"+stamp+".json")
path.write_text(json.dumps(receipt,indent=2)+"\n")
path.chmod(0o600)
print(json.dumps(receipt))
