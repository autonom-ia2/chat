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

## Aberto, fora do escopo desta branch

- A linha da matriz de decisão da Fase 2 "humano atendendo agora → adia o toque, não cancela" nunca
  entrou no prompt do `FollowUpComposer`. Os dados existem no payload (`conversation_state`), mas
  não há regra de decisão usando-os.
- O `CallbackRunner` usa o mesmo schema do follow-up, incluindo `open_loop_source`, mas não faz a
  verificação de citação que o `AutoFollowupRunner` faz desde a Fase 3.
- A régua de 15 casos (`rake crm:followup_eval`) roda fora do CI por ser chamada paga de IA. Nada
  força que ela seja executada antes de mudar o prompt.
