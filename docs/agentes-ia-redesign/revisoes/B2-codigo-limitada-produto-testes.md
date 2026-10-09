# Checagem limitada B2 — produto e testes

Data: 2026-10-07

Alvo congelado: snapshot23 em `/Users/Shared/maccluster-workspaces/chat2you/20261007-184308-532a5b7b-9803329751-205ae53c/src`, SHA informado `9803329751ae3fce6fd8cec442e77faa9170b38434587aac62a8e81438e480ad`.

Esta foi uma checagem limitada somente dos achados B2-CODE-01 e B2-CODE-02 já corrigidos. Não executei RSpec, build, banco, navegador ou produção e não alterei código.

## Resultado

**Aprovado nesta checagem limitada.** Não encontrei residual concreto nos dois achados nem dependência incompatível que bloqueie a primeira tela.

## B2-CODE-01 — enum numérico e disponibilidade do Copilot

O controller valida `actuation` antes de `create`/`update` em `app/controllers/api/v1/accounts/autonomia/agents_controller.rb:1-4,93-106`. A entrada precisa ser uma string que exista no enum; `1`, `2`, `"1"` e `"2"` recebem `422` com `code: invalid_enum` antes de qualquer assign. A entrada pública documentada `external`, `internal` e `both` continua chegando ao serviço de disponibilidade de quatro flags (`app/services/autonomia/agents/copilot_availability.rb:10-20`).

Os specs de request cobrem create e PATCH para os números `1` e `2`, verificando ausência de agente, bot, vínculo e alteração parcial do nome (`spec/requests/api/v1/accounts/autonomia/agents/copilot_availability_spec.rb:27-72` no snapshot). Os casos de strings `internal`/`both` continuam cobrindo `422` sem Copilot e sucesso quando as quatro condições estão disponíveis. Não há dependência de produto que exija a forma numérica.

## B2-CODE-02 — identidade do canal na lista

`ListProjection#channels_for` agora retorna exatamente `{ inbox_id, name, channel_type }` em `app/services/autonomia/agents/list_projection.rb:99-104`. O serializer da lista repassa essa projeção sem criar alias (`app/views/api/v1/accounts/autonomia/agents/_agent.json.jbuilder:38-43`), e o request spec fixa o shape com `inbox_id` (`spec/requests/api/v1/accounts/autonomia/agents/index_spec.rb:51-63`). Isso coincide com PRD BE-01 e F1.

O endpoint separado de Canais mantém seu shape próprio, com `id` do vínculo e `inbox_id` da caixa (`app/views/api/v1/accounts/autonomia/agents/channels/index.json.jbuilder:1-9`). O `PanelChannels` usa `inbox.inbox_id` para desconectar e `inbox.id` para caixas elegíveis; portanto a correção da lista não quebra esse consumidor. A primeira tela deve ler `channels[].inbox_id` e, para gerir vínculos, continuar usando o endpoint nested `/agents/:agent_id/channels`.

## Conclusão

B2-CODE-01 e B2-CODE-02 estão fechados nesta checagem limitada. Isso não é aprovação do lote B2 inteiro: os demais achados e a validação coordenada permanecem sob seus owners.
