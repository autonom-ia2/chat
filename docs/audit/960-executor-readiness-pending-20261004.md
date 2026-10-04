# #960 — patch local de espera e pendência

Escopo autorizado: somente a cópia `tmp/reuse-auth-20261004/executor-current.py`,
preservando antes da edição `executor-original.py`. Branch existente:
`release/2026-10-04-instagram-960`, nó local M4. Alterações preexistentes preservadas.

Delta: 30 linhas adicionadas, 5 removidas. A classificação de instalação existente
mantém as verificações de arquivos/configuração e aguarda até 25 segundos totais
por unit active/running e listeners 16380/16381 no gateway Docker bridge exato.
Somente consultas locais nessa espera; nenhuma chamada Meta, restart ou retry do smoke.
O main local bloqueia qualquer pending não nulo antes de consultas AWS ou novos comandos.
Não consulta/retoma a pendência antiga; a reconciliação cabe ao parent.

Smoke, igualdade do egress ao Direct, guards, stdin/TTY e confirmação humana preservados.
Evidência anterior consultada: `960-final-orchestration-20261004.md`,
`960-proxy-upstream-canonical.md` e `m4-direct-proxy-proof.json`.
Nenhuma nova prova real de transporte/autenticação foi executada nesta rodada.

SHA-256 original: `912debdaf8b4bfb7e186d5fd4403f281eb2475c593b1dc21854d3b83cf28edc7`.
SHA-256 patch: `ca83f3babbae592ee3e1bb263c9cb6ba45e332860b50726d7ac751d934f60d7b`.
Runner intacto: `8a90b556813d14a66a288c49d8a9b4fb6e7a16905127dbc1313c8a9d122ae4cf`.
Seu hash esperado ainda aponta para o original; precisa de reconciliação pelo parent
com o novo SHA antes de executar. O helper continua chamando main(), sem mudança.

Planner: `maccluster work plan -- python3 -I tmp/reuse-auth-20261004/scratch-readiness/test_executor.py`
selecionou M4, excluindo M2 offline. Execução sintética local em ambiente limpo:
`env -i PATH=/usr/bin:/bin /Users/rodrigosilva/.local/bin/python3 -I -B tmp/reuse-auth-20261004/scratch-readiness/test_executor.py`.
Resultado final: 15 testes aprovados, incluindo latência no orçamento de 25s,
portas ausentes/gateway errado, pendência preservada sem chamadas remotas,
estado ausente/livre, TTY e uma confirmação. Subprocessos reais proibidos pelos mocks.
Compilação local/remota e whitespace do diff aprovados.

Diff: `tmp/reuse-auth-20261004/executor-readiness.patch`.
Sem leitura de secrets/logs, AWS/SSH/Docker reais, alteração do runner/rede,
instalação, merge ou deploy. Entrega local ao parent; sem publicação de PR/Project nesta rodada.
