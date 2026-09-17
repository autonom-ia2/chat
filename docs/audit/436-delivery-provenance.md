# #436 — proveniência de entrega na UI

Data: 2026-09-17. Integração local de apresentação; sem Git, Rails, banco, rede,
instalação, leitura de ambiente real, servidor/browser ou escrita em outra worktree.

## Comportamento e contrato assumido

- `delivered` permanece o enum, o filtro HTTP e o valor exportado. Nenhuma API,
  contagem ou base de taxa foi alterada. Não há reclassificação de `sent`, `opened`,
  `clicked`, supressão ou falhas.
- `delivery_mode: direct_inbox` significa aceitação pelo serviço de envio, incluindo
  o evento legado gravado em Graph 202/aceitação SMTP. O texto é **Aceito pelo serviço
  de envio**, sem alegar confirmação do servidor do destinatário.
- `delivery_mode: ses` permite **Aceito pelo servidor do destinatário** no evento
  `delivered`; não comprova chegada à caixa de entrada/leitura humana.
- Para destinatários, a origem vem de `payload.meta.delivery_mode`, com precedência
  de `recipient.delivery_mode` se o campo existir. Um valor explícito desconhecido
  ou null na linha não herda uma confirmação da meta. O filtro usa somente a meta
  da campanha, nunca a origem inferida da primeira linha. Durante troca de campanha,
  dados/meta antigos são limpos antes da resposta nova.
- Na ausência de metadados, usa **Aceitação registrada**. Não consulta a configuração
  atual da inbox para reconstruir o passado e não trata ausência como zero.
- Summary/campaigns: `delivery_evidence.provider_confirmed`,
  `direct_acceptance_only`, `legacy_delivered_includes_acceptance` são lidos diretamente.
  Uma origem exclusiva direta usa o texto do serviço; totais mistos, legados ou prova
  incompleta usam o texto combinado e a ressalva localizada. Para afirmar total
  confirmado pela evidência, as duas parcelas devem ser inteiros não negativos,
  somar `delivered`, não conter parcela direta e declarar flag false.
- O resumo mostra as duas parcelas informadas; parcela ausente é `—`, nunca zero
  calculado ou subtraído. A comparação mantém os números de cada campanha e identifica
  sua origem. Os percentuais permanecem os recebidos, com denominador rotulado segundo
  a mesma aceitação histórica; não há recálculo com base apenas em SES.
- Timeline assume `payload.delivery_mode` ao lado de `payload.series`, conforme o
  contrato solicitado ao backend E. Esse campo controla a legenda da série `delivered`,
  independentemente do resumo. Sem o campo, legenda conservadora; buckets ausentes
  permanecem null. Estado anterior é limpo ao refazer a timeline.
- `METRICS_HINT` permanece intacto nos 57 idiomas: aceitação não garante caixa de
  entrada, abertura não comprova leitura humana e scanners podem registrar cliques.
  A nova ressalva explica a aceitação do serviço sem confirmação do servidor destinatário.
- O produtor backend E e o HTTP real não foram executados neste recorte. O parent deve
  confirmar os campos persistidos em reports/campaigns/detail/rows/meta/timeline.
  Uma ausência temporária desses campos gera texto conservador, sem alegação de entrega.

## Preservação

- Aliases de motivos de backend, `valid => completed` e helper de retomada preservados.
  Os testes de pausa manual/protegida, provider e POST continuam passando.
- Classes `w-full min-w-0 sm:flex-1 sm:min-w-60` da busca mobile e
  `w-full sm:w-auto` do filtro preservadas; e-mails seguem em `bdi dir=ltr` e status
  mantém a direção do locale. Nenhum redesenho de outros módulos.
- Snapshot por SHA-256 de 2.772 JSONs de locale: 2.715 sem alteração; os outros 57
  recuperam exatamente o hash inicial após retirar as três novas chaves. Zero
  divergências. Inclui preservação das sete correções de plural anteriores.
- Os 57 índices e o registro de 43 idiomas ativos não foram editados. Nenhum idioma
  inativo foi ativado. Checker já calcula o número de folhas; não precisou mudar.
- Runner mantém os checks/screens anteriores e acrescenta um cenário `pt-direct` com
  asserções de badge, filtro, enum HTTP e ressalva. Não foi iniciado browser/servidor.
  Os **126 PASS / 90 PNG** e os **4.949 testes completos** informados antes deste delta
  são evidência anterior, não resultados atuais.
- Uma expectativa antiga de fixture foi alinhada ao dado já presente: provider
  `healthy` (o teste esperava `active`). O conflito manual + provider bloqueado com
  `resume:true` e suas asserções de segurança permanecem.
- Nenhum arquivo de SMTP regular, envio de conversa, inbox, backend ou adapter foi editado.
  Testes de frontend dessas superfícies são proteção de regressão, não prova de SMTP real.

## Traduções e inventário

Três folhas novas em `EMAIL_CAMPAIGN_PROTECTION`, com textos escritos nos 57 idiomas:

1. `STATUS.accepted_service`
2. `STATUS.acceptance_recorded`
3. `DELIVERY_HINT`

Sem placeholders novos, cópias de frases inglesas para outros idiomas ou fallback inglês.
95 folhas de proteção (antes 92) + 167 legadas = **262 por locale**.
**171 mensagens novas**; **14.934 mensagens compiladas/renderizadas**, 57 índices,
43 idiomas ativos, `fallbackLocale: false`. As verificações estruturais não equivalem
à revisão linguística por falantes nativos.

## Validação executada

Dependências existentes; todos os comandos Node usaram:

```sh
env -i PATH=/Users/rodrigosilva/.nvm/versions/node/v24.11.0/bin:/usr/bin:/bin
```

Diretório de evidência: `/private/tmp/436-delivery-kabkkaas`.
Wrapper `vitest.config.mjs` importa a configuração real e define `envDir` como
`/private/tmp/436-delivery-kabkkaas/empty-env` (pasta vazia). Nenhum `.env` real foi lido.

1. Vitest inicial: `TZ=UTC node node_modules/vitest/vitest.mjs run --config /private/tmp/436-delivery-kabkkaas/vitest.config.mjs --no-cache --no-coverage --maxWorkers=2 --minWorkers=1 app/javascript/dashboard/components-next/Campaigns/EmailProtection/specs`
   — **7 arquivos / 377 testes PASS**, 8,07 s (`vitest-1.log`).
2. Vitest final, mesmo comando e opções, acrescentando os oito caminhos abaixo após
   a pasta dos specs de proteção — **15 arquivos / 524 testes PASS**, 10,40 s
   (`vitest-2.log`). A pasta de proteção ficou com 378 testes após o caso adicional
   de total misto e ausência de contagens. Duas execuções, máximo de dois workers.

```text
app/javascript/dashboard/api/specs/emailCampaignProtection.spec.js
app/javascript/dashboard/api/specs/inboxes.spec.js
app/javascript/dashboard/api/specs/inbox/message.spec.js
app/javascript/dashboard/api/specs/inbox/conversation.spec.js
app/javascript/dashboard/helper/specs/inbox.spec.js
app/javascript/dashboard/helper/specs/quotedEmailHelper.spec.js
app/javascript/dashboard/helper/specs/emailQuoteExtractor.spec.js
app/javascript/dashboard/routes/dashboard/settings/inbox/channels/emailChannels/OAuthChannel.spec.js
```

3. `node scripts/check-email-protection-i18n.mjs` — saída 0, inventário acima (`i18n.log`).
4. `node --test tests/qa/email-campaigns/fixtures.test.mjs tests/qa/email-campaigns/browser-helpers.test.mjs`
   — **9 PASS**, saída 0 (`fixtures.log`). SES, direto, misto, desconhecido, conservação
   de contagens, filtro/CSV e proteções anteriores. Sem executar `run.mjs`.
5. `node node_modules/eslint/bin/eslint.js` nos oito arquivos JS/Vue de aplicação do
   manifesto — saída 0, **0 erros / 145 avisos** estáticos de i18n (`eslint-app.log`).
   Os índices reais foram validados sem fallback. Não houve supressão de regras.
6. `node node_modules/prettier/bin/prettier.cjs --check` nos 68 arquivos de código/JSON
   do manifesto — saída 0 (`prettier.log`); `--write` anterior limitado aos mesmos
   arquivos. `node --check` nos três `.mjs` modificados — saída 0.

Avisos: caniuse-lite desatualizado, sem atualização; teste existente de data inválida
em quotedEmailHelper emite aviso/stack do date-fns, mas passa.

A primeira tentativa de ESLint incluiu também o harness Node/browser usando as regras
Airbnb do frontend: **100 erros / 151 avisos** (`eslint.log`). Dois erros nos novos
specs de aplicação foram corrigidos (loop e ternário). Os outros 98 apontamentos
estão nos três arquivos do harness (93 no runner, três na fixture, dois no teste):
loops/await sequenciais, console de resultados, identificadores `__qa`, globais de
browser e ternários. Não foi refatorado o runner nem desabilitadas regras para produzir
um falso lint global verde. O resultado verde declarado acima é exclusivamente o
lint dos oito arquivos de frontend; harness foi validado por parser, formato e testes
Node. O parent mantém o gate real do navegador e pode avaliar separadamente a política
de lint desse harness.

## Manifesto exato deste delta

69 arquivos: oito de aplicação/specs, 57 JSONs, três do harness e este documento.
Nenhum index, checker, API, arquivo Rails, configuração ou outro documento foi alterado.

```text
app/javascript/dashboard/components-next/Campaigns/EmailProtection/EmailRecipients.vue
app/javascript/dashboard/components-next/Campaigns/EmailProtection/EmailStatusFilter.vue
app/javascript/dashboard/components-next/Campaigns/EmailProtection/presentation.js
app/javascript/dashboard/components-next/Campaigns/EmailProtection/specs/locales.spec.js
app/javascript/dashboard/components-next/Campaigns/EmailProtection/specs/management.spec.js
app/javascript/dashboard/components-next/Campaigns/EmailProtection/specs/presentation.spec.js
app/javascript/dashboard/components-next/Campaigns/EmailProtection/specs/recipients.spec.js
app/javascript/dashboard/i18n/locale/am/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/ar/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/az/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/bg/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/bn/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/ca/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/cs/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/da/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/de/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/el/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/en/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/es/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/et/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/fa/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/fi/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/fr/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/he/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/hi/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/hr/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/hu/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/hy/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/id/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/is/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/it/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/ja/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/ka/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/ko/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/lt/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/lv/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/ml/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/ms/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/ne/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/nl/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/no/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/pl/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/pt/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/pt_BR/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/ro/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/ru/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/sh/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/sk/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/sl/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/sq/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/sr/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/sv/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/ta/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/th/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/tl/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/tr/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/uk/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/ur/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/ur_IN/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/uz/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/vi/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/zh/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/zh_CN/emailCampaignProtection.json
app/javascript/dashboard/i18n/locale/zh_TW/emailCampaignProtection.json
app/javascript/dashboard/routes/dashboard/crm/pages/CrmCampaignManagementPage.vue
docs/audit/436-delivery-provenance.md
tests/qa/email-campaigns/fixtures.mjs
tests/qa/email-campaigns/fixtures.test.mjs
tests/qa/email-campaigns/run.mjs
```

## Handoff ao parent

- Integrar/confirmar o contrato HTTP do backend E, especialmente persistência da origem
  e `payload.delivery_mode` da timeline / `payload.meta.delivery_mode` de recipients.
- Build e execução real do runner com o cenário direto novo, preservando os gates
  de mobile, RTL, teclado, erros, plural e retomada já existentes.
- Reexecutar o gate completo após integrar este delta; não reutilizar os números de
  4.949 / 126 / 90 como validação do novo estado. Nenhum merge/deploy foi realizado.
