# #1540 — preflight do Instagram fora do caminho crítico do deploy

Decisão do Rodrigo (14/10/2026): falha só do Instagram assistido não para o deploy. Em 14/10 o
`igcoord/check.sh` falhou três vezes no boot da green e abortou o cloud-init e o deploy inteiro.

## O que muda

- **Boot da green** (`deploy.sh` no user data dos dois workflows): se o instalador do túnel
  (`install-coordination-tunnel.sh`) sair com erro, ou o `check.sh` der um veredito do Instagram, a green
  sobe com `INSTAGRAM_TESTER_AUTOMATION_ENABLED=false` no `instagram-tester.env` (mesmo efeito do
  `suspend-instagram-assisted.py`). Web, worker, `db:chatwoot_prepare` e o preflight do SES seguem.
  Continua fatal: copiar os scripts da imagem (`docker create`/`docker cp`), veredito de host do
  `check.sh`, `check.sh` sem veredito (não chegou a rodar) e qualquer outra falha do boot.
- **Passos via SSM** ("Switch Sidekiq workers to green" e "Shift HTTPS listener to green"):
  `check_green_instagram_or_suspend` em `scripts/deploy/blue-green-recovery.sh`. Só status `Failed` com
  sentinela e veredito do Instagram suspende: mesmo helper da recuperação, mais o marcador, reinício do
  web (e do worker, se ativo); antes de virar o listener, espera o alvo da green voltar a `in-service`.
  Qualquer outro status (TimedOut, Cancelled, InProgress...), JSON ilegível, veredito de host, erro de
  API, da suspensão ou do reinício continua fatal. Marcador presente: não roda o check de novo, só avisa.
  O waiter do SSM desiste em ~100 s; o check lento mas legítimo (60 s de espera do túnel + boot do Rails)
  segue sendo lido a cada 10 s até um status final, com teto de 10 min. O reinício do web espera até
  90 s (18 × 5 s), dentro da janela do waiter.
- **Veredito do `check.sh`** (stderr curto; a saída do Rails vai para o stdout, então o corte de 8000
  caracteres do SSM não perde nada): a sentinela `instagram_coordination_preflight_ran` e uma linha.
  - `instagram_coordination_preflight_failed step=<código>` — Instagram, suspende. Os códigos ficam só
    na `INSTAGRAM_STEPS` do `check.sh`: `tunnel_timeout`, `tunnel_inactive`, `coordination_ping_failed`,
    `proxy_configuration_invalid`, `proxy_preflight_failed` e `rails_preflight_failed` (o script Ruby
    começou — ele avisa com `instagram_coordination_preflight_rails_started` — e saiu com erro comum
    sem classificar; o Ruby já classifica `StandardError` e `ScriptError`). O boot acrescenta
    `tunnel_install_failed`.
  - `instagram_coordination_preflight_host_failed step=<código>` — host/Docker, fatal:
    `host_gateway_unavailable`, `host_docker_failed` (o `docker run` não chegou ao script),
    `host_rails_killed` (o contêiner morreu por sinal, ex. OOM, depois de o script começar) e
    `preflight_failed` (qualquer outra falha inesperada).
  - A sentinela vale em qualquer linha (o `sudo` pode imprimir antes). O parser é o mesmo no boot e no
    runner, e um teste garante que os dois não divergem.
- **Aviso**: `INSTAGRAM_ASSISTED_SUSPENDED step=<código>` no log do cloud-init e no arquivo
  `/opt/chatwoot/instagram-assisted-suspended`; no GitHub Actions, `::warning::` com o mesmo prefixo
  (inclusive quando a suspensão veio de antes do passo). Não havia outro alerta no caminho de recuperação.

## Publisher na green suspensa

O publisher remoto (VPS → `forced-publisher.sh` → `session_publisher.rb`) **não** olha
`INSTAGRAM_TESTER_AUTOMATION_ENABLED`: o `SessionPublisher` exige `INSTAGRAM_TESTER_SESSION_SOURCE=managed`
e proxy válido, não a flag. É o mesmo comportamento da suspensão que a recuperação já fazia na blue. Com o
Instagram suspenso, as telas e jobs do Instagram assistido ficam desligados (`Configuration#enabled?`),
mas a VPS ainda consegue publicar sessão/operador na green. Bloquear isso é decisão à parte.

## Como religar

O Instagram volta no próximo deploy (green nova) ou ao rodar de novo `/opt/chatwoot/deploy.sh` na
instância: ele relê o `instagram-tester.env` do SSM e apaga o marcador.

## Validação local

- `deploy-recovery_test.py`: testes novos do boot (`GreenBootInstagramTest`) e dos passos SSM.
- `coordination-runtime_test.py`: código de cada etapa do `check.sh` e do Ruby.
- `deploy-paths_test.py`, `bash -n` dos scripts e `ruby -c`.
