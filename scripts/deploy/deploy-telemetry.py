#!/usr/bin/env python3
"""Telemetria do blue-green (#2004). Só lê e formata; nunca decide nada do deploy.

Subcomandos:
  sanitize                 stdin -> stdout sem segredos (toda saída coletada da green passa por aqui).
  critical JOBS STATUS     diz se algum passo crítico do Deploy Green falhou ou demorou (uma linha por motivo).
  phases JOBS OUT_JSON     tabela de tempos por fase (markdown no stdout) e o mesmo conteúdo em JSON.

JOBS é a resposta da API do GitHub para os jobs do run (attempts/N/jobs). Se ela faltar ou vier quebrada, o
critical cai no status do job e o phases mostra a tabela vazia, sem falhar.
"""
import json
import os
import string
import sys
from datetime import datetime, timezone

REDACTED = '<REDACTED>'
OPENING_QUOTES = '"\'([{'
# Regra de segredos do Rodrigo e issue #2004: sequência de 32+ caracteres de [A-Za-z0-9_-] some, seja o que for.
MIN_SECRET_LEN = 32
TOKEN_CHARS = frozenset(string.ascii_letters + string.digits + '_-')
# Chave em base64 (ex.: secret da AWS) tem / + =, e partida na barra escaparia da regra acima. Some quando mistura
# maiúscula, minúscula e dígito; caminho de arquivo e URI de imagem quase nunca misturam.
BASE64_CHARS = frozenset(string.ascii_letters + string.digits + '+/=')
# Palavra seguinte a um destes é credencial (cabeçalho Authorization).
AUTH_SCHEMES = ('bearer', 'basic')

DEPLOY_JOB = 'Deploy Green'
BLUE_JOB = 'Desligar a blue'
# Passos críticos da issue #2004 e quanto podem levar antes de contar como "demorou". Limites iniciais, para ajustar
# com a tabela de tempos dos próximos deploys; o waiter do Register estoura em 10 min.
CRITICAL_STEPS = {
    'Wait for green SSM and local health': 20 * 60,
    'Register green target group': 5 * 60,
    'Shift HTTPS listener to green': 3 * 60,
}
# (fase, job, passo). O boot da green vem de fora da API: lançamento da EC2 até o fim do cloud-init.
PHASES = [
    ('Build da imagem', DEPLOY_JOB, 'Build and push image'),
    ('Boot da green', None, None),
    ('Saúde local da green', DEPLOY_JOB, 'Wait for green SSM and local health'),
    ('Registro no target group', DEPLOY_JOB, 'Register green target group'),
    ('Troca dos workers', DEPLOY_JOB, 'Switch Sidekiq workers to green'),
    ('Troca do listener', DEPLOY_JOB, 'Shift HTTPS listener to green'),
    ('Desligamento da blue', BLUE_JOB, 'Stop blue instance and remove older rollback'),
]


def is_assignment_name(name):
    return name.isidentifier() and any(char.isalpha() for char in name)


def redact_word(word):
    body = word.lstrip(OPENING_QUOTES)
    prefix = word[:len(word) - len(body)]
    name, separator, _ = body.partition('=')
    if separator and is_assignment_name(name):
        # NOME=valor no meio da linha (trace do set -x, mensagem de erro), em qualquer caixa: fica só o nome.
        return f'{prefix}{name}={REDACTED}'
    scheme, separator, rest = body.partition('://')
    if separator and '@' in rest:
        # usuário:senha de URL (postgres://, redis://) nunca sai, mesmo curta ou com barra na senha.
        return f"{prefix}{scheme}://{REDACTED}@{rest.rpartition('@')[2]}"
    return word


def redact_runs(text, alphabet, is_secret):
    """Troca por <REDACTED> cada trecho contínuo de `alphabet` com 32+ caracteres que `is_secret` aprova."""
    out, run = [], []

    def flush():
        chunk = ''.join(run)
        out.append(REDACTED if len(chunk) >= MIN_SECRET_LEN and is_secret(chunk) else chunk)
        run.clear()

    for char in text:
        if char in alphabet:
            run.append(char)
        else:
            flush()
            out.append(char)
    flush()
    return ''.join(out)


def mixed_case_with_digit(chunk):
    return any(c.isupper() for c in chunk) and any(c.islower() for c in chunk) and any(c.isdigit() for c in chunk)


def redact_words(line):
    words, word, previous = [], [], ''
    for char in line + '\n':
        if char not in ' \t\n':
            word.append(char)
            continue
        current = ''.join(word)
        word.clear()
        if current:
            redacted = REDACTED if previous.strip(OPENING_QUOTES + ':').lower() in AUTH_SCHEMES else redact_word(current)
            words.append(redacted)
            previous = current
        if char != '\n':
            words.append(char)
    return ''.join(words)


def sanitize_line(line):
    stripped = line.lstrip()
    indent = line[:len(line) - len(stripped)]
    body = stripped[len('export '):].lstrip() if stripped.startswith('export ') else stripped
    name, separator, _ = body.partition('=')
    if separator and name.isidentifier():
        # Linha inteira de env (KEY=VALUE, como no .env): fica só o nome.
        line = f'{indent}{stripped[:len(stripped) - len(body)]}{name}={REDACTED}'
    else:
        line = redact_words(line)
    line = redact_runs(line, TOKEN_CHARS, lambda chunk: True)
    return redact_runs(line, BASE64_CHARS, mixed_case_with_digit)


def sanitize(text):
    return '\n'.join(sanitize_line(line) for line in text.split('\n'))


def load_jobs(path):
    try:
        with open(path, encoding='utf-8') as stream:
            jobs = json.load(stream).get('jobs')
    except (OSError, ValueError, AttributeError):
        return None
    return jobs if isinstance(jobs, list) else None


def parse_time(value):
    if not value:
        return None
    if value.isdigit():
        # Fim do cloud-init chega da green em epoch (stat -c %Y).
        return datetime.fromtimestamp(int(value), timezone.utc)
    try:
        return datetime.fromisoformat(value.replace('Z', '+00:00'))
    except ValueError:
        return None


def find_step(jobs, job_name, step_name):
    for job in jobs or []:
        if job.get('name') != job_name:
            continue
        for step in job.get('steps') or []:
            if step.get('name') == step_name:
                return step
    return None


def duration(start, end):
    if start is None or end is None:
        return None
    return int((end - start).total_seconds())


def human(seconds):
    if seconds is None:
        return '—'
    minutes, rest = divmod(max(seconds, 0), 60)
    return f'{minutes}m{rest:02d}s' if minutes else f'{rest}s'


def critical(jobs_path, job_status):
    jobs = load_jobs(jobs_path)
    reasons = []
    if jobs is None:
        if job_status == 'failure':
            reasons.append('falhou: passo não identificado (API do GitHub indisponível)')
        return reasons
    for name, limit in CRITICAL_STEPS.items():
        step = find_step(jobs, DEPLOY_JOB, name)
        if step is None:
            continue
        if step.get('conclusion') == 'failure':
            reasons.append(f'falhou: {name}')
            continue
        if job_status != 'success':
            # Job falhou noutro passo (ex.: troca de workers, com o worker da blue parado): a limpeza vem logo depois e
            # não pode esperar o SSM por causa de um passo que só demorou.
            continue
        seconds = duration(parse_time(step.get('started_at')), parse_time(step.get('completed_at')))
        if seconds is not None and seconds > limit:
            reasons.append(f'demorou: {name} ({human(seconds)}, limite {human(limit)})')
    return reasons


# Conclusões que a API do GitHub dá a um passo. Repositório público: a tabela leva só passo, duração, horário e uma
# destas; qualquer outro valor vira "outro".
KNOWN_CONCLUSIONS = ('success', 'failure', 'cancelled', 'skipped', 'in_progress', 'queued')


def phase_rows(jobs, boot):
    rows = []
    for label, job_name, step_name in PHASES:
        if job_name is None:
            start = parse_time(boot.get('launch_time'))
            end = parse_time(boot.get('boot_done'))
            conclusion = 'ok' if start and end else 'sem dado'
        else:
            step = find_step(jobs, job_name, step_name)
            start = parse_time(step.get('started_at')) if step else None
            end = parse_time(step.get('completed_at')) if step else None
            conclusion = (step.get('conclusion') or step.get('status')) if step else 'não rodou'
            if step and conclusion not in KNOWN_CONCLUSIONS:
                conclusion = 'outro'
        rows.append({'fase': label, 'passo': step_name or 'lançamento da EC2 → fim do cloud-init',
                     'inicio': start.isoformat() if start else None, 'fim': end.isoformat() if end else None,
                     'segundos': duration(start, end), 'conclusao': conclusion})
    return rows


def phases(jobs_path, out_path):
    jobs = load_jobs(jobs_path)
    boot = {'launch_time': os.environ.get('GREEN_LAUNCH_TIME', ''), 'boot_done': os.environ.get('GREEN_BOOT_DONE', '')}
    rows = phase_rows(jobs, boot)
    deploy_job = next((job for job in jobs or [] if job.get('name') == DEPLOY_JOB), {})
    report = {
        'stack': os.environ.get('DEPLOY_STACK', ''),
        'run_id': os.environ.get('GITHUB_RUN_ID', ''),
        'run_attempt': os.environ.get('GITHUB_RUN_ATTEMPT', ''),
        'sha': os.environ.get('GITHUB_SHA', ''),
        'api_disponivel': jobs is not None,
        'deploy_total_segundos': duration(parse_time(deploy_job.get('started_at')),
                                          parse_time(deploy_job.get('completed_at'))),
        'fases': rows,
    }
    with open(out_path, 'w', encoding='utf-8') as stream:
        json.dump(report, stream, ensure_ascii=False, indent=2)
    lines = [f"### Tempos do deploy ({report['stack']})", '']
    if jobs is None:
        lines += ['API do GitHub indisponível: sem os tempos dos passos.', '']
    lines += ['| Fase | Passo | Duração | Início (UTC) | Conclusão |', '| --- | --- | --- | --- | --- |']
    lines += [f"| {row['fase']} | {row['passo']} | {human(row['segundos'])} | {row['inicio'] or '—'} | {row['conclusao']} |"
              for row in rows]
    lines += ['', f"Job Deploy Green: {human(report['deploy_total_segundos'])}. "
              'Boot da green = lançamento da EC2 até o fim do cloud-init (inclui a espera da imagem do build).']
    return '\n'.join(lines)


def main(argv):
    command = argv[1] if len(argv) > 1 else ''
    if command == 'sanitize':
        sys.stdout.write(sanitize(sys.stdin.read()))
    elif command == 'critical' and len(argv) == 4:
        reasons = critical(argv[2], argv[3])
        if reasons:
            print('\n'.join(reasons))
    elif command == 'phases' and len(argv) == 4:
        print(phases(argv[2], argv[3]))
    else:
        print(__doc__, file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
