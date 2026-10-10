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
6. O `preflight` exige systemd ≥ 252 (`systemctl kill --kill-whom`; a VPS roda Ubuntu 24.04, systemd 255)
   e o horário de início legível (`ExecMainStartTimestamp`) de toda unit ativa. Sem ele o `verify` não
   saberia desde quando ler o journal.

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
alguma operação foi interrompida e se o lock sumiu. A leitura do journal faz `journalctl --sync` e só vale
com o marcador de fim; leitura incompleta conta como operação interrompida. Então para as outras units, roda o instalador
validado (`systemd-run --wait --collect ... BindReadOnlyPaths=<node privado>:/usr/bin/node`), confere
`current`, o manifesto da release, o `verify-pair` e os drop-ins e overrides. Sobe display e gateway
(401 sem `Set-Cookie`), o publisher (sonda que conecta no socket sem escrever) e o manager. Por fim
observa 180 s de bootstrap. ETA ≈ 8 min.

## Códigos de saída

| Código | Significado | O que fazer |
|---|---|---|
| 0 | ok | — |
| 2 | precondição falhou, **nada mudou** | ler as linhas `FAIL`, corrigir, repetir |
| 2 `manager_term_failed` | o SIGTERM não foi entregue; o manager segue como estava | ler a causa; nada a desfazer |
| 3 | falhou depois de mudar algo | rodar o comando `rollback:` impresso |
| 3 `manager_stop_timeout` + `nada_trocado` | SIGTERM entregue, o manager não saiu em 40 s; `current` segue PREV | esperar ele sair (o `Restart=on-failure` religa em PREV com `NRestarts=1`) e rodar o `rollback:` impresso, que para tudo, zera o contador e religa PREV limpo |
| 3 + `operation_outcome_uncertain` | a parada interrompeu uma operação, ou o journal não pôde ser lido por inteiro | rollback; **não** repetir a operação; reconciliar no Rails |
| 3 `vps_release_stage_failed` | só o stage ficou incompleto | ver "Limpeza" |
| 4 | runtime ok, a sessão Meta pede uma pessoa | depois de um `install`, PREV estava saudável no backup e a decisão de rollback é sua: o `rollback:` impresso já leva `--stop-operator-waiter` (ver "Waiter do operador"). Em `verify` avulso ou depois de um rollback, o rollback não resolve |

## Units habilitadas no boot e reboot no meio da janela

As 8 units estão `enabled` desde 2026-10-07: o runtime volta sozinho depois de um boot da VPS. A
ferramenta não habilita nem desabilita units; o `preflight` só exige que as 8 tenham o mesmo estado
(`enabled` ou `disabled`), e o `install` confere o estado de cada uma contra o backup.

Se a VPS reiniciar entre a parada e a subida do `install`, as units sobem sozinhas na release para a
qual `current` aponta. Ela é sempre PREV ou NEW inteira, porque o instalador troca o link por
`mv -T` atômico. Esse boot pula as checagens de fila, de janela humana, o `wait_bootstrap` de 180 s e
os `pair_ready`/`publisher_ready` do `start_runtime`. O boot encerra as transientes do `systemd-run`
e apaga o marker em `/run`, que é tmpfs. Ele não encerra pedidos Meta que já tinham sido recebidos,
nem impede o manager religado de aceitar pedidos novos sem verificação. Depois do boot:

1. Até o `verify` dar 0, o manager pode já estar aceitando pedidos. Antes do `verify`, confira
   `ps -o pid=,args= -u ig-<stack>` e a fila no Rails (0 queued e 0 running). Depois rode
   `python3 $T verify --sha <release de current> --backup <path>`. Se o backup sumiu de `/tmp`, use
   `--units-active` explícito.
2. `current` = NEW só prova que o link foi trocado, não que o runtime foi validado depois do boot. Só
   considere a instalação concluída com `current` = NEW **e** `verify` 0; depois valide como de costume.
3. Em qualquer outro caso, rode o `rollback:` do runbook. Não repita a operação Meta que estava em
   andamento; reconcilie no Rails.

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
Pode ser repetido. `rollback_noop` exige também `NRestarts=0` em todas as units: um manager que
reiniciou sozinho é religado limpo. Se o backup sumiu de `/tmp` (por exemplo depois de um boot), informe as units
explicitamente: `--units-active hub2you=display,gateway,publisher,manager --units-active autonomia=...`.

## Waiter do operador

Quando o `session-manager.mjs` sai com 2 (a sessão Meta pede uma pessoa), o `manager.sh` sobe o
`runtime/operator-waiter.mjs`, que fica esperando um pedido humano pelo Rails por até 1 h, em laço.
O `install` nunca para um waiter. O `rollback` só para com `--stop-operator-waiter`, dado de propósito,
e mesmo assim recusa (código 2, nada parado) quando há uma pessoa no meio do pedido:

- marcador `/run/instagram-<stack>/browser-request.json` presente (navegador aberto para a pessoa); ou
- algum processo `session-browser.mjs` ou `session-manager.mjs` do `ig-<stack>`: com o waiter vivo, eles
  só existem como filhos dele, isto é, um pedido já reivindicado.

Parar um waiter ocioso descarta só a espera; a sessão continua pedindo uma pessoa em PREV, se for o
caso, e o `verify` do rollback devolve 4. Janela residual: entre o claim no Rails e o filho subir, o
pedido existe sem processo visível na VPS. Se isso acontecer, o waiter devolve o pedido como `failed`
ao receber o SIGTERM, e a pessoa refaz o pedido.

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
