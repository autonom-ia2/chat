# Upgrade Chatwoot 4.19.1 → 4.20.1 (#3120): o que entrou, o que ficou neutralizado

Esta é a etapa 2 do épico #3118. A etapa 1 está em `2026-11-22-3119-neutralizacoes.md`, e a régua é a mesma:
**zero regressão**. Entra o código do upstream, não o comportamento. Na dúvida, vence o fork.

- Base: `main` = `a9da74909c` (já com a 4.19.1). Upstream: `v4.20.1` = `b2f94636d3`.
- O merge trouxe 167 arquivos em conflito: 59 de tradução, 13 do Instagram, 37 de telas e 50 de backend.
- Os conflitos foram resolvidos em 5 frentes. Uma sexta frente, o inventário, leu os arquivos que entraram sem
  conflito, para achar mudança de comportamento que o merge automático trouxe calado.

## Estrutura (resolvida à mão)

- **Flags**: `shopify_custom_apps` e `captain_mcp_servers` vêm do upstream na `feature_flags_ext_1`, posições 16–17, que
  são do fork. Aqui elas vão para a `feature_flags_ext_2`, posições 59–60, as duas desligadas. O spec
  `featurable_positions_spec.rb` e o `account_spec.rb` conferem. Sobram 3 posições na ext_2; a ext_3 já existe.
- **Gems**: Rails 8.0.5.2, `administrate` 1.0, `ruby_llm` 2.1.1 e `ruby-vips` ≥ 2.2.1. O `Gemfile.lock` partiu do lock
  do upstream. As gems só do fork ficaram na versão do fork: Ascii85, afm, css_parser, hashery, marcel 1.1.0 (decisão
  da etapa 1) e mcp 1.7.0. Ruby 3.4.13 e Node 24.22.1.
- **Rotas**:
  - O `post 'bot'` do fork fica antes do `mount`, que passa a ser o `Integrations::Facebook::WebhookServer` (#16576).
    Esse servidor recusa o webhook se não houver `FB_APP_SECRET`, e o segredo está no banco nas duas stacks.
  - Saem as rotas `instagram/connections` do login único (#16645).
- **`conversation.rb`**: **#16584 recusado**. O upstream passou a tirar o robô sempre que a conversa vira "Aberta".
  No fork, a passagem (#1377) deixa a conversa aberta, no nome do robô, à espera de uma pessoa. Com o upstream, o robô
  pararia de responder sem nenhum erro. O nome do callback segue o upstream (`clear_invalid_ai_assignee`, #16391), e o
  corpo segue o fork: o robô sai só quando uma pessoa é atribuída.
  - O spec novo `spec/models/conversation_robo_ao_reabrir_spec.rb` trava esse comportamento.
  - Os specs que o #16584 tinha mudado voltaram ao fork: bulk actions, reabrir adiada, `action_service`,
    `message_spec` e `auto_assignment_handler_shared`.
- **Migrations**:
  - `20261103142055` (#16181, liga `data_import` em todas as contas) vira **no-op**: conta com importação desligada
    continua desligada.
  - As outras só criam estrutura: MCP, Shopify, `data_exports`, `accepts_*` com padrão true,
    `channel_instagram.auth_type` com padrão `instagram_login`, e índices `CONCURRENTLY`.
  - `20261104104833` gera o segredo das caixas SMS; há 0 caixas SMS.
  - `20261111031108` troca os modelos GPT-5 e o3, que a OpenAI desliga em 11/12, por `gpt-6-luna`, no
    `CAPTAIN_OPEN_AI_MODEL` e nos `captain_models` das contas. É o mesmo caso da troca aprovada na etapa 1. Ver
    "Antes do deploy".
- **Docker**: Ruby 3.4.13, Alpine 3.23 e `apk upgrade` (correções de segurança do Alpine). Ficam o `compress-vite-assets`
  e o `ca-certificates` declarado do fork.

## Neutralizado (o código entra, o comportamento fica o do fork)

| PR upstream | O que faria | Onde ficou travado |
|---|---|---|
| #16584 | Tirar o robô ao reabrir | `conversation.rb` (acima) |
| #16701, #16708 | Limite de 1.000 GET/min por usuário na lista de conversas (travaria o n8n) | `rack_attack.rb` igual ao fork |
| #16461, #15877 | 2FA no Super Admin e por conta (#3125) | `rack_attack.rb`, `account_user.rb` |
| #16574 | Pedir a senha atual para trocar e-mail (#3124) | `profiles_controller.rb`, `UserBasicDetails.vue`, `profile/Index.vue` iguais ao fork |
| #16525 | Só administrador conecta Facebook/WhatsApp (#3126) | `whatsapp/authorizations_controller.rb` igual ao fork |
| #16645–#16647 | Login único do Instagram | Controllers, helper, builder, `message_text`, telas e Super Admin iguais ao fork; colunas sem uso |
| #16503–#16507 | Command bar nova no ⌘K, que é da busca da lista (#2211) | `Dashboard.vue`, `Sidebar.vue` (`hasCommandBarV2` falso) |
| #16342 | Preferências de trabalho ("aceitar conversas" no menu de perfil) | `SidebarProfileMenu*.vue` escondem o botão; o padrão `accepts_conversations=true` não muda a distribuição |
| #16181, #16541 | Dados (importar/exportar) para toda conta | Trava `data_import` no menu e nas rotas; migration no-op |
| #16541, #16649 | Importar/exportar indo para Configurações › Dados; o e-mail da exportação com link no lugar do arquivo | `contacts_controller#export` volta ao `Account::ContactsExportJob`; diálogos e store do fork restaurados |
| #16541, #16649 | Job diário que apaga arquivos de importação e exportação com mais de 30 dias | Tirado do `TriggerDailyScheduledItemsJob`; **decisão do Rodrigo** |
| #16554, #16555 | Portal público: só artigo publicado; link de prévia | `public/.../articles_controller.rb` igual ao fork |
| #16496 | Botão "Ver conversas" e nome do canal na lista e no cabeçalho das caixas | `inbox/Index.vue`, `inbox/Settings.vue` |
| #16339 | Sugestão de criar automação depois de criar SLA | `AddSLA.vue` igual ao fork |
| #13856 | Carregador de traduções por glob, com junção rasa | Recusado (ver "Traduções") |
| #16420, #16722, #16623 | Limite de altura da imagem (colide com #1702), arrastar e soltar no e-mail novo, `openCopilot` | Telas iguais ao fork |
| #15938, #16074 | Reading mode e recolher o editor | ReplyBox e MessagesView do fork |
| #16548 | App secret obrigatório para criar caixa WhatsApp Cloud manual, migrar para manual ou apagar o segredo; aviso de conta e de modelo aceito sem assinatura quando a caixa da URL ainda não tem segredo | `channel/whatsapp.rb` sem a validação; campo opcional nas 3 telas; `access_loss` e `templates/webhook_entry.rb` mantêm a assinatura obrigatória nos avisos |
| #16620 | Checagem própria do callback da Bandwidth ligada por padrão em caixa nova | Migration `20261104104833` deixa o padrão `false`, como nas caixas existentes; o `CONFIG_KEYS` aceita as credenciais de callback do fork (#1027) |

## Traduções

- O upstream apagou os `locale/<lng>/index.js` e passou a carregar todos os `*.json` por glob, com junção rasa. Ficaram
  os `index.js` do fork, porque:
  1. o painel baixa cada idioma por `localeLoader.js`, que lê esse `index.js`;
  2. a junção rasa perderia o `AUTOMACAO_LIVRE`, montado de 13 arquivos;
  3. o glob carregaria arquivos que o fork nunca carregou, e textos que hoje aparecem em inglês mudariam.
- O spec novo `i18n/specs/catalogoPorIdioma.spec.js` prova que o catálogo servido em `en`, `pt_BR` e `de` é exatamente o
  de hoje.
- `en/contact.json`: voltaram `IMPORT_CONTACT` e `EXPORT_CONTACT`, que o #16649 apagou e o fork usa (cabeçalho de contatos
  e pacotes de seguros).
- `pt_BR`: entraram as 61 chaves novas do upstream (conversation, inboxMgmt, settings).

## Problemas que o merge automático trazia calado (achados pelo inventário)

- **Super Admin, página de conta com erro 500**: o `label_suggestion` do fork apontava para `gpt-5-mini`,
  `gemini-3-flash` e `claude-haiku-4.5`, que saíram do catálogo (#16678). Passou a usar `gpt-6-luna`, `gpt-6.1-terra`,
  `gpt-5.1` e `gpt-5.2`, com padrão `Llm::Config::DEFAULT_MODEL`. Agora todo modelo citado por uma função existe no
  catálogo.
- **Tela de perfil exigindo senha** (#16574): voltou ao fork.
- **Exportar contatos**: voltou ao fork (ver a tabela).
- **Importação de outro sistema**: `data_imports/index.json.jbuilder` usava `administrator?`. Passou a usar
  `DataImportPolicy#integration_import?`, a chave `integration_manage` do fork (#2027).

## Entra (aproveitado, sem mudar o fluxo)

- **Segurança**:
  - verify token do webhook do Instagram recusado se vier vazio, e comparação segura;
  - dono da caixa nas integrações (#16614);
  - link de reset que expira de verdade (#16521);
  - linha de contato como texto puro (#16465);
  - log de mesclagem só com ids (#16518);
  - resposta do widget sem o contato inteiro (#16497);
  - `:install_url` filtrado do log;
  - Alpine com `apk upgrade`.
- **Desempenho**: gzip, cache da conta e os índices novos.
- **Filtro**: "contém" recusado em atributo numérico (#16610).
- **E-mail**: "Para" entra no Cc ao responder a todos (#16476, `@chatwoot/utils` 0.0.58). O `semQuemSaiuDaCopia`
  (#1828) roda depois do `getRecipients` e limpa Para, Cc e Cco. Quem pediu para sair da cópia continua fora.
- **Atribuição**: automação ou macro que atribui uma pessoa passa pelo serviço de atribuição do fork (#16475), que tira
  o robô e abre a conversa, como a atribuição manual. A produção tem 0 regras ativas.
- **WhatsApp Cloud**: faixa e campo de app secret na caixa manual (#16548), visíveis só para o administrador. O campo é
  opcional (ver a tabela). Com o segredo salvo, o webhook passa a conferir a assinatura da caixa.
- **Voz e Twilio** (sem uso): ficou o upstream. A aba de voz passa a se chamar "Chamadas".

## CI, rodada 2 (`038615fac3` e seguinte)

- `Captain::McpTool` usava a forma do upstream (`validates_with JsonSchemaValidator`); o validador do fork é um
  `EachValidator`. A classe não carregava e derrubava uns 90 exemplos. Passou para a forma do `Captain::CustomTool`.
- `db/schema.rb` no formato do dump do Rails 8.
- `20261107075626`: a remoção da coluna de `captain_mcp_servers` (tabela criada nesta mesma entrega) foi para dentro do
  `safety_assured`.
- **Rails 8 e `as_json(only:)`**: as chaves saem na ordem da lista, e não mais na das colunas. Os payloads da
  Prospecção voltaram a sair iguais byte a byte. Outros `as_json(only:)` só mudam a ordem das chaves, e quem lê pelo
  nome não percebe.
- **#16342 e o rodízio**: os ids de quem está online agora passam pela lista de `account_users` com
  `accepts_conversations`. Em produção os ids já vinham do Redis em texto, então o rodízio atribui como antes. Os
  specs do `HandoffExecutor` simulavam a presença com id inteiro, o que desligava o rodízio por acaso; agora a caixa
  do teste nasce com o rodízio desligado.
- **Captain**: `captain_active?` agora exige a flag `captain_integration` (#16391). O Captain não é usado; conferir antes
  do deploy que nenhuma conta o usa sem essa flag.
- **Bandwidth**: a tela de criar caixa passa a pedir client ID e secret (OAuth, #16052). Há 0 caixas SMS.
- Specs do upstream que testavam comportamento neutralizado saíram ou voltaram ao fork: robô tirado ao reabrir
  (#16584), PUT do portal (#501/#502) e POST `/bot` do `WebhookServer` (o POST continua no controller do fork).

## Arquivos gerados

- `pnpm guia:build`: entram 4 telas novas no registro do Guia.
- `settings_data_export_show` foi para `_fora_do_guia`, porque nada leva o usuário até ela.
- Na Central de Ajuda, a evidência do artigo 07.06 passou a apontar para `key: 'calls-configuration'`: o texto antigo
  agora aparece duas vezes no arquivo.
- `formatos-das-acoes.json` e o relatório de cobertura serão regerados pelo artefato da CI, como na etapa 1.

## Validação local

- RuboCop: 696 arquivos `.rb` que o merge mudou. Ficam 2 ofensas, em `config/environments/development.rb`, que já
  existem na base.
  - O `DataImportJob` passava do `ClassLength` (178/175). A herança da recusa foi extraída para
    `Contacts::OptOutInheritanceJob.perform_for`.
- ESLint: 328 arquivos JS e Vue, 0 erros.
- Vitest: ver o PR.
- Conferências que passaram: `check-fork-i18n.mjs`, `check-email-protection-i18n.mjs`, `guide-map/check.mjs` e
  `central-de-ajuda/conferir.mjs`.
- RSpec só roda na CI: rspec é proibido neste Mac.

## CI, rodada 1 (`1643fbc463`)

- **Enums do Rails 8**: o Rails 8 tirou a forma `enum status: {...}, _prefix: x`, e os specs caíam todos ao carregar
  `EmailCampaign`. Passaram para `enum :status, {...}, prefix: x` 54 declarações em 37 modelos do fork. Os valores, os
  prefixos e os escopos são os mesmos. Não sobrou nenhuma na forma antiga em `app`, `enterprise` e `lib`.
- **Ruby 3.4.13 na CI**: o `setup-ruby` fixado no SHA não conhecia essa versão. O pin passou para a v1.343.0 no
  `testes.yml` e nos dois deploys blue/green.
- **Trava de lint do e-mail**: ela bloqueia todo aviso de ESLint, menos o de chave dinâmica, em qualquer arquivo de
  front que o PR mude. Os 10 avisos estavam em arquivos que vieram do upstream: texto solto (`·`, `#`, `—`, `❌`/`✅`),
  `v-if` na raiz e dois componentes num spec. Cada um ganhou um `eslint-disable` de uma linha, no padrão que o repo já
  usa. A marcação e o comportamento não mudaram.
- **RuboCop** nos modelos mexidos: alinhamento de hash e uma linha longa de anotação, com 0 ofensas no fim.
- **Já falhava na `main`, e não é desta etapa**:
  - "Node synthetic contracts" estoura o teto de 10 min. O passo de recuperação do deploy leva de 7,5 a 8,5 min, e na
    `main` `a9da74909c` também foi cancelado.
  - "Component browser QA": o contraste do "Buscar perfil" (3,499) é o mesmo da `main`.

## Antes do deploy (Orquestração)

1. **Modelo de IA em produção**: ler o `CAPTAIN_OPEN_AI_MODEL` nas duas stacks. Se for gpt-5* ou o3, a migration
   `20261111031108` troca por `gpt-6-luna`, como na etapa 1.
2. **`FB_VERIFY_TOKEN`**: gravar nas duas stacks (decisão 7 do épico).
3. **Índice `contact_inboxes(contact_id, inbox_id)`**: é `CONCURRENTLY`, mas a tabela é grande. Medir o tempo.

## Para o Rodrigo decidir

1. Job diário que apaga arquivos de importação e exportação com mais de 30 dias: hoje está desligado.
2. Limite de login do Super Admin. Hoje todas as tentativas da instalação caem num contador só (5 a cada 15 min), porque
   o fork lê `params['email']`. O conserto do upstream veio junto com o 2FA (#16461). Pode entrar sozinho.
3. Portal público, artigo em rascunho ou arquivado ainda abrindo pelo link (#16554/#16555). A recomendação é ligar
   depois, em PR próprio.
4. Trava #2027 na tela nova da Twilio (`calls/TwilioCallingCard.vue`): a voz está sem uso; registrar Issue.
