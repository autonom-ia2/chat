# Fase 6 da issue #257 — investigação dos dois números anômalos

Data: 2026-08-09 · Branch: `feat/crm-followup-fases-4-5-6`

A Fase 6 pedia para **investigar antes de consertar** dois números que só apareceram no dado de
produção, não na leitura de código:

1. dos 675 follow-ups da IA na conta 6, **zero** saíram por template, mesmo com o funil pedindo
   "Usar template utilidade continuidade_atendimento";
2. **112 de 675 (17%)** falharam no envio.

## Como o dado foi lido

AWS `354307071110` (perfil `hub2you`), instância `chatwoot-hub2you-prod-ec2-green`, via SSM Run
Command → `docker exec chatwoot-web` → `psql` com as variáveis de ambiente do próprio contêiner.
Somente `SELECT`; nenhuma escrita, nenhum `rails runner`. Nenhum valor de credencial foi exibido
ou registrado — apenas os NOMES das variáveis (`POSTGRES_HOST`, `POSTGRES_USERNAME`,
`POSTGRES_PASSWORD`, `POSTGRES_DATABASE`, `POSTGRES_PORT`).

Nenhuma transcrição de cliente foi extraída. Só contagens agregadas e chaves de controle do
`metadata`.

## Resultado 1 — os dois números são o MESMO bug

Agrupamento por `send_error` (conta 6, `metadata->>'source' = 'ai_followup'`):

| erro | n |
|---|---|
| `Validation failed: Template params/namespace must be of type string` | 104 |
| `sender_required` | 9 |
| sem erro | 568 |

Nos 104 registros com erro de template, o `metadata` já continha `template_name =
continuidade_atendimento`, `template_language = pt_BR` e `template_processed_params`. Ou seja: **a
IA escolhia o template certo, aquele que o funil pedia.** O envio é que era recusado.

Causa raiz em `app/services/crm/follow_ups/message_sender.rb#native_template_params`:

```ruby
namespace: metadata['template_namespace'].to_s.strip.presence
```

Nada no fluxo de follow-up preenche `template_namespace` (namespace só existe na API on-premise da
Meta). `.presence` devolve `nil`, e o `TEMPLATE_PARAMS_SCHEMA` do `Message`
(`app/models/message.rb`) declara `namespace` como `'string'`, exigindo apenas `name`. `nil` não é
string → `ActiveRecord::RecordInvalid`.

Logo, **todo** envio por template morria antes de virar mensagem — o que explica os dois números de
uma vez: 0 templates enviados E o grosso dos erros de envio. Cada toque ainda gastava as 3
tentativas do budget antes de desistir.

Distribuição temporal: 95 em 07/2026, 9 em 08/2026 na primeira leitura. Em verificação por conta, as
falhas de template aparecem **só na conta 6** — é a única usando template nativo
(`Channel::Whatsapp`) no follow-up. Nos 30 dias anteriores à investigação o erro seguia ativo (100
ocorrências), ou seja, não era resíduo histórico.

Conserto: a chave `namespace` passa a ser **omitida** quando não há valor, em vez de ir como `nil`.
O schema exige só `name`, então a omissão é válida. Quando o namespace existe, ele continua indo.
Regressão coberta em `spec/services/crm/follow_ups/message_sender_spec.rb`, com verificação de que
o teste falha quando o bug é reintroduzido.

## Resultado 2 — `sender_required` já estava resolvido

Os 9 casos são todos de 07/2026 e todos têm `created_by_id` e `assignee_id` nulos. O
`AutoFollowupTouchBuilder#resolved_sender` já resolve um remetente em cascata (dono do card →
assignee da conversa → administrador da conta) — correção de release anterior. Zero ocorrências nos
30 dias anteriores à investigação. **Nada a fazer.**

## Efeito esperado em produção

Depois do deploy, follow-ups fora da janela de 24h passam a sair de fato por template aprovado
(`continuidade_atendimento`, categoria UTILITY). Isso é **mudança de comportamento visível para o
cliente final**: hoje esses toques simplesmente não saem. O cap de 24h por contato da Meta (131049)
só se aplica a template MARKETING, então o UTILITY não é limitado por ele.

O volume de mensagens entregues deve subir. Esse é o resultado pretendido pela issue ("volume igual
ou maior, acerto muito melhor"), mas exige aceite explícito antes de subir.

## O que medir depois do deploy

- `send_error` agrupado: a linha `Template params/namespace` deve zerar;
- `send_mode`: deve aparecer `template` (hoje só existe `session` e nulo);
- volume de toques entregues por dia, comparado com a semana anterior.

## Atualização — PRs seguintes (#260, #261, #262)

Este documento registrou a Fase 6 no dia em que foi escrito. As três PRs que fecharam a issue #257
inteira já estão mergeadas e no ar; ver `docs/crm_ai_followup_prd.md` para o estado atual do
sistema. Dois dos três pontos abaixo, deixados como "aberto" nesta investigação, já foram
resolvidos:

- ~~A linha da matriz "humano atendendo agora → adia o toque, não cancela" nunca entrou no
  prompt.~~ **Resolvido na PR #262** por um caminho diferente do proposto na Fase 2: em vez de uma
  regra explícita de "humano atendendo = adiar", o relógio da cadência (`CadenceAnchor`) passou a
  contar da última mensagem da conversa, de quem for — não mais só da última fala do cliente. Um
  atendente conversando com o cliente agora empurra o próximo toque sozinho, sem precisar de uma
  regra dedicada no prompt.
- ~~O `CallbackRunner` não confere a citação como o `AutoFollowupRunner`.~~ **Resolvido na PR
  #262**: a verificação foi extraída para `Crm::Ai::QuoteVerifier` e passou a ser usada pelos dois
  runners.
- **A régua de casos (`rake crm:followup_eval`) segue fora do CI**, por ser chamada paga de IA. Já
  cresceu de 15 para 25 casos nas PRs seguintes, mas nada força que alguém a rode antes de mexer no
  prompt. Continua sendo o maior risco de regressão silenciosa do sistema.

Achado adicional na PR #261, fora do escopo original desta investigação: um filtro SQL em
`Crm::Ai::ContextBuilder#last_human_agent_at` nunca excluía os próprios follow-ups automáticos do
cálculo de "última fala humana" — `content_attributes` é coluna `json` com `store ... coder: JSON`,
e o operador `->>` do Postgres não enxerga uma string JSON aninhada. Ver o corpo da PR #261 para o
detalhe completo.
