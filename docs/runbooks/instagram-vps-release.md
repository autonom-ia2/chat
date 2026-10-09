# Release do runtime Instagram na VPS — #1180

Ferramenta: `scripts/instagram_testers/runtime/vps/release/vps_release.py` (Python 3, só stdlib).
Ela roda no Mac do operador e fala com a VPS só por `ssh n8n`, com checagem estrita de host key
(`StrictHostKeyChecking=yes`, `HostKeyAlgorithms=ssh-ed25519`), sem agente e sem multiplexação.
Ela usa o `install.py` existente e não o substitui. Contexto e lacunas: runbook
[#995](instagram-vps-runtime-995.md) e [handoff](instagram-assisted-codex-handoff.md).

## O que a ferramenta nunca faz

- Imprimir saída remota, env, journal ou respostas HTTP. Ela imprime só estados, contagens e
  hashes que ela mesma calculou. `.env` só é tocado por `grep -cxF`, que devolve uma contagem.
- Apagar ou mover perfil, cookie, `Singleton*`, `.instagram-manager.lock`, release, stage ou backup.
  O único `mv` é o compare-and-swap de `/opt/instagram-meta/current`.
- `systemctl enable|disable|restart`, SIGKILL, AWS, SSM, Docker, Tailscale, Redis ou Rails.
  `reset-failed` só existe no `rollback`, com as 8 units nomeadas, depois de pará-las.
  (Depois de `TimeoutStopSec`, o próprio `systemctl stop` pode matar restos do cgroup; isso é do systemd.)
- Copiar `node_modules` do Mac. O `npm ci --ignore-scripts` roda na VPS, numa unit transitória,
  com o Node privado e a partir do lock.

## Antes de começar (gates do operador)

1. OK explícito do Rodrigo para a janela: as duas stacks ficam sem Instagram por ~4-5 min.
2. O SHA alvo está mergeado em `main`: `git fetch origin main`. A ferramenta exige
   `<NEW>` contido em `origin/main` e descendente de `<PREV>` (`--allow-downgrade` só com OK).
3. Registrar a revisão Rails/SSM publicada nas duas AWS e confirmar que é compatível com `<NEW>`.
   A ferramenta não toca AWS. A última ativação falhou no canal do lado AWS
   (`docs/audit/995-publisher-sudo-channel-20261008.md`).
4. Logo antes do `install`: fila de operações de navegador com 0 queued e 0 running pelo leitor
   aprovado do Rails, nas duas instalações, e sem janela humana aberta. A VPS não consegue provar
   que a fila está ociosa: o lifecycle só aparece no fim de cada operação. Quando o manager está com
   `INSTAGRAM_TESTER_BROWSER_OPERATIONS_ENABLED=true` (ou o `manager.env` é mais novo que o
   processo), o `install` exige `--queue-idle-confirmed hub2you,autonomia`.
5. A VPS precisa alcançar o registry do npm durante o `stage`.

## Sequência

Rode cada passo primeiro com `--dry-run`. Ele imprime os comandos remotos e não abre SSH.

```sh
T=scripts/instagram_testers/runtime/vps/release/vps_release.py
NEW=<sha mergeado>; PREV=61f20cfd107361a431fda51f02cace751cc4978d
python3 $T --dry-run install --sha $NEW --from $PREV --backup /tmp/instagram-vps_state_20260101T000000Z.json --modules-digest 0000000000000000000000000000000000000000000000000000000000000000
python3 $T preflight --sha $NEW --from $PREV          # só leitura
python3 $T backup    --sha $NEW --from $PREV          # imprime path=/tmp/instagram-vps_state_<UTC>.json
python3 $T stage     --sha $NEW --from $PREV          # imprime modules_digest=<hex>; runtime intocado
python3 $T install   --sha $NEW --from $PREV --backup <path> --modules-digest <hex> [--queue-idle-confirmed ...]
python3 $T verify    --sha $NEW --backup <path>       # pode repetir a qualquer momento
```

O `install` faz, nesta ordem: checagens caras (stage contra o manifesto refeito do `git archive`,
`node_modules` contra o digest do `stage`, `verify-pair.py` da release nova), réplica somente-leitura
das checagens do `install.py`, fila e janela humana. Depois, por stack: relê marcador e waiter,
manda SIGTERM só ao processo principal do manager, espera até 40 s e dá `stop`. Confere no journal se
alguma operação foi interrompida e se o lock sumiu. Então para as outras units, roda o instalador
validado (`systemd-run --wait --collect ... BindReadOnlyPaths=<node privado>:/usr/bin/node`), confere
`current`, o manifesto da release, o `verify-pair` e os drop-ins e overrides. Sobe display e gateway
(401 sem `Set-Cookie`), o publisher (sonda que conecta no socket sem escrever) e o manager. Por fim
observa 180 s de bootstrap. ETA ≈ 8 min.

## Códigos de saída

| Código | Significado | O que fazer |
|---|---|---|
| 0 | ok | — |
| 2 | precondição falhou, **nada mudou** | ler as linhas `FAIL`, corrigir, repetir |
| 3 | falhou depois de mudar algo | rodar o comando `rollback:` impresso |
| 3 + `nao_rodar_rollback` | o manager não saiu em 40 s, nada foi trocado | esperar o auto-restart em PREV e rodar o `verify` impresso |
| 3 + `operation_outcome_uncertain` | a parada interrompeu uma operação | rollback; **não** repetir a operação; reconciliar no Rails |
| 3 `vps_release_stage_failed` | só o stage ficou incompleto | ver "Limpeza" |
| 4 | runtime ok, a sessão Meta pede uma pessoa | depois de um `install`, PREV estava saudável no backup e a decisão de rollback é sua. Em `verify` avulso ou depois de um rollback, o rollback não resolve |

## Rollback

```sh
python3 $T rollback --to $PREV --from $NEW --backup <path>
```

ETA ≈ 6-7 min (o Instagram volta em ≈ 3-4 min). Ele recusa (código 2, nada parado) se o
instalador ou o npm transitório ainda estiver rodando, se `current` não for NEW nem PREV, se
`releases/PREV` ou os templates divergirem, se houver marcador humano ou lock órfão. Para as units,
roda `reset-failed` (zera o start-limit sem apagar estado), faz o compare-and-swap
(`ln -s` + `mv -T`; se `current-PREV` já aponta para PREV, só termina o `mv -T`), sobe na ordem e
verifica. Quando PREV já está rodando com todas as units, ele não muda nada (`rollback_noop`).
Pode ser repetido. Se o backup sumiu de `/tmp` (por exemplo depois de um boot), informe as units
explicitamente: `--units-active hub2you=display,gateway,publisher,manager --units-active autonomia=...`.

## Lock do manager

Um lock vazio e sem dono já ficou para trás numa parada real
(`docs/audit/995-publisher-sudo-channel-20261008.md`). A ferramenta só detecta o lock e para; o
tratamento é do operador, com OK, depois de provar o estado:

```sh
s=hub2you   # ou autonomia
systemctl show -p ActiveState,MainPID instagram-vps-manager@$s.service     # inactive/failed e 0
ps -o pid= -u ig-$s                                                          # vazio
stat -c '%i %U %a %s %F' /var/lib/instagram-$s/profile/.instagram-manager.lock   # ig-$s 600 0
# pasta de auditoria root 0700 no MESMO filesystem (conferir `stat -c %d` dos dois lados)
mv -T /var/lib/instagram-$s/profile/.instagram-manager.lock <pasta-de-auditoria>/$s-$(date -u +%Y%m%dT%H%M%SZ).lock
```

Depois rode de novo o comando que a ferramenta indicou.

## Onde ficam os artefatos

- Stage: `/opt/instagram-meta-staging/release-<SHA>/` (root 0700): `artifact.tar`, `manifest.sha256`,
  `src/`, `npm-ci.log` (0600, nunca impresso) e `stage.json` (recibo).
- Backup: `/tmp/instagram-vps_state_<UTC>.json` (0600, `set -C`). Guarda o estado das units, os hashes e
  os bytes dos drop-ins e overrides, conferidos contra os SHAs conhecidos. Não guarda env, chaves
  nem perfis.
- Releases: `/opt/instagram-meta/releases/<SHA>`. Nenhuma é apagada.

## Limpeza (fora da ferramenta, com OK do Rodrigo)

A ferramenta nunca reaproveita nem apaga stage ou release. Repetir o mesmo SHA depois de um stage
ou instalação parcial é recusado. Prefira um SHA novo. Se for mesmo preciso repetir, com OK e sem
nenhuma unit usando o caminho:

```sh
readlink /opt/instagram-meta/current      # NÃO pode apontar para o SHA a descartar
mv -T /opt/instagram-meta-staging/release-<SHA> /opt/instagram-meta-staging/discarded-<SHA>-$(date -u +%Y%m%dT%H%M%SZ)
mv -T /opt/instagram-meta/releases/<SHA> /opt/instagram-meta/discarded-release-<SHA>-$(date -u +%Y%m%dT%H%M%SZ)
```

## Testes

`python3 -B tests/instagram_testers/vps-release_test.py -v` usa uma VPS falsa e um repositório git
temporário. Não abre SSH nem toca AWS ou Meta. Roda no CI `instagram-tester-onboarding.yml`.
