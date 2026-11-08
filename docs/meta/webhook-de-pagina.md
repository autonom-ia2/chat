# Webhook de Página da Meta nas duas stacks (#2200)

O app da Meta 544486745144318 tem **um** endereço de webhook de Página para todas as stacks:
`https://chat.autonomia.site/bot`. Por ele chegam o Messenger (`messaging`), os leads de formulário
(`changes`, campo `leadgen`) e os comentários do Facebook (`changes`, campo `feed`).

## Caminho de um evento

1. `POST /bot` → `Webhooks::FacebookPageController#events`. O `GET /bot` (verificação da Meta) continua na gem
   `facebook-messenger`.
2. Confere `X-Hub-Signature-256` com `FB_APP_SECRET`, `WHATSAPP_APP_SECRET` e o segredo da caixa, quando houver.
   Assinatura inválida: 401 e nada é processado.
3. `messaging` vai para os handlers da gem (`config/initializers/facebook_messenger.rb`), como antes.
4. Cada `changes[]` vira o job do seu campo, com `(page_id, value, time)`:
   - `leadgen` → `Webhooks::FacebookLeadgenJob` (#2195);
   - `feed` → `Webhooks::FacebookFeedJob` (#2197).
   O job ignora Página que não conhece nesta stack. Sem a classe (ainda não publicada), o evento só é registrado
   no log.
5. Repasse para a outra stack (`FB_PAGE_WEBHOOK_RELAY_URLS`, Super Admin → Facebook), pelo
   `Webhooks::InstagramRelayJob`, com o corpo e a assinatura originais:
   - corpo com `changes`: sempre;
   - corpo só com `messaging`: quando alguma Página do corpo não é caixa desta stack.
   O evento repassado leva o cabeçalho de repasse e nunca é repassado de novo.

Configuração:
- autonomia: `FB_PAGE_WEBHOOK_RELAY_URLS=https://chat.hub2you.ai/bot`;
- hub2you: vazio. Só muda se o callback do painel um dia passar para a hub2you; aí inverte.

## Inscrição da Página nos campos

`POST /{page_id}/subscribed_apps` substitui a lista inteira de campos, e `DELETE` tira o app da Página.
Todo recurso usa `Crm::MetaAds::PageSubscription`, que lê a lista atual, soma ou tira só os seus campos e grava a
lista inteira:

```ruby
Crm::MetaAds::PageSubscription.new(page_id:, access_token: page_token).add!(%w[leadgen])
```

O app é o do próprio token (GET /app). No Instagram (login do Instagram) não há nada a inscrever por conta: os
campos valem pelo painel do app.

`Channel::FacebookPage#subscribe/#unsubscribe` somam e tiram só os campos do Messenger.

## Teste depois do deploy

1. Painel do app → Webhooks → Página → `leadgen` → "Testar" (só envia um evento; não muda configuração).
2. Log da autonomia: `POST /bot` 200 e o repasse enfileirado. Log da hub2you: `POST /bot` 200 com o cabeçalho de
   repasse.
3. Lead real: Ferramenta de teste de anúncios de cadastro numa Página de teste ligada a uma conta.

## Rollback

1. Parar o repasse: esvaziar `FB_PAGE_WEBHOOK_RELAY_URLS` no Super Admin da autonomia. Vale na hora, sem deploy.
2. Desfazer o roteador: revert do PR. O `POST /bot` volta a ser só a gem (leadgen e feed voltam a ser descartados).
3. O painel da Meta não é tocado por esta mudança.
