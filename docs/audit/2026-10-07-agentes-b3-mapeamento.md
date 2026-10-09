# Auditoria — mapeamento inicial do B3/BE-05

**Data:** 2026-10-07  
**Branch:** `docs/agentes-ia-prd`  
**Worktree:** `/Users/rodrigosilva/dev/worktrees/chat2you/agentes-ia-prd`  
**Estado:** rascunho documental, sem implementação e sem revisão normal.  
**Escopo:** somente o leitor/retomada BE-05 necessário para F1. Os demais requisitos de B3 permanecem pendentes.

## Autorização e limites

Foi autorizado escrever apenas o desenho B3, este mapeamento e a correção do fixture de ownership em
`spec/requests/api/v1/accounts/autonomia/agents/channels_spec.rb`. Não foram executados RSpec, banco,
build, navegador, produção, fila, push, PR ou merge. O RSpec do B2 continua rodando no snapshot coordenado
por outra sessão e não foi tocado.

## Fontes conferidas

- `docs/agentes-ia-redesign/PRD.md:109,275-280,415-430,518,595-597,733,1146`;
- `docs/agentes-ia-redesign/design/F1.md:13-18,115-146`;
- `docs/agentes-ia-redesign/revisoes/B3-desenho-normal-integracao.md`;
- `config/routes.rb:395-402`;
- `app/controllers/api/v1/accounts/autonomia/base_controller.rb:55-66`;
- `app/controllers/api/v1/accounts/autonomia/agents/build_threads_controller.rb:1-5,60-66,115-167`;
- `app/models/autonomia/agents/build_thread.rb:31-45,95-120`;
- `app/models/autonomia/agents/agent.rb:59-67,90-121,220-250,237-243,335-342`;
- `app/services/autonomia/agents/list_projection.rb:48-59`;
- `app/services/autonomia/agents/builder.rb:1013-1027,1334-1388,1543-1568`;
- `app/views/api/v1/accounts/autonomia/agents/build_threads/show.json.jbuilder:1-25`;
- `app/javascript/dashboard/api/autonomia/buildThreads.js:16-64`;
- `app/javascript/dashboard/store/modules/autonomiaBuildThreads.js:128-177,179-249,316-361,424-433`;
- `app/javascript/dashboard/routes/dashboard/autonomia/components/panel/PanelTune.vue:209-287`.

## Mapa contrato → código → lacuna → prova

| Item | Evidência atual | Lacuna concreta | RED mínimo |
|---|---|---|---|
| Leitor nested | Só `resources :build_threads` top-level em `config/routes.rb:395-402` | Não há GET por agente | request 200 no caminho nested |
| Conta/permissão | `agents_scope`/`build_threads_scope` em `base_controller.rb:55-66`; GET top-level já exige manage | Falta combinar agente e thread na URL com guard própria | viewer 401 antes de query; cross-account 404 |
| Última sessão | `BuildThread#inherit_pending_question!`, `Agent#apply_builder_config!` e `ListProjection#latest_threads` usam conta/agente e id maior | O reader BE-05 precisa repetir a mesma ordenação | duas threads; maior id é escolhida |
| Histórico real | Jbuilder show expõe só mensagens e state filtrado | F1 ainda abre diálogo vazio | GET hidrata mensagens/state e não expõe `draft_config` |
| `force_close` | controller grava a flag no create/messages; jbuilder não a expõe | saída da criação pode fechar imediatamente na retomada | GET limpa somente a flag, idempotente |
| Modo manual/Lia | `fetch_thread` recusa a instrução mantida, mas não há `manual_mode` para retomada | manual pode alcançar o Builder antigo | 422 antes de modelo/append/job |
| Campos protegidos | `map_attributes` inclui schema inteiro e `apply_builder_config!` mescla | voz, nome, fallback, atuação e canais precisam sobreviver ao ajuste | saída maliciosa muda campos protegidos; só cinco permitidos persistem |
| Cliente/store | API só tem create/show/send/retry; PanelTune chama start sem thread | “Mudar conversando” cria sessão nova | spy prova GET + mesmo id + zero `start/create` |
| Criação versus ajuste | `Builder#ensure_agent` cria rascunho antes do fechamento; `Builder#adjust_mode?` usa `instruction.present?` | E1/E2 com agente vinculado não podem ser confundidos com ajuste fechado; ajustes legados também precisam D22 | E1/E2 aceitam nome/voz/apresentação; agente fechado usa allowlist sem exceção de voz |

## Causas registradas antes da correção

A revisão normal de integração em `docs/agentes-ia-redesign/revisoes/B3-desenho-normal-integracao.md`
encontrou dois bloqueios P1 no desenho anterior:

1. **B3-DES-01 — criação inacabada confundida com ajuste fechado.** O desenho marcava toda thread lida
   pelo GET nested como `resume` e mandava aplicar a allowlist D22. Em E1/E2, porém, o Builder já criou
   um rascunho vinculado antes do primeiro fechamento; essa criação ainda precisa aceitar nome, voz e
   apresentação. A presença de `agent_id` tampouco distingue os fluxos. A correção deve usar o predicado
   real `Builder#adjust_mode?` (instrução já presente), manter criação com rascunho no schema completo e
   proteger qualquer retomada de agente já fechado, inclusive o ajuste legado, sem uma exceção de voz.
2. **B3-DES-02 — guarda manual somente antes da fila.** A guarda em `fetch_thread` não cobre a corrida
   em que o agente muda para manual depois do enqueue e antes do job escrever. A correção deve manter a
   recusa antes de append/IA para requests já manuais e acrescentar uma segunda guarda dentro do lock
   autoritativo de `Agent#apply_builder_config!`, antes de qualquer atributo ser alterado, com prova de
   enqueue → troca para manual → conclusão recusada sem sobrescrita.
3. **B3-DES-03 — allowlist ainda não era autoritativa no writer.** A correção anterior dizia que o Builder
   filtraria antes de `apply_builder_config!`, mas deixava o `Agent` aplicar o schema recebido sem reavaliar
   `instruction.present?` sob lock. Uma corrida em que a instrução ainda estava vazia no primeiro turno e
   outro fechamento chegasse depois poderia gravar schema completo fora da criação. A allowlist D22 precisa
   ser escolhida no `Agent#apply_builder_config!`, após reload sob `Agent.with_lock`; o filtro antecipado do
   Builder pode permanecer como defesa, mas não é a autoridade de escrita.

Nenhuma mudança no desenho foi feita antes deste registro. As conferências da revisão não encontraram novo
problema em conta/kept/system_key, manage-only, `id DESC`, envelope privado, ordem Agent → Thread do reset
ou no escopo restrito de BE-05. O RED17 já alinhou `ListProjection` ao `id DESC`; o desenho não trata isso
como divergência atual.

## Decisões de desenho registradas

1. A rota nova é `GET /api/v1/accounts/:account_id/autonomia/agents/:agent_id/build_thread`.
2. A sessão é filtrada por conta e agente e escolhida por `id DESC`, alinhada à convenção existente de
   pendência, ao writer concorrente e à `ListProjection` após o RED17.
3. O GET zera apenas `state.force_close` sob lock na ordem Agent → Thread, sem criar thread, chamar job ou
   limpar materiais.
4. O envelope reutiliza `build_threads/show`; instruction, scaffold, draft_config, tokens e config privada
   continuam fora da resposta.
5. Manual devolve `manual_mode`; Lia mantém `instrucao_mantida`; viewer não recebe mensagens.
6. Na retomada de agente guiado já existente, somente `instruction`, `human_card`, `scaffold`,
   `handoff_rule` e `config.guardrails` podem mudar. Nome, voz, atuação, fallback, persona/identidade,
   canais e demais configuração ficam preservados. Criação nova permanece com schema completo.
7. `agent_id` não identifica ajuste, pois o Builder cria o rascunho no início. Não há terceiro modo nem
   marcador no `state`: `Builder#adjust_mode?` (`instruction.present?`) escolhe schema completo para E1/E2
   e allowlist D22 para agente fechado, inclusive ajuste legado. O predicado é reavaliado após reler o
   agente no lock do writer.
8. Manual tem duas portas: request/fetch antes de append, IA ou enqueue; e `Agent#apply_builder_config!`
   dentro do `with_lock`, antes da escrita, para cobrir troca para manual após enqueue sem sobrescrever a
   instrução manual.
9. F1 hidrata antes de abrir o diálogo e nunca cria thread substituta como fallback.

## Correção aplicada após a revisão normal

- Removido do desenho o `builder_flow`/`resume` aplicado a todo GET. E1/E2 conservam o primeiro fechamento
  completo mesmo com `autonomia_agent_id` já vinculado; o ajuste fechado continua sendo decidido por
  `instruction.present?`.
- Mantida a ordem de lock Agent → Thread no reset de `force_close`, sem novas mutações no GET.
- Acrescentada a guarda manual no writer sob lock, além da guarda anterior à fila; a prova de corrida ficou
  explícita no RED.
- Tornada explícita a autoridade do writer: `Agent#apply_builder_config!` relê `instruction.present?` sob
  lock e escolhe a allowlist D22 depois da reload; o filtro no Builder é antecipado, não a fonte final.

## RED acrescentado pela correção

- E1/E2: a thread retornada já tem `autonomia_agent_id`, mas o agente ainda está sem `instruction`; depois
  do GET e do primeiro fechamento, nome, voz e apresentação podem ser gravados como criação completa.
- Ajuste fechado: a mesma jornada com `instruction.present?` tenta alterar voz, nome, fallback e canais; a
  allowlist D22 preserva todos os protegidos, inclusive em ajuste legado pela rota top-level.
- Request manual: a guarda antes do append/IA/enqueue devolve `422 manual_mode` e não grava mensagem nem
  chama o modelo.
- Corrida manual: depois do enqueue, mudar o agente para `manual` antes do resultado; o writer relê sob
  `Agent#with_lock`, recusa antes de `apply_builder_attributes!`, marca a thread como recusada/failed e
  preserva a instrução manual.
- Corrida de fechamento: o Builder pode ter visto um rascunho sem instrução, mas o writer relê o agente sob
  lock; se a instrução já estiver presente, aplica D22 e não grava nome, voz, fallback ou canais como schema
  de criação.

## Correção de fixture B2/C

**Causa:** `spec/requests/api/v1/accounts/autonomia/agents/channels_spec.rb:81` ainda lia
`.agent_id` diretamente de `Autonomia::Agents::AgentInbox`. O modelo usa a coluna/FK
`autonomia_agent_id`; o accessor `agent_id` não existe. O controller já havia sido corrigido na causa C1
para acessar `link.agent.id`, então o erro restante era somente do fixture/assertion.

**Correção mínima:** a linha agora lê `.autonomia_agent_id` e compara com o agente da outra conta. Isso
mantém a prova de isolamento sem adicionar coluna, associação ou fallback.

## Validação estática deste bloco

Executada somente validação estática, sem declarar GREEN funcional:

- `ruby -c spec/requests/api/v1/accounts/autonomia/agents/channels_spec.rb`: `Syntax OK`;
- `git diff --check`: limpo;
- `eval "$(rbenv init -)" && bundle exec rubocop --force-exclusion spec/requests/api/v1/accounts/autonomia/agents/channels_spec.rb`:
  `ok ✓ rubocop (1 files)`, sem autocorreção.

RSpec, banco, build, snapshot, navegador e serviços continuam pendentes para a sessão coordenadora.

### Checagem limitada após a revisão normal

- `git diff --check`: limpo;
- busca estática confirmou que `builder_flow`/`resume` ficaram apenas como causa removida e não como
  contrato de implementação; o desenho usa `Builder#adjust_mode?` e as duas portas de `manual_mode`;
- não foram executados RSpec, banco, build, navegador, snapshot ou serviços nesta correção documental.

## Bloqueios e critério de parada

- B2 permanece em integração/teste no snapshot16; esta fatia não o executa nem o altera.
- B3 inteiro não está pronto: BE-03, BE-04, BE-07, BE-09 e BE-26 continuam pendentes.
- F1 não pode implementar “Continuar” antes de BE-05 GREEN e revisão própria.
- O desenho permanece DRAFT até RED/GREEN, revisão normal e aceite do fluxo real; não há autorização de
  merge, fila, deploy, produção ou banco.
