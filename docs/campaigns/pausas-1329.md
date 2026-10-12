# Pausa de campanha e conferência do modelo no disparo (#1329, épico #1320)

## O problema

Até aqui a campanha do WhatsApp Oficial não conferia o modelo na hora do disparo. Se o modelo tinha sido
pausado, alterado, apagado ou mudado de tipo depois de a campanha ser criada, ela saía mesmo assim. Todos os
contatos ficavam "falhou", com o erro da Meta em inglês, e a campanha terminava "concluída". O spec
`spec/services/campaign_pauses/whatsapp_dispatch_gate_spec.rb` reproduz o caso.

## Regra única de formato enviável

`Whatsapp::Templates::SendableFormat` (`app/services/whatsapp/templates/sendable_format.rb`) responde se
os motores de hoje conseguem enviar um modelo. Ela lê só a estrutura de `components` (o schema da Meta),
nunca o texto do modelo.

- **Enviável:**
  - corpo e rodapé;
  - cabeçalho de texto, foto, vídeo ou documento;
  - botões de resposta rápida, link (fixo ou com final variável) e ligar.
- **Flow:** continua enviável, como já é hoje. Vem com o aviso `flow_without_token`.
- **Botão de tipo que a regra ainda não conhece** (ex.: `VOICE_CALL`): continua enviável, como hoje, com o aviso `unknown_button`.
- **Copiar código:** enviável só quando o envio leva o código (`coupon_codes:`, os índices dos botões com código gravado, como faz o diálogo antigo de campanha, um código para todos). A jornada não pede o código, então lá ele fica não enviável.
- **Ainda não enviável**, com o código do motivo:
  - `copy_code`;
  - `carousel`;
  - `limited_time_offer`;
  - `catalog` (CATALOG/MPM/SPM, LIST, PRODUCT);
  - `verification_code` (botão OTP);
  - `location_header`;
  - `call_permission_request`;
  - `unsupported_header`, `unsupported_button` e `unsupported_component` (para tipos que a Meta criar depois).

A regra de categoria continua no `Whatsapp::AuthenticationTemplateGuard`, que barra modelo de autenticação
para destinatário BSUID. As duas regras não se repetem.

```ruby
Whatsapp::Templates::SendableFormat.check(template)     # => Result(reason_code, warnings), #sendable?
Whatsapp::Templates::SendableFormat.sendable?(template) # => true / false
```

Os outros consumidores passam a usá-la em PRs pequenos, depois deste:

- `Crm::BookingV2::Notices::Route.fillable_template?`;
- filtro de modelo do follow-up;
- seletor de modelo da conversa.

## Conferência no disparo

`CampaignPauses::WhatsappDispatchGate` é prependido em `Whatsapp::OneoffCampaignService` por
`config/initializers/campaign_pauses.rb`, depois dos módulos da jornada. Por isso é o `perform` mais
externo e roda antes de qualquer destinatário ser criado. Ele vale para toda campanha one_off de caixa
WhatsApp Cloud.

1. `Whatsapp::Templates::DispatchCheck` pergunta à Meta pelo modelo, com uma chamada por campanha:
   `GET /{WABA}/message_templates?name=…&fields=name,language,status,category,components`, na versão
   `WHATSAPP_API_VERSION` e com `template_access_token`.
2. Se a Meta não responde (timeout, erro de rede ou resposta não-2xx), a conferência lê
   `channel.message_templates` e registra no log que a fonte foi o cache.
3. A conferência compara o que a campanha gravou (`template_params`: nome, idioma, categoria e
   `processed_params`) com o modelo atual.

| reason_code | source | quando |
|---|---|---|
| `template_missing` | template | não há modelo com esse nome e idioma |
| `template_not_approved` | template | status diferente de APPROVED (pausado, em análise, recusado, desativado) |
| `template_category_changed` | template | a categoria mudou (o custo muda) |
| `template_format_unsupported` | template | formato que ainda não dá para enviar (`details.format_code`) |
| `template_structure_changed` | template | variáveis, cabeçalho ou botões diferentes dos gravados (`details`: chaves, sem valores) |
| `templates_not_synced` | system | a Meta não respondeu e o cache foi zerado na troca de conta, ainda sem resync |
| `template_unverifiable` | system | a Meta não respondeu e não há cache para ler, ou a própria conferência quebrou (`details.error_class`) |

Se houver divergência, ninguém recebe nada. A campanha ganha uma `CampaignPause` aberta e volta para
`active` (sob lock de linha, só se ainda estiver `processing`). Se a conferência quebrar, a campanha não
sai às cegas nem fica presa em `processing`: pausa pelo sistema.

Campanha gravada num formato antigo (`processed_params` plano, `{ '1' => 'x' }`, ou lista posicional) não passa pela comparação
de estrutura. As outras conferências valem para ela.

## Registro genérico da pausa: `campaign_pauses`

É uma tabela do fork, polimórfica: `pausable_type` aceita `Campaign` (do Chatwoot) e `EmailCampaign` (do
fork). Nenhuma tabela do Chatwoot ganha coluna.

| coluna | |
|---|---|
| `account_id` | FK accounts, cascade |
| `pausable_type`, `pausable_id` | a campanha pausada |
| `source` | `template` · `email_protection` · `manual` · `system` |
| `reason_code` | código estável, que as telas traduzem |
| `details` | jsonb com fatos técnicos, nunca dado pessoal |
| `paused_by_id`, `paused_at` | quem pausou (nulo quando foi o sistema) e quando |
| `resumed_by_id`, `resumed_at` | quem retomou e quando; `resumed_at` nulo = pausa aberta |

Índices:

- `idx_campaign_pauses_on_pausable`: (`pausable_type`, `pausable_id`, `paused_at`), para o histórico;
- `idx_campaign_pauses_one_open`: único em (`pausable_type`, `pausable_id`) `WHERE resumed_at IS NULL`, para
  que haja no máximo uma pausa aberta por campanha.

O primeiro a gravar é a conferência do modelo. Os pontos de pausa do e-mail (`pause!`, higiene, admissão,
autopausa do envio direto) passam a gravar aqui em outro PR.

## Como a campanha nativa fica pausada e como volta

- **Pausada:** o `campaign_status` fica `active` e a campanha tem uma `CampaignPause` aberta.
  `CampaignPauses::TriggerGate`, prependido em `Campaign`, faz `trigger!` retornar antes de virar
  `processing`. O agendador continua escolhendo a campanha, mas cada escolha é um no-op.
- **Retomada:** `CampaignPauses::Resumer` fecha a pausa e grava quem retomou e quando. Se a campanha ainda
  está `active`, ele dispara `Campaigns::TriggerOneoffCampaignJob` depois do commit, porque o agendador só olha 3
  dias para trás. A conferência roda de novo. Se o modelo ainda diverge, abre uma pausa nova e ninguém
  recebe.
  - API: `POST /api/v1/accounts/:account_id/campaign_journey/campaign_pauses/:id/resume`. Exige
    `campaign_manage` (sem a permissão, 401) e a flag da jornada (desligada, 404). Pausa de outra conta dá
    404.
  - A pausa é travada (`lock!`): duas retomadas ao mesmo tempo não passam juntas. Erros (422, com `code`): `pause_not_open`, ou `campaign_already_sent` quando a campanha já tem
    destinatário além de `queued`. Nesse caso a pausa continua aberta.
- **Sem reenvio:** `Campaign#trigger!` vira `processing` sob lock de linha e ignora campanha em `processing`
  ou `completed`, então campanha concluída nunca sai de novo. A pausa abre antes do primeiro destinatário.
  Campanha que já enviou não é retomada (`campaign_already_sent`), porque o caminho de etiquetas do
  Enterprise reprocessa todos os destinatários.
- **Exibição:** `campaign.pause` no Resultado (`CampaignRecipientsResult#campaign_payload`) e `pause` em cada
  linha da Gestão (`CampaignOverview`). A campanha pausada aparece na Gestão mesmo estando `active`.

## Toques em arquivos do Chatwoot

- `config/routes.rb`: uma linha, a rota de retomar.
- `db/schema.rb`: gerado pela migration.
- Specs existentes:
  - stub da consulta à Meta: `spec/services/whatsapp/oneoff_campaign_service_spec.rb`,
    `spec/enterprise/services/enterprise/whatsapp/oneoff_campaign_service_spec.rb` e
    `spec/support/campaign_journey_helpers.rb`;
  - dois exemplos ganharam um modelo aprovado e coerente com a campanha, para continuar exercitando o que
    testavam (líquido em branco; guard de autenticação para BSUID).

`campaign.rb`, `template_processor_service.rb`, `oneoff_campaign_service.rb` (OSS e EE) e o job de disparo
não foram editados.
