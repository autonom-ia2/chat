# Nova conversa em gaveta (#1459)

## Contexto

A tela de "Nova conversa / Enviar mensagem" era o popover herdado do Chatwoot (`components-next/NewConversation/`). O Rodrigo viu e disse que não estava no padrão da casa. A meta: uma jornada que uma pessoa sem conhecimento de tecnologia use sozinha.

## Decisões

- **Tela nova no padrão da casa.** Gaveta lateral com herói escuro, cartões-frase, opções grandes com rádio de verdade e a prévia de como a pessoa recebe. Uma tela, uma ação azul: Enviar mensagem. Aprovada pelo Rodrigo em 13/10/2026, vendo a tela real em painel local (1440 e 390 px).
- **Construção aditiva.** Tudo novo em `components-next/NovaConversa/` e `components-next/whatsapp-preview/`. O `ComposeConversation.vue` antigo ficou intacto e continua sendo a tela das contas com a flag desligada.
- **Atrás de flag de conta, ligada em todas.** `nova_conversa_tela`, bit 20 (1048576) de `feature_flags_ext_1`, migration `20261026100000`. Bit e versão reservados com a Orquestração em 13/10/2026.
- **Mesmo envio de antes.** `contactConversations/create` com `prepareNewMessagePayload` e `prepareWhatsAppMessagePayload`. Nada mudou no servidor além da flag.
- **Canais perguntados ao servidor.** A gaveta chama `contactable_inboxes` ao abrir, também quando o contato vem da página, porque é só essa resposta que diz se o WhatsApp aceita texto livre (`whatsapp_api_start`).
- **Ordem dos canais própria.** WhatsApp com texto livre, WhatsApp só com mensagem pronta, e-mail, SMS, site, outros. O helper antigo (`compareInboxes`) não foi alterado.
- **Rascunho.** Fechar pelo X, por Esc ou clicando fora mantém o que foi escrito; só "Cancelar" descarta (decisão do Rodrigo).
- **"Criar mensagem pronta" só para quem pode.** Mesma régua da rota de criar modelo: administrador ou função com `whatsapp_templates_manage`. Os demais leem a quem pedir.
- **Telefone legível.** `+55 (11) 4000-0001`, montado com `libphonenumber-js` (código do país + formato nacional). Sem regex.
- **Vocabulário.** "Mensagem pronta" e "modelo aprovado pelo WhatsApp". A tela não mostra "template", "API", "inbox" nem "janela de 24h".

## O que ficou de fora

- Modelo com mídia no cabeçalho ou botão com variável usa o preenchedor antigo (`WhatsAppTemplateParser`), com o resumo dele escondido por seletor.
- WhatsApp via Twilio usa o seletor antigo (`ContentTemplateSelector`), que confirma e envia sozinho; o botão do rodapé não habilita nesse canal.
- Erro de envio mostra uma frase genérica: a action `contactConversations/create` faz `throw new Error(error)` e a resposta do servidor não chega à tela.
- Sem emoji, sem Copilot e sem o botão de alternar assinatura. A assinatura entra sozinha no e-mail quando a preferência está ligada.
- Anexo como antes: só em e-mail e site, e o envio direto continua dependendo de haver uma conversa aberta.
- Cópia e cópia oculta do e-mail reaproveitam o `EmailOptions`, com a linha de assunto escondida por seletor e sem sugestão de contatos.
- A prévia do e-mail mostra o texto cru, sem a formatação aplicada.
- Contato sem canal: a frase diz "ainda não tem telefone nem e-mail" também quando ele tem telefone mas nenhuma caixa o alcança.

## Toques em arquivos do Chatwoot

- Cinco pontos de uso, uma linha cada (o import passa a apontar para `NovaConversa/NovaConversaEntrada.vue`): `Contacts/ContactsDetailsLayout.vue`, `Contacts/ContactsHeader/ContactHeader.vue`, `Relationships/ContactDetailActions.vue`, `sidebar/Sidebar.vue`, `routes/dashboard/conversation/contact/ContactInfo.vue`.
- `featureFlags.js`: constante `NOVA_CONVERSA_TELA`.
- `i18n/locale/en/index.js` e `pt_BR/index.js`: registro do catálogo `novaConversa.json`.
- `config/features.yml`, `config/fork_i18n.json`, `crowdin.yml`, `spec/models/account_spec.rb` (lista de bits).

## Validação local (13/10/2026)

Comandos, na worktree, com Node 24.11:

```
node node_modules/eslint/bin/eslint.js <pastas novas + arquivos tocados>
TZ=UTC node node_modules/vitest/vitest.mjs run <NovaConversa, whatsapp-preview, NewConversation, whatsapp, campaigns/modelos, campaignsMenuRoutes>
node scripts/check-fork-i18n.mjs
node scripts/guide-map/build.mjs && node scripts/guide-map/check.mjs
bundle exec rubocop db/migrate/20261026100000_ligar_nova_conversa_tela.rb spec/models/account_spec.rb
```

Resultados:

- ESLint: 0 erros, 118 avisos. São 116 `no-missing-keys` e 2 `no-dynamic-keys`; 117 em linhas que esta entrega não tocou e 1 em arquivo novo (`useNovaConversa.js`, mesma regra que acusa `CRM_FUNIL` nos arquivos de referência).
- Vitest, conjunto amplo (com `campaigns/modelos` e o menu de campanhas): 22 arquivos, 300 testes, 300 passando. Conjunto da entrega (`NovaConversa`, `whatsapp-preview`, `NewConversation`), já com os pontos de entrada: 8 arquivos, 136 testes, 136 passando — gaveta 20, funções puras 32, mensagem pronta 23, pontos de entrada 6, ponte 5, `PreviaWhatsapp` 5, tela antiga 45.
- i18n do fork: 18 catálogos, 27168 mensagens, en e pt_BR com as mesmas chaves e parâmetros.
- Guia: em dia, 216 fluxos, 202 telas, 0 sem explicação. Bloco `iniciar_nova_conversa` reescrito; `guia-produto.md` regerado.
- RuboCop nos dois arquivos Ruby: sem ocorrências.
- O envio pelo modelo foi comparado, em spec, com o que o preenchedor antigo emite (0, 1 e 2 campos de corpo): idênticos.
- Migration `20261026100000` aplicada em banco de teste próprio.
- RSpec: `rspec spec/models/account_spec.rb spec/services/whatsapp_hybrid/new_conversation_spec.rb` — 87 exemplos, 0 falhas, 1 pendente (quarentena antiga, sem relação com esta entrega).
- `autonomia:guia:formatos:check`: em dia.
- Pontos de entrada: `specs/pontosDeEntrada.spec.js` confere que os cinco arquivos tocados usam a ponte, e não o `ComposeConversation` direto.
- Visual: conferido pelo coordenador no painel local, em 1440 e 390 px.

## Plano de volta

Voltar à tela antiga não pede deploy: a flag desligada devolve o popover do Chatwoot nos cinco pontos de entrada. Nenhuma tabela ou coluna foi criada, e nenhum dado é apagado.

### Uma conta

Super Admin > Contas > a conta > Editar > em Recursos, desmarcar "Nova conversa em gaveta (para quem, por onde, mensagem e prévia)". Vale na hora para quem recarregar o painel.

### Todas as contas

Só por `psql`, nunca `rails runner` em produção. O caminho é o do runbook (SSM, `docker exec` no `chatwoot-web`), nas duas stacks.

O bit é o 1048576 (bit 20) da coluna `accounts.feature_flags_ext_1` (`bigint`): `nova_conversa_tela` é o 21º item dessa coluna no `config/features.yml`.

```sql
-- 1) conferir (leitura) e guardar a lista, para poder religar só estas contas
BEGIN READ ONLY;
SELECT id FROM accounts WHERE (feature_flags_ext_1 & 1048576) <> 0 ORDER BY id;
COMMIT;

-- 2) desligar em todas as contas
BEGIN;
UPDATE accounts SET feature_flags_ext_1 = feature_flags_ext_1 & ~1048576 WHERE feature_flags_ext_1 & 1048576 <> 0;
COMMIT;
```

O passo 2 vale na hora, sem restart: quem recarregar o painel já vê a tela antiga.

### Contas novas (o padrão)

O padrão de conta nova fica em `installation_configs`, na linha `ACCOUNT_LEVEL_FEATURE_DEFAULTS`: uma lista de `{ name, enabled }` dentro de `serialized_value`. Quem grava é `FeatureFlagRollout.padrao!` (`lib/feature_flag_rollout.rb`): acha o item pelo `name`, troca o `enabled` e salva pelo model. Só mudar o `features.yml` não basta, porque o ConfigLoader do deploy não sobrescreve valor já gravado.

Voltar o padrão para `false` do jeito que o helper faz:

1. PR com `enabled: false` em `nova_conversa_tela` no `config/features.yml`;
2. no mesmo PR, uma migration nova que chame `FeatureFlagRollout.padrao!('nova_conversa_tela', false)` e `GlobalConfig.clear_cache` — é o que o `down` da `20261026100000` faz;
3. vai pela fila normal de deploy.

Não editar essa linha por SQL: o `docs/agendamento-whatsapp-first/ROLLBACK.md` registra que o valor é gravado como YAML dentro do jsonb. Enquanto o PR não sobe, conta criada no intervalo nasce com a tela nova; o passo 2 de "Todas as contas" pode ser repetido.

### Código

Reverter o PR devolve os cinco imports ao `ComposeConversation.vue`, que ficou intacto.
