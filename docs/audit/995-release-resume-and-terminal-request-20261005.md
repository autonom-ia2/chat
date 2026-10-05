# #995 — retomada da publicação e pedido terminal — 05/10/2026

> Registro histórico da etapa de preparação. A execução posteriormente autorizada,
> seus recibos e os gates ainda pendentes estão na
> [auditoria operacional de 05/10](995-vps-runtime-operations-20261005.md).
> Os resultados abaixo preservam o contexto e o horário da observação original.

## Escopo e autorização recuperados

Rodrigo pediu continuar o chat “Diferença entre testadores” e ampliar o uso de subagentes.
A autorização explícita para PR #1003, deploy OFF, runtime VPS n8n, identidades
AWS dedicadas, HTTPS privado e rollback já estava registrada:
https://github.com/autonom-ia2/chat/issues/995#issuecomment-5997020246.

A identidade SSH também já tinha confirmação independente pelo console do provedor:
https://github.com/autonom-ia2/chat/issues/995#issuecomment-5994827800.
O acesso de manutenção usa verificação estrita; o registro separado do conector
SSH não foi alterado. Não reiniciar o projeto nem repetir a confirmação já feita.

## Publicação da PR #1003

O chat anterior enfileirou o head `a6084cbc93e128e637ae563c34b4d2cc7175b361`
às 15:01 UTC. Durante esta retomada, a fila concluiu o merge às 15:13:24 UTC:
`b68c94a2f3cdc2492f74847a3fa2ba0b7dae8f04`.
A leitura GitHub e o recibo do watcher confirmam MERGED. Não houve novo dispatch.

- Hub2You: https://github.com/autonom-ia2/chat/actions/runs/37331059255
- Autonom.ia: https://github.com/autonom-ia2/chat/actions/runs/37331059104

Conferência real após a troca do tráfego:

| Stack | Horário UTC | Instância CURRENT | SSM de leitura |
| --- | --- | --- | --- |
| Hub2You | 15:23:43 | `i-06a683f197980ef20` | `77c1344e-20ba-44cf-a7d8-87a65410e0a5` |
| Autonom.ia | 15:23:54 | `i-0fc4a7b5611bf768e` | `938dc9ee-33e1-492e-bcd1-990e17a6f143` |

Nas duas instâncias: SSM Success/exit 0; web/worker running no SHA de merge;
`INSTAGRAM_TESTER_AUTOMATION_ENABLED=false` em ambos os containers; API HTTP 200.
CURRENT, listener HTTPS, target group e alvo saudável correspondiam à mesma
instância antes da consulta; CURRENT permaneceu estável depois dela.
Hashes de ticket, gateway e manager corresponderam ao conteúdo da release #1003.
Isso comprova publicação e OFF naquele horário, não instalação VPS nem sessão Meta.

O verificador `tmp/approved-1003-20261005/verify-resume-postdeploy.py` executou
somente observações de containers/API/hashes e registrou recibos sanitizados
em `postdeploy-resume-*/{hub2you,autonomia}.json`. Não chamou Meta, publicou
sessão, alterou Redis, reiniciou serviço ou copiou credenciais.

## Correção do achado P2

Fonte: https://github.com/autonom-ia2/chat/pull/1003#discussion_r4183544270.
`OperatorControl#complete` encerra a tentativa como `operator_required`, mas o
ticket ainda aceitava esse estado. A UI emitia um ticket cujo gateway esperava
um marcador que nunca voltaria para aquele request ID.

A única alteração de produção restringe `ACTIVE_STATES` a `queued` e `running`.
UI e endpoint já compartilham `eligible?`; o pedido terminal deixa de exibir o
navegador e o POST antigo retorna o erro 503 existente. O fluxo de Reconectar
permanece disponível quando o waiter anuncia controle, e cria outro UUID.
Nenhuma mudança foi necessária em Redis, gateway, waiter ou formato do ticket.

Validação:
- Controle negativo: 16 exemplos, 3 falhas nos três sintomas.
- Correção: os mesmos 16 exemplos, 0 falhas.
- Repetição sobre a base mergeada `b68c94a2`: 16 exemplos, 0 falhas.
- RuboCop: 3 arquivos, nenhuma infração. Whitespace: exit 0.
- Revisão independente `review_operator_runtime`: diff focal aprovado;
  comparou nove arquivos com a release mergeada e confirmou o contrato terminal.

Os contratos usam Rails/RSpec com ambiente sintético, Dotenv apontado para arquivo
inexistente e banco/Redis em loopback porta 1. O aviso de initializer sem banco
pertence a esse isolamento; não representa teste operacional do runtime.
Evidências em `tmp/operator-ticket-p2-20261005/`. O patch focal tem SHA256
`23fae00748c04c862cbd4a342939c1e309c1ac4c8e2cd844487ec17f36f20b05`.

Como #1003 já havia sido enfileirada no chat anterior, a correção segue separada
na branch `fix/995-instagram-terminal-browser-request`, derivada do merge confirmado.
Não foi enviada para a branch antiga já mergeada.

## Configuração persistente e limites operacionais

O runbook passou a indicar o parâmetro principal `/chatwoot/prod/env`, por conta
AWS, para URL privada, stack e chave de assinatura do navegador. A allowlist do
parâmetro `instagram-tester-env` rejeita essas três entradas; ela não foi alterada.
O gateway usa a origem do `FRONTEND_URL` efetivo do Rails, sem inferir domínio.

A instalação VPS permanece bloqueada pela rejeição automática do instalador
`prepare-dependencies.py` no chat anterior. O handoff registra recusa antes da
execução; não contém justificativa detalhada recuperável. Não apresentar uma
hipótese sobre a causa como motivo fornecido pela ferramenta. O instalador não
foi repetido nem reenviado por outra rota nesta retomada.

A leitura da VPS confirmou dependências/runtime/contas/unidades ainda ausentes
e Serve vazio. A avaliação de AWS não encontrou bloqueio IAM demonstrado, mas
nenhuma identidade foi provisionada. Planos e limites nas auditorias de
dependências e identidade desta mesma issue; produção permanece assistido OFF.

Login/2FA, primeira publicação e renovação automática, HTTPS real, isolamento
entre usuários Linux e retirada dos gestores Mac permanecem sem homologação.
Não marcar #995 concluída, habilitar assistido ou atribuir os resultados CI
a essas etapas. Preservar perfis, outcomes, epochs, Redis geral e dedicado.
