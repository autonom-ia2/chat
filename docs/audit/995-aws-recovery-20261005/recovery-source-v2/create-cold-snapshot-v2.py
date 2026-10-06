#!/usr/bin/env python3
"""Copy only the pinned public allowlist; never import or execute its sources."""
import datetime
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import stat

BASE = Path('/Users/rodrigosilva/dev/worktrees/chat2you/995-instagram-vps-runtime/tmp/approved-1023-20261005')
DEST = BASE / 'recovery/cold-snapshot-v2'
PINS = {
    'https/recovery-source-allowlist-v2.json': '18326e1844d21b6f86b755134128b64724d2bf9c95dc44cd8daeb36620a1cd0c',
    'https/recovery-source-plan-v2.md': '5184877dc3e3117ea6eba1f3bd3f4d0898377fd62c52ea5d97572e3d6f644c38',
    'review/expanded-recovery-source-plan-review.json': '176720ca548aa723b1aace0bf246552629043a62a5b03ef4bebd09bb0726780d',
}


def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def read_regular(path):
    require(path.resolve(strict=True) == path, 'symlink_path_refused')
    before = path.lstat()
    require(stat.S_ISREG(before.st_mode), 'not_regular')
    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW), 'rb') as stream:
        opened = os.fstat(stream.fileno())
        require((before.st_dev, before.st_ino) == (opened.st_dev, opened.st_ino), 'source_replaced')
        data = stream.read()
        after = os.fstat(stream.fileno())
    end = path.lstat()
    identity = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_mode)
    require(identity(before) == identity(after) == identity(end), 'source_changed_during_read')
    return data, {'sha256': digest(data), 'bytes': len(data), 'mode': format(stat.S_IMODE(after.st_mode), '04o')}


def create_file(path, data, mode):
    with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, mode), 'wb') as stream:
        stream.write(data)
        stream.flush()
        os.fchmod(stream.fileno(), mode)
        os.fsync(stream.fileno())


def main():
    started = utc()
    documents = {}
    for relative, expected in PINS.items():
        data, actual = read_regular(BASE / relative)
        require(actual['sha256'] == expected, 'governing_document_hash_mismatch')
        documents[relative] = data
    allowlist = json.loads(documents['https/recovery-source-allowlist-v2.json'])
    files = allowlist['files']
    require(allowlist['original_base'] == str(BASE), 'source_base_mismatch')
    require(len(files) == 54 and sum(not f['optional'] for f in files) == 51, 'counts_mismatch')
    require(len({f['path'] for f in files}) == 54, 'duplicate_path')
    for entry in files:
        relative = PurePosixPath(entry['path'])
        require(not relative.is_absolute() and '..' not in relative.parts and str(relative) == entry['path'], 'invalid_relative_path')
        require(entry['snapshot_relative_path'] == 'sources/' + entry['path'], 'snapshot_mapping_mismatch')
        require(entry['restore_worktree_relative_path'] == 'tmp/approved-1023-20261005/' + entry['path'], 'restore_mapping_mismatch')
        require(entry['mode'] in ('0600', '0644'), 'unexpected_file_mode')
    require(BASE.resolve(strict=True) == BASE, 'source_base_symlink')
    DEST.parent.mkdir(mode=0o700, exist_ok=True)
    require(DEST.parent.resolve(strict=True) == DEST.parent, 'destination_parent_symlink')
    DEST.mkdir(mode=0o700, exist_ok=False)
    (DEST / 'sources').mkdir(mode=0o700)
    records = []
    for entry in files:
        record = {k: entry[k] for k in ('path', 'optional', 'kind', 'group', 'snapshot_relative_path', 'restore_worktree_relative_path')}
        record['expected'] = {k: entry[k] for k in ('sha256', 'bytes', 'mode')}
        record['checked_at'] = utc()
        record['copied'] = False
        try:
            data, observed = read_regular(BASE / entry['path'])
            record['source'] = observed
            require(observed == record['expected'], 'source_drift')
            target = DEST / entry['snapshot_relative_path']
            target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            create_file(target, data, int(entry['mode'], 8))
            record['copied'] = True
            readback, measured = read_regular(target)
            record['snapshot'] = measured
            require(readback == data and measured == record['expected'], 'readback_mismatch')
            record['status'] = 'copied_and_verified'
        except FileNotFoundError:
            record['status'] = 'optional_missing' if entry['optional'] and not record['copied'] else 'required_or_copy_missing'
        except ValueError as error:
            record['status'] = str(error)
        except OSError as error:
            record['status'] = 'filesystem_error'
            record['errno'] = error.errno
        records.append(record)
    counts = {
        'listed': len(records),
        'required': sum(not r['optional'] for r in records),
        'optional': sum(r['optional'] for r in records),
        'copied_and_verified': sum(r['status'] == 'copied_and_verified' for r in records),
        'optional_missing': sum(r['status'] == 'optional_missing' for r in records),
        'failed': sum(r['status'] not in ('copied_and_verified', 'optional_missing') for r in records),
    }
    manifest = {
        'schema_version': 1, 'record_type': 'cold_public_source_snapshot',
        'started_at': started, 'finished_at': utc(), 'source_base': str(BASE),
        'snapshot_base': str(DEST), 'governing_document_sha256': PINS,
        'status': 'complete' if counts['failed'] == 0 else 'partial_with_recorded_exceptions',
        'counts': counts, 'files': records,
        'pending_additions': ['Final AWS sources: separate owner-reviewed allowlist still required', 'DG for the actual future merge: actual SHA and reviewed repin still required'],
        'sources_imported_or_executed': False, 'tests_rerun': False,
        'tracked_files_changed': False, 'operational_state_copied_or_modified': False,
        'restoration_authorizes_execution': False,
    }
    manifest_bytes = (json.dumps(manifest, indent=2, ensure_ascii=False) + '\n').encode()
    create_file(DEST / 'manifest.json', manifest_bytes, 0o600)
    require(read_regular(DEST / 'manifest.json')[0] == manifest_bytes, 'manifest_readback_mismatch')
    readme = '''# Snapshot frio de fontes públicas — revisão 2

O manifesto registra os bytes, hashes, modos, horários e resultado de cada um dos 54 paths nomeados na allowlist aprovada. Confira `status` e cada item antes de usar; uma exceção não foi substituída por outra fonte. Somente itens `copied_and_verified` estão confirmados. Os modos dos arquivos foram preservados; proprietários e timestamps de origem não são reproduzidos.

Para restaurar, confira o SHA-256, tamanho e modo de cada `sources/<path>` contra `manifest.json`. Reponha esse arquivo no `restore_worktree_relative_path` sob `/Users/rodrigosilva/dev/worktrees/chat2you/995-instagram-vps-runtime`, preservando o layout e os modos. Reconcile primeiro qualquer arquivo existente; não sobrescreva divergências, intents, journals, backups ou estado para permitir repetição. Não execute os programas a partir deste snapshot: imports e pins dependem do parentesco original dos diretórios. Restaurar bytes não autoriza qualquer operação real.

O fe0 histórico continua reader de B0/discovery; o cutover corrigido permanece seu irmão `cutover-mac-argv`. O DG histórico incluído é dependência de leitura do producer e não o futuro executor de ativação. Os dois JSONs opcionais de teste são recibos históricos, não suítes executáveis. Planos e env-plan são históricos e não provam prontidão atual. A cláusula histórica de grupo nominal em AUTH_PLAN não cria requisito adicional à autorização vigente de HTTPS privado na Tailnet com JWT SuperAdmin.

Não foram importadas ou executadas fontes, repetidos testes, copiados privados ou alterados estado operacional, Git, serviços ou configurações. Fontes AWS finais e DG para o merge efetivo continuam adições pendentes, com allowlist e hashes próprios. Este snapshot local ainda depende da consolidação Git coordenada pelo root para preservação fora do diretório temporário.
'''.encode()
    create_file(DEST / 'README.md', readme, 0o600)
    require(read_regular(DEST / 'README.md')[0] == readme, 'readme_readback_mismatch')
    print(json.dumps({'status': manifest['status'], 'counts': counts, 'snapshot_base': str(DEST), 'manifest_sha256': digest(manifest_bytes), 'readme_sha256': digest(readme)}, sort_keys=True))
    return 0 if counts['failed'] == 0 else 2


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(json.dumps({'status': 'snapshot_stopped', 'error_type': type(error).__name__}))
        raise SystemExit(3)
