#!/usr/bin/env python3
"""Promote only the root-approved A6 diagnostic sources locally; no AWS/VPS operations."""
import datetime,hashlib,json,os,pathlib,stat
BASE=pathlib.Path(__file__).resolve().parent
ROWS=[
  [
    "auth-a6/ssm_close_diagnostic.py",
    "ssm_close_diagnostic.py",
    "ssm_close_diagnostic-reviewed-a5.py",
    "b6eb8f232b88a9880e80d39e83bf4caa30044382e69476028c4185066641b4f1",
    "f8e3da749b14e3427a61f84af927bbb736a372e6b5a1549dc7c2c6806e31d5f0"
  ],
  [
    "auth-a6/preflight-live-proofs-auth-candidate.py",
    "preflight-live-proofs.py",
    "preflight-live-proofs-reviewed-a5.py",
    "0ef4d06ed2a9c223cb77553d3a48bb91e6f12f107422ced2d9088dcdccfe42ae",
    "d78ce8102641d8327fe27e532954c65bc415ed9c729f3c43c73e766ebb75aea8"
  ]
]
MODULES={"service-proof.py":"d878ffe456d30d77b871added475961a3b94d647a997aa2799c7ef56923e3bc3","probe-client-from-mac.py":"e299c0e5d7ad4915185333034ce796cbedd9ebfbb96460078232a16b8b1b52f8","auth_diagnostic.py":"161ba3c6235acf2f7b2e7080b38fc77c55e4cbc3b4ccb348d1035543628b961f","ssm_metadata.py":"49866b1cab65ad28f8ed75da20d0ef5223ea3bf23a89b09f9fbf6771c846d2f7","provision-identity.py":"5280a18bc67ee5c2be881591415e1971fd0cc458d057ab06f01dfa49bedf7273"}
def digest(path):
    info=path.lstat()
    assert stat.S_ISREG(info.st_mode) and info.st_nlink==1 and info.st_uid==os.getuid(),"source_metadata"
    return hashlib.sha256(path.read_bytes()).hexdigest()
def exclusive(path,data):
    fd=os.open(str(path),os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
    with os.fdopen(fd,"wb") as handle:
        handle.write(data);handle.flush();os.fsync(handle.fileno())
def save(path,data,initial=False):
    raw=(json.dumps(data,indent=2)+"\n").encode()
    if initial: exclusive(path,raw)
    else:
        fd=os.open(str(path),os.O_WRONLY|os.O_NOFOLLOW)
        with os.fdopen(fd,"wb") as handle:
            info=os.fstat(handle.fileno());assert stat.S_ISREG(info.st_mode) and info.st_nlink==1 and stat.S_IMODE(info.st_mode)==0o600
            os.ftruncate(handle.fileno(),0);handle.write(raw);handle.flush();os.fsync(handle.fileno())
def main():
    path=BASE/"auth-a6-promotion-20261005.json"
    assert not path.exists(),"promotion_receipt_exists_reconcile"
    for source,target,backup,old,new in ROWS:
        assert digest(BASE/source)==new and digest(BASE/target)==old,"source_hash_mismatch"
        if (BASE/backup).exists():assert digest(BASE/backup)==old,"backup_hash_mismatch"
    for name,value in MODULES.items():assert digest(BASE/name)==value,"module_hash_mismatch"
    receipt={"utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),"state":"intent","scope":"local A6 diagnostic source promotion only","auth_binding_released":False,"module_sha256":MODULES,"promoted":[]}
    save(path,receipt,True)
    try:
        for source,target,backup,old,new in ROWS:
            if not (BASE/backup).exists():exclusive(BASE/backup,(BASE/target).read_bytes())
            assert digest(BASE/backup)==old and digest(BASE/target)==old,"pre_replace_hash_mismatch"
            staged=BASE/(target+".auth-a6-stage")
            exclusive(staged,(BASE/source).read_bytes())
            assert digest(staged)==new,"stage_hash_mismatch"
            os.replace(staged,BASE/target)
            assert digest(BASE/target)==new,"promoted_readback_mismatch"
            receipt["promoted"].append({"target":target,"backup":backup,"previous_sha256":old,"sha256":new})
            save(path,receipt)
        receipt["state"]="promoted_readback_exact";receipt["finished_utc"]=datetime.datetime.now(datetime.timezone.utc).isoformat();save(path,receipt)
        print(json.dumps({"receipt":str(path),**receipt}))
    except Exception as error:
        receipt["state"]="partial_requires_reconciliation";receipt["error_type"]=type(error).__name__;save(path,receipt);raise
if __name__=="__main__":
    try:main()
    except Exception as error:
        print(json.dumps({"status":"failed","error_type":type(error).__name__}))
        raise SystemExit(1)
