# Runbook: avisos da Meta sobre modelos do WhatsApp (#1337)

**Precisa do OK do Rodrigo.** Mexer na configuração do app na Meta é infra/produção. Nada aqui foi executado.

O código do #1337 já trata os avisos de modelo. Enquanto o app não assinar os campos abaixo, ele fica parado: nenhum
aviso chega e a lista continua vindo só do sync (cerca de 5 minutos). Este runbook liga a entrega dos avisos.

## O que o código faz

| Campo do webhook (`whatsapp_business_account`) | O que muda na lista da caixa |
|---|---|
| `message_template_status_update` | `status`. `REINSTATED` vira `APPROVED`. `REJECTED` grava `rejected_reason`. `FLAGGED`, `LOCKED` e `UNARCHIVED` não mudam a lista: pedem o sync da caixa. |
| `message_template_quality_update` | `quality_score.score` |
| `template_category_update` | Com a mudança feita: `category` e `previous_category`. Com o aviso de 24 h antes: só `correct_category`. |

- A caixa é achada pelo `entry.id`, que é a WABA. O aviso atualiza **todas** as caixas Cloud com aquele
  `business_account_id`. O modelo é achado pelo id da Meta. A gravação passa só pelo `Whatsapp::Templates::ChannelList`,
  sem chamada à Graph.
- Modelo que a caixa não tem (criado no WhatsApp Manager): o código pede o sync da caixa e não inventa a entrada.
- Ordem: um aviso mais antigo que o último aplicado ou que o último sync não muda nada. Um aviso repetido também não.
- A assinatura `X-Hub-Signature-256` é **obrigatória** nos avisos de modelo. Valem o segredo do app
  (`WHATSAPP_APP_SECRET`) ou um `app_secret` gravado em caixa da própria WABA. Assinatura que não confere responde 401.
- O log registra só ids e situação: `[whatsapp][templates] webhook kind=… waba_id=… template_id=… event=… channel_id=… result=…`.
- Um POST que mistura aviso de modelo com mensagem, status de envio ou chamada segue inteiro pelo caminho do Chatwoot.
  O aviso desse POST se perde, e o sync seguinte corrige.

Arquivos: `app/controllers/concerns/whatsapp/templates/webhook_entry.rb` (prepend no `Webhooks::WhatsappController`,
registrado em `config/initializers/whatsapp_templates.rb`), `app/jobs/whatsapp/templates/webhook_job.rb` e
`app/services/whatsapp/templates/webhook_event.rb`.

## Fatos da Meta que decidem o passo a passo

Conferidos na documentação oficial em 13/10/2026:

1. **Os avisos de modelo não respeitam override.** A URL da caixa (`override_callback_uri` do número, que o Chatwoot
   grava como `FRONTEND_URL/webhooks/whatsapp/<número>`) e a da WABA não valem para eles. Segundo a página de
   overrides, "Meta always delivers these webhooks to your app's default callback URL". Eles vão para a **Callback URL
   padrão do app**, a que está no App Dashboard.
   (developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/override)
2. **Os campos são assinados no app**, em App Dashboard → WhatsApp → Configuration → Webhook fields. Em app do caso de
   uso "Connect with customers through WhatsApp", o caminho é Use cases → Customize → Configuration. O
   `POST /{WABA}/subscribed_apps` documentado aceita só `override_callback_uri` e `verify_token`. O `subscribed_fields`
   que o Chatwoot manda nessa chamada não está na referência oficial, então não conte com ele para os campos de modelo.
   (…/reference/whatsapp-business-account/subscribed-apps-api)
3. Formatos do `value` (referência de cada campo em …/webhooks/reference/<campo>). Todo `entry` traz `id` (WABA) e
   `time` (Unix). O idioma vem como `en-US`, com hífen.
   - status: `event`, `message_template_id`, `message_template_name`, `message_template_language`, `reason`,
     `message_template_category`, e opcionais `disable_info`, `other_info` e `rejection_info`;
   - qualidade: `previous_quality_score`, `new_quality_score` (`GREEN`, `YELLOW`, `RED`, `UNKNOWN`) e os 3 de modelo;
   - tipo: os 3 de modelo, mais `previous_category` + `new_category` (mudança feita) ou `correct_category` +
     `new_category` (tipo atual) + `category_update_timestamp` (aviso de 24 h antes).
4. BSPs que confirmam o mesmo desenho, com formato próprio por cima do da Meta. A WATI repassa a situação e a qualidade
   por WABA, com o id do modelo da Meta (docs.wati.io/reference/template-status-update e /template-quality-update). A
   360dialog descreve as situações e o `correct_category` (docs.360dialog.com/partner/messaging/template-messages/template-statuses).

## Antes de mudar (só leitura)

Faça na ordem e pare se algo der diferente do esperado.

1. **Quais apps enviam.** Cada app só manda os avisos das WABAs em que está assinado, e manda para a URL padrão dele.
   No Hub2You há caixas por cadastro incorporado (app do `WHATSAPP_APP_ID`) e caixas manuais com token de outro app.
   O PRD cita o token da Autonom.ia, compartilhado por 5 caixas de 4 contas. Liste os apps envolvidos.
   - Banco (psql via SSM, como em `inventario-de-deploy.md`), sem ler valores:
     ```sql
     SELECT provider_config->>'business_account_id' AS waba, provider_config->>'source' AS source,
            count(*) AS caixas, bool_or(provider_config ? 'app_secret') AS tem_segredo_na_caixa
       FROM channel_whatsapp WHERE provider = 'whatsapp_cloud' GROUP BY 1, 2 ORDER BY 1;
     ```
   - Para cada WABA, confirme qual app está assinado. Use `GET /{WABA}/subscribed_apps` com o token da caixa, que é só
     leitura e responde id e nome do app. Não cole o token em chat nem em log.
2. **URL padrão de cada app.** No App Dashboard, anote a Callback URL atual.
   - Se ela já é `https://<domínio do Chat2You>/webhooks/whatsapp/<um número>`, o passo 3 é só ligar os campos.
     O número não importa para os avisos de modelo.
   - Se ela aponta para **outro sistema** (n8n, outro produto ou outro domínio): **PARE**. A URL padrão também recebe
     as mensagens de todo número sem override. Trocar essa URL desvia mensagens de outros sistemas. Leve ao Rodrigo:
     contexto, opções (trocar a URL, repassar do outro sistema ou não usar o webhook nesse app) e o risco de cada uma.
3. **Segredo.** A assinatura usa o App Secret do app que envia.
   - Para o app do cadastro incorporado, `WHATSAPP_APP_SECRET` precisa estar preenchido (Super Admin ou o parâmetro SSM
     do stack). Confira só a presença do nome, nunca o valor.
   - Para outro app, ou o `WHATSAPP_APP_SECRET` é o dele, ou as caixas daquela WABA têm `app_secret` (coluna
     `tem_segredo_na_caixa` acima). Sem isso, todo aviso desse app volta 401, e a Meta repete a entrega por até alguns
     dias. Gravar segredo em caixa é escrita em produção e precisa do OK do Rodrigo, uma caixa por vez.
4. **Código no ar.** O commit do #1337 precisa estar em produção (`ok, SHA`). Sem ele, os avisos caem no job de
   mensagens e são descartados, como hoje.

## Mudança (com OK do Rodrigo)

Para cada app aprovado nos passos 1 a 3:

1. App Dashboard → WhatsApp → Configuration (ou Use cases → Customize → Configuration) → Webhook fields.
2. Assine (**Subscribe**) `message_template_status_update`, `message_template_quality_update` e
   `template_category_update`. **Não** mexa na Callback URL nem nos outros campos.
3. Não use a Application Subscriptions API (`POST /{app-id}/subscriptions`) para isso. Ela pede a lista de campos e
   pode tirar os que já estão assinados (`messages`, `smb_message_echoes`, `calls`…). Pelo painel, liga-se só o que
   se marca.

Tempo estimado: 5 minutos por app.

## Conferência depois

1. No painel, use **Test** ao lado de `message_template_status_update` (envia um exemplo da Meta). O esperado no log
   do stack é `[whatsapp][templates] webhook kind=status … result=no_channel`, porque o exemplo usa uma WABA falsa, e
   resposta 200. Um 401 no log do Rails nessa rota quer dizer segredo errado: volte ao passo 3.
2. Na conta 16 (piloto), crie ou altere um modelo de teste pela tela de Modelos. Quando a Meta aprovar ou recusar, deve
   sair `result=changed` no log com o `channel_id` da caixa, e a situação muda na tela sem esperar o sync.
3. Por 24 h, observe:
   - nenhum `result=needs_sync` em laço para o mesmo modelo;
   - nenhum aumento de 401 em `/webhooks/whatsapp/*`;
   - as mensagens das caixas seguem chegando (nenhum campo antigo foi tirado).

## Volta

- **Painel:** desmarque os 3 campos de modelo (5 minutos por app). A lista volta a depender só do sync, como antes do
  #1337. Nada no banco precisa ser desfeito. As entradas guardam a chave extra `webhook_event_times`, que o sync
  seguinte descarta.
- **Código:** reverter o commit do #1337. Com os campos ainda assinados, os avisos voltam a ser descartados no
  `Webhooks::WhatsappEventsJob`, o que é inofensivo.
