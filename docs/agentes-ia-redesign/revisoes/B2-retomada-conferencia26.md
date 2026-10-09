# B2 — conferência da correção final no snapshot26

**Data:** 2026-10-07
**Alvo:** snapshot `20261007-205528-532a5b7b-520f4c0382-67c2ca60`
**SHA de conteúdo:** `520f4c0382924dfde59d2b1d15757c1855eddaf61541ad06694887a34a0a20f6`
**Escopo:** somente os dois ajustes que ficaram abertos no snapshot25.

## Resultado

**Aprovado nesta conferência focada.** O coordenador informou 222 exemplos Ruby sem falhas ou pendências,
43 testes JavaScript verdes e RuboCop em 106 arquivos sem infrações. Não reabri a revisão geral B2.

## Ajuste 1 — callbacks, ordem e contratos

`AgentsController` registra `fetch_agent` e, logo depois, os três validadores nas linhas 2–5:

1. `validate_public_config_contract`;
2. `validate_actuation_type`;
3. `validate_copilot_actuation`.

O concern `RequestValidation` agora contém somente os métodos privados (`:1-44`), e o controller o inclui
depois do registro (`agents_controller.rb:6`). A sequência preserva o gate de configuração antes do
`agent_params`, a rejeição de valores numéricos do enum antes do assign e a consulta do Copilot apenas
para `internal`/`both`.

O serviço continua consultando CRM, Autonom.ia, Copilot e CRM AI
(`app/services/autonomia/agents/copilot_availability.rb:10-20`), e `ConfigContract` mantém a allowlist
pública (`app/services/autonomia/agents/config_contract.rb:1-47`). Não encontrei mudança semântica ou
regressão nesse ajuste.

## Ajuste 2 — spec Enterprise

O alinhamento do bloco `create(:message, ...)` foi corrigido no arquivo efetivamente executado:
`spec/enterprise/requests/api/v1/accounts/autonomia/agents/analytics_wrong_replies_spec.rb:104-107`.
O conteúdo do caso da nota privada permanece igual; somente a formatação foi ajustada.

## Limite

Este parecer cobre apenas os dois resíduos corrigidos no snapshot26. Não é aceite de F0/F1, das telas reais
ou de uma revisão geral B2. Nenhum código de produto foi editado nesta conferência.
