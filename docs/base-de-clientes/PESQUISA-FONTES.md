# Base de clientes e Relacionamentos: fontes da pesquisa

Os 18 levantamentos completos que sustentam o relatório [PESQUISA-RELACIONAMENTOS.md](PESQUISA-RELACIONAMENTOS.md), feitos em 11/10/2026: 6 sobre o código em produção (commit 3db6d348c2), 6 de mercado e UX e 6 que fecham lacunas apontadas pelo crítico. Cada um traz as fontes (arquivo:linha ou URL).

## codigo: relac-front

# Relacionamentos: mapa do front em produção e o que reaproveitar ou remontar

Só li o código, não editei nada. O worktree está no `d987e9dce9`. O `3db6d348c2` é ancestral dele e não há diferença em `app/javascript` entre os dois, então o front lido é o mesmo do commit pedido. Caminhos relativos a `app/javascript/dashboard/`.

## 0. Flags e navegação

| Flag | Padrão | Efeito no front |
|---|---|---|
| `relationships_navigation` | off (`config/features.yml:293`) | Liga a Home, o breadcrumb, as abas novas, o resumo e o seletor de visão. Na sidebar, troca os grupos Contatos e Empresas e o item "Atributos Personalizados" de Configurações por um item único, "Relacionamentos" (`components-next/sidebar/Sidebar.vue:1371-1401`) |
| `relationships_attributes` (+ `custom_attributes`) | off (`features.yml:283`) | Liga FieldConfigurator, FieldEditor e RelationshipFields (`composables/useRelationships.js:45-52`) |
| `relationships_company_media` (+ `companies`) | off (`features.yml:288`) | Aba Mídias da empresa e rota `relationships_company_media` (`useRelationships.js:57-61`) |
| `companies` | off, premium (`features.yml:229`) | Empresas, cards e métricas de empresa |
| `crm` | on (`features.yml:99`) | Rotas de contatos (`routes/dashboard/contacts/routes.js:10-13`) |
| `customer_base` | off (`features.yml:330`) | **Nenhuma referência no front.** Só backend: `app/services/campaign_imports/*` |
| globalConfig `CRM_KANBAN_ENABLED` | — | Aba e botão de Oportunidades |
| globalConfig `CAMPAIGN_JOURNEY_ENABLED` + `CAMPAIGN_IMPORT_ENABLED` | — | Importação nova. Sem as duas, volta o diálogo CSV do Chatwoot (`contacts/import/contactImport.routes.js:10-12,38-41`) |

Problemas na navegação:
- Com a navegação nova, Segmentos e Etiquetas saem da sidebar. Só aparecem num seletor ("Segmentos: X", "Marcado com: Y") em `components-next/Relationships/ContactViewSelect.vue:15-38`.
- As rotas `contacts_import_journey` e `contacts_campaign_imports` não estão no `activeOn` (`Sidebar.vue:1386-1399`). Na tela de importar, a sidebar perde o destaque.

## 1. Home de Relacionamentos

`routes/dashboard/relationships/RelationshipsHome.vue`, rota `relationships_home` (`relationships/routes.js:9-23`).

- **Objetivo:** porta de entrada para Contatos, Empresas e Atributos.
- **O que mostra:** um cabeçalho (ícone, título e subtítulo de marketing, linhas 79-97) e três cards. Cada card tem ícone, título, subtítulo, descrição longa, três "capacidades" com ícone e um botão (linhas 37-68 e 108-156). No fim, um aviso fixo "Relacionamentos mais fortes geram mais oportunidades" (linhas 159-175).
- **Ações:** só navegar.
- **Problemas para o leigo:**
  - Não mostra nenhum dado: nem número de contatos, nem pendência.
  - Cerca de 15 textos antes de qualquer ação.
  - Jargão: "Atributos personalizados", "Configurar atributos", "Campos globais nesta conta", "definições de campos" (`i18n/locale/pt_BR/relationships.json:6,113,131-137`).
  - A descrição muda conforme as flags (`DESCRIPTION` vs `BASIC_DESCRIPTION`, linhas 31-36).
  - O card de Empresas usa as permissões `['administrator','agent']` (linha 52), mas a rota de empresas aceita também `contact_view` e `contact_manage` (`companies/routes.js:14-19`). Uma função personalizada com `contact_view` entra na rota mas não vê o card.
- **Componentes:** `Icon` e `Policy`. Os cards são HTML com Tailwind, sem componente do design system.

## 2. Lista de contatos

`routes/dashboard/contacts/pages/ContactsIndex.vue`, com `components-next/Contacts/ContactsListLayout.vue`, `ContactsHeader/ContactListHeaderWrapper.vue`, `ContactHeader.vue`, `Pages/ContactsList.vue` e `ContactsCard/ContactsCard.vue`.

- **Objetivo:** encontrar e agir sobre pessoas.
- **O que mostra, de cima para baixo:**
  1. Seletor de visão e breadcrumb (`ContactsIndex.vue:509`).
  2. Cabeçalho com título, busca e ícones de filtro, salvar segmento, apagar segmento e ordenar. O menu ⋮ tem Adicionar, Exportar, Importar, "Importar base" e Histórico. Ao lado, o botão "Enviar mensagem" (`ContactHeader.vue:38-129`; `ContactMoreActions.vue:24-77`).
  3. "Acompanhamento da base", com 4 métricas de 30 dias (`Relationships/RelationshipSummary.vue:21-42,72-140`; `ContactsIndex.vue:535`).
  4. Os cards de contato.
- **Ações:**
  - Buscar, filtrar, criar e apagar segmento, ordenar, criar, importar e exportar.
  - Ações em massa: etiquetar, tirar etiqueta e excluir (`ContactsIndex.vue:342-407`, `ContactsBulkActionBar`).
  - Editar dentro do card, que expande um formulário com o botão "Atualizar contato" e uma seção de excluir (`ContactsCard.vue:198-241`).
  - "Ver detalhes" (`ContactsCard.vue:188-193`).
- **Estados vazios:**
  - Conta sem contatos: `ContactEmptyState`, com cards de exemplo e o botão "Adicionar contato" (`ContactsIndex.vue:556-563`).
  - Busca, filtro ou visão vazios: só texto, com emoji ("…🔍", "…📋", "…🌙"; `pt_BR/contact.json` em `CONTACTS_LAYOUT.EMPTY_STATE`).
- **Problemas para o leigo:**
  - Ações principais escondidas: Importar só aparece no ⋮.
  - Botões só com ícone (filtro, salvar, lixeira) e sem rótulo (`ContactHeader.vue:68-106`).
  - A seleção para ação em massa só aparece ao passar o mouse no avatar (`ContactsList.vue:75-77`). Não funciona no toque e ninguém descobre.
  - Dá para editar no próprio card e também na ficha: são dois lugares para a mesma coisa.
  - O título "Contatos" aparece duas vezes, no cabeçalho e no seletor de visão.
  - Jargão: "Segmentos", "Marcado com", "Ativo", "Visão de contatos", "Acompanhamento da base".
  - Títulos com maiúscula em toda palavra: "Todos os Contatos", "Atributos Personalizados" (`pt_BR/settings.json` em `SIDEBAR`).
  - Os ícones de exportar e importar parecem trocados: exportar usa `upload`, importar usa `download` (`ContactMoreActions.vue:45,57`).
- **Bug provável:** `ContactEmptyState.vue:52` chama `toggleExpanded`, que não existe no componente. O clique na seta dos cards de exemplo deve dar erro.
- **Componentes:** `Input`, `Button`, `DropdownMenu`, `CardLayout`, `Avatar`, `Checkbox`, `Flag`, `ChoiceSelect`, `Spinner`, `Dialog`, `PaginationFooter`, `EmptyStateLayout`.

## 3. Ficha do contato

`routes/dashboard/contacts/pages/ContactManageView.vue`, com `components-next/Contacts/ContactsDetailsLayout.vue` e `Pages/ContactDetails.vue`.

- **Coluna esquerda** (`ContactDetails.vue:178-283`):
  - Avatar, nome, "Criado… • Última atividade…" e etiquetas.
  - Ações (`Relationships/ContactDetailActions.vue:33-67`): "Nova oportunidade", que abre o CRM em outra aba (`ContactOpportunityLink.vue:27-41`), "Enviar mensagem", "Ligar" e o menu Bloquear.
  - O `ContactsForm`, só com placeholders e sem rótulos: nome, sobrenome, e-mail, telefone, cidade, país, "biografia", empresa e 8 redes sociais (LinkedIn, GitHub…; `ContactsForm.vue:36-56,293-330`), mais o botão "Atualizar contato".
  - "Campos personalizados" (`RelationshipFields`, superfície `contact_details`).
  - "Cliente" (`ContactCustomerSection`), "Mensagens ativas" (`ContactOptOutSection`) e "Excluir contato", só para administrador.
- **Coluna direita, "Acompanhamento"** (`RelationshipTabs.vue:29-60`): até 6 abas. São Oportunidades, Atributos, Histórico, Notas, Mídia e Mesclar (`ContactManageView.vue:75-100`). A aba padrão é Notas (linha 36), embora Oportunidades venha primeiro.
- **Sem permissão de escrita:** aparece `RecordReadOnly`, com 8 linhas fixas (`ContactDetails.vue:48-91,235`).
- **Problemas para o leigo:**
  - **Os mesmos dados em três editores diferentes:**
    1. "Campos personalizados" à esquerda (`FieldEditor`).
    2. A aba "Atributos" à direita (`ContactCustomAttributes.vue` + `ContactCustomAttributeItem`), com divisão "usados / não usados" e uma busca com `<input>` cru (linhas 113-159).
    3. A lateral do atendimento (`routes/dashboard/conversation/customAttributes/CustomAttributes.vue:293-345`, superfície `contact_sidebar`).
  - **O vazio padrão manda para a outra tela.** No modo `legacy`, `contact_details` não mostra nenhum campo (`Relationships/presentation.js:1-9`). A ficha exibe "Nenhum campo destacado nesta ficha… continuam disponíveis na aba Atributos" (`relationships.json:164-165`). O próprio texto aponta para a outra tela.
  - **Empresa existe de dois jeitos:** o texto livre `additionalAttributes.companyName` e o vínculo `companyId` pelo `CompanySelector`, que aparece por regra condicional (`ContactsForm.vue:44,100-104`). Isso afeta direto a Base de clientes (pessoa × empresa).
  - Botões "Configurar campos" e "Criar atributo" dentro da ficha: a configuração da conta mistura com o preenchimento do registro (`FieldConfigurator.vue:272-292`).
  - Jargão: "Mesclar", "Atributos", "Acompanhamento", "biografia", "Oportunidades no CRM", "Não arquivadas", "Resultados nesta consulta".
  - Uma tela com cerca de 10 blocos e mais de 6 abas, sem uma ação principal.

## 4. Aba Oportunidades (contato e empresa)

`components-next/Relationships/RelationshipOpportunities.vue`, com `useRelationshipOpportunities.js` e `useContactOpportunities.js`.

- **O que mostra:** título, ajuda, botão atualizar, busca com botão de lupa, seletor "Situação" com 8 opções (linhas 32-41), contagem, cards (título, funil · etapa, status colorido, valor, responsável, previsão) e paginação Anterior/Próxima.
- **Ações:** clicar abre o card no CRM **em outra aba** (`target="_blank"`, linhas 172-178).
- **Estados:** carregando, erro com "Tentar novamente", e vazio "Nenhuma oportunidade nesta consulta" com "Confira a busca e a situação…" (linhas 255-269). Para um contato sem nenhum negócio, o texto culpa o filtro.
- **Problemas:**
  - É um formulário de consulta dentro de uma aba estreita.
  - Abrir em outra aba desorienta o usuário leigo.
  - A ajuda fala de permissão: "Apenas oportunidades que você pode acessar" (`pt_BR/crm.json`, em `CONTACT_OPPORTUNITIES.HELP`).
- **Reaproveitar:** o formato do card e a formatação de moeda e data, que já tratam fuso e moeda inválida (linhas 50-67).

## 5. Lista e ficha de empresas

`routes/dashboard/companies/pages/CompaniesIndex.vue` e `CompanyDetailView.vue`.

- **Lista:** busca, ordenação, criar (`CompanyCreateDialog`), resumo de 4 métricas e `CompaniesCard`.
  - O estado vazio é só o texto "Nenhuma empresa encontrada", **sem botão** (`CompaniesIndex.vue:190-197`).
  - O carregamento é texto, sem esqueleto.
- **Ficha, coluna esquerda:**
  - `CompanyProfileCard`.
  - Ações "Ver site" e ⋮ Excluir (linhas 316-345).
  - `RelationshipFields` na superfície `company_details` (linha 348).
- **Ficha, abas:** Oportunidades, Histórico, Notas, "Contatos (n)", Atributos e Mídias (linhas 110-133). A padrão é Contatos (linha 42).
- **Problemas:**
  - A mesma duplicação do contato: "Campos personalizados" à esquerda e a aba "Atributos" (`CompanyCustomAttributes.vue`) com outro editor.
  - O vazio da aba diz "Não há atributos personalizados da empresa configurados ainda" (`pt_BR/companies.json`).
  - Com Oportunidades ligada, as abas viram uma grade de 3 colunas (linhas 380-383). São 6 abas em 2 linhas.

## 6. Mídias (empresa e contato)

`routes/dashboard/relationships/CompanyMediaView.vue` (rota de página inteira), `Relationships/CompanyMedia.vue` e `RelationshipMedia.vue` (707 linhas), `ContactMediaPanel.vue` e `Contacts/ContactsSidebar/ContactMedia.vue`.

- **O que mostra:** busca por nome de arquivo, filtros (tipo, contato, De/Até, "Agrupar por contato") e uma tabela com Visualizar, Baixar e "Ir à mensagem".
- **Problemas:** textos técnicos, como "Arquivos armazenados no sistema de conversas autorizadas…", "O período usa o fuso de relatório da conta; sem configuração, UTC." e "{type} · {size} B" (`relationships.json:76-99`). Também há um `<input>` cru em `RelationshipMedia.vue:417`.

## 7. Atributos (configurações) e editores de campo

### 7a. Lista de atributos

`routes/dashboard/settings/attributes/Index.vue`, rota `attributes_list` (`attributes.routes.js:19-27`). Fica em Configurações, com o breadcrumb de Relacionamentos quando a navegação nova está ligada.

- **O que mostra:**
  - Abas Conversas, Contato, Empresa e Card (linhas 82-109).
  - Contagem, busca, "Configurar campos" (só em Contato e Empresa) e "Criar atributo personalizado".
  - Uma lista `AttributeListItem` com nome, **tipo cru em inglês** ("text", "list"; `Index.vue:197` → `ConversationWorkflow/AttributeListItem.vue:52`), **chave com ícone de chave** (`AttributeListItem.vue:59-65`) e descrição.
- **Ações:** criar, editar e excluir. Para excluir é preciso digitar o nome (`woot-confirm-delete-modal`, linhas 313-334).
- **Com `relationships_attributes` ligado,** criar e editar abrem o `FieldConfigurator`, inclusive nas abas Conversas e Card (linhas 63-69, 132-139, 221-225).
  - **Provável bug:** com `entity='card'`, `ENTITY_LABELS.card` não existe em `pt_BR/relationships.json:158-162` (nem no `en`). O diálogo mostraria a chave crua "RELATIONSHIPS.ENTITY_LABELS.card" e o ícone de conversa (`FieldConfigurator.vue:352-362`).
- **Com a flag desligada,** abre o `AddAttribute.vue`. Ele expõe "Chave", "Expressão Regex", "Orientação de validação Regex", "Aplica-se a" e "Caixa de seleção" (`pt_BR/attributesMgmt.json`, em `ADD.FORM`).
- **Texto do cabeçalho:** "Um atributo personalizado controla detalhes adicionais…" (`attributesMgmt.json`, `DESCRIPTION`), longo e técnico.

### 7b. `FieldConfigurator.vue` (diálogo `Dialog`, largura xl)

Tem dois modos:
- **Configurar** (linhas 462-568): busca, seletor "Local de exibição" (Lateral do atendimento / Ficha do contato), um interruptor por campo, "Restaurar padrão", "X de Y campos selecionados" e "Editar".
- **Criar/Editar** (linhas 365-461): Nome, Descrição (obrigatória só ao criar, linhas 139-145), Tipo com `ChoiceSelect` (travado ao editar, linha 408), Opções "uma por linha" em textarea e "Onde exibir este atributo" com interruptores por superfície.

A chave é gerada do nome (`presentation.js:18-29`) e não aparece na tela. Isso é bom. O texto de erro, porém, cita "chave" (`relationships.json:19`).

Problemas:
- "Entidade: Contato" aparece na tela (linhas 347-364).
- Aviso "Válido para a equipe desta conta. Ocultar não apaga valores nem restringe acesso." (linha 344).
- "Restaurar padrão" volta ao modo `legacy`, sem explicar o efeito.
- O título diz "Criar atributo", mas a seção da ficha se chama "Campos personalizados". Os nomes divergem.
- Não há prévia de como o campo vai aparecer.
- Os tipos legados "Moeda (legado)" e "Percentual (legado)" aparecem ao editar (linhas 60-68; `relationships.json:45-46`).

### 7c. `FieldEditor.vue` (um campo, com edição no lugar)

- **Lendo:** ícone do tipo, nome e um ⓘ com a descrição num `<details>`, que é um tooltip artesanal (linhas 287-300). O valor aparece como "Não informado", "Sim/Não" ou data formatada, com botões copiar, editar e limpar só com ícone (linhas 393-423).
- **Editando:** `ChoiceSelect` para lista, **`<input type="checkbox">` cru** para sim/não (linhas 310-322), `Input` para o resto e os botões Salvar, Cancelar e Limpar.
- **Campos com `regex_pattern`** caem no `CustomAttribute` legado, ou seja, outro editor e outro endpoint (linhas 140-153, 253-272).
- **Salvar:** usa um PATCH `/relationships/{entity}/{id}/values` com `previous` (controle de conflito 409) e protege contra resposta de outro registro (linhas 154-186). **Vale reaproveitar.**

### 7d. `RelationshipFields.vue`

Seção "Campos personalizados" com descrição, os botões do configurador, uma grade de `FieldEditor` e o vazio (linhas 26-66).

Problema: o vazio tem duas frases técnicas e nenhum botão (`relationships.json:164-165`).

### 7e. Também usam o FieldConfigurator

- O CRM, em `routes/dashboard/crm/components/CrmRelationshipResources.vue:149-155`.
- `CrmCardCustomFields.vue:64-67` manda para `attributes_list`.

Mexer no configurador afeta o painel do card.

## 8. Importação de contatos (entra na Base de clientes)

`routes/dashboard/contacts/import/ContactImportPage.vue` com `components-next/ContactImport/*`:
- `ContactImportColumns`
- `ContactImportCompanies`
- `ContactImportProblems`
- `ContactImportResult`
- `contactImportView.js`

Passos: enviar → ler → colunas → pessoas → empresas → importar → resultado, com consulta a cada 2 s (`ContactImportPage.vue:1-4,31,100-112`). O cabeçalho diz que a tela não nomeia o motor de leitura (linhas 3-4). Isso já segue a regra de não citar IA.

**Não existe hoje** separação de colunas em PESSOA / EMPRESA / NEGÓCIO, nem criação de campo com nome e descrição durante a importação.

## 9. i18n pt_BR envolvida

| Arquivo | Uso |
|---|---|
| `i18n/locale/pt_BR/relationships.json` | Home, campos, mídias, resumo |
| `contact.json` | `CONTACTS_LAYOUT` |
| `companies.json` | Empresas |
| `attributesMgmt.json` | Tela de atributos |
| `crm.json` | Oportunidades |
| `settings.json` | `SIDEBAR` |
| `contactImportJourney.json` | Importação |

Jargão recorrente: atributo, entidade, chave, regex, segmento, mesclar, card, "legado", UTC, "não arquivadas", "consulta". Há emojis e maiúsculas em toda palavra nos estados vazios e títulos.

Não achei `<select>` nativo nessas telas: a escolha usa `ChoiceSelect` e `ComboBox`. Mas há `<input>` crus: o checkbox em `FieldEditor.vue:310`, a busca em `ContactCustomAttributes.vue:134` e um input em `RelationshipMedia.vue:417`.

## 10. O que reaproveitar e o que remontar

**Reaproveitar (lógica e componentes sólidos):**
- **`useRelationships.js`:** sessão por usuário e conta, revisão e 409, invalidação. Também `useRelationshipPermissions.js` e `confirmedValues.js`.
- **`presentation.js`:** `selectDefinitions`, `fieldValue` e `attributeKey`, que gera a chave sem pedir ao usuário.
- **A lógica de gravação do `FieldEditor`,** com o endpoint `/values`, `previous` e a proteção de corrida. Remontar só a parte visual.
- **O modelo de superfícies** (`contact_sidebar` / `contact_details` / `company_details`) e o endpoint `relationships/configuration`.
- **`RelationshipTabs.vue`,** que tem teclado WAI-ARIA e alvo de 44 px, e **`RelationshipBreadcrumb.vue`.**
- **Os dados de `RelationshipSummary`** (endpoint `/summary`). A forma visual pode mudar.
- **Componentes do design system:** `ChoiceSelect`, `ComboBox`, `Dialog`, `Button`, `Input`, `TextArea`, `Switch`, `Avatar`, `Spinner`, `EmptyStateLayout`, `PhoneNumberInput`, `CompanySelector`.
- **O card de oportunidade** (formatação de valor e data) e `useRelationshipOpportunities.js`.
- **O motor da importação:** API `contactImports`, `contactImportView.js` e as etapas de colunas, problemas e resultado.
- **As seções já escritas para leigo:** "Cliente" (`ContactCustomerSection`) e "Mensagens ativas" (`ContactOptOutSection`). O tom do texto é bom (`contact.json`, `DETAILS.CUSTOMER` e `OPT_OUT`).

**Remontar:**
1. **Home:** de "3 cards de marketing" para uma tela de trabalho, com dados reais, uma ação principal e a entrada da Base de clientes.
2. **Um único lugar para os campos de cada registro.** Eliminar a aba "Atributos" (`ContactCustomAttributes` / `CompanyCustomAttributes`) ou fundi-la com "Campos personalizados", e acabar com o vazio `legacy` que aponta para a outra aba.
3. **Ficha do contato:** reduzir para uma ação principal e poucas abas. Tirar Mesclar e 8 redes sociais do caminho principal. Formulário com rótulos. Resolver empresa como texto livre × empresa vinculada.
4. **Lista de contatos:** importar visível, seleção visível no toque, sem edição dentro do card, estados vazios com 1 frase e 1 botão, sem emoji.
5. **Criação de campo:** tirar "Entidade", "Restaurar padrão", tipos legados e checkbox cru. Adicionar prévia e linguagem de "pergunta" (nome e explicação), sem citar chave nem tecnologia. Separar configurar a conta de preencher o registro.
6. **Tela de atributos em Configurações:** tipo cru em inglês, chave à mostra, Regex no formulário antigo e o bug do rótulo `card`.
7. **Lista de empresas:** vazio com botão.
8. **Mídias:** tirar os textos técnicos de fuso, UTC e bytes.
9. **Oportunidades:** abrir no próprio contexto, sem nova aba. O vazio não deve culpar o filtro quando não há negócio nenhum.
10. **Importação, para a Base de clientes:** falta a etapa que separa colunas em pessoa, empresa e negócio, a decisão "o dado do negócio também vai para a pessoa?" e a criação de campo com nome e descrição no meio do fluxo. O flag `customer_base` hoje só existe no backend.
11. **Sidebar:** Segmentos e Etiquetas sumiram da navegação, e falta o destaque nas rotas de importação.


## codigo: relac-back

O worktree está em `d987e9dce9`, que descende de `3db6d348c2`. Rodei `git diff --stat 3db6d348c2 HEAD` em `app/services/relationships`, `app/controllers/api/v1/accounts/relationships`, `app/models` e `enterprise/app/models` e veio vazio. Por isso as linhas citadas abaixo valem para o commit de produção. Os caminhos são relativos a `/Users/rodrigosilva/dev/worktrees/chat2you/relacionamentos-pesquisa`.

## 1. Modelo de dados real

**Pessoa = `contacts`** (`app/models/contact.rb`)
- Colunas nativas: `name`, `email`, `phone_number`, `identifier`, `company_id`, `contact_type`, `customer_since`, os campos de recusa `opted_out_at`/`opt_out_source`/`opted_out_by_id`, `additional_attributes` (jsonb) e `custom_attributes` (jsonb) (contact.rb:7-28).
- Unicidade por conta: e-mail (sem diferença de maiúsculas), telefone em E.164 e identifier (contact.rb:58-63, índices :43-44).
- `contact_type` pode ser `visitor`, `lead` ou `customer` (contact.rb:79). Um visitante com e-mail, telefone ou rede social vira `lead` sozinho (`app/services/contacts/sync_attributes.rb:22-30`).
- A lista mostra `lead` e `customer` quando `crm_v2` está ligado (contact.rb:191-200).
- **Lead vira cliente** (`app/models/concerns/contact_customer.rb:12-30`):
  - Pelo card: um card ganho chama `become_customer!` (`app/models/crm/card.rb:103,184-186`).
  - À mão: `Contacts::CustomersController` (`app/controllers/api/v1/accounts/contacts/customers_controller.rb:6-14`).
  - `customer_since` guarda só a primeira vez.
- **Recusa de envio ativo:** `ContactOptOut` (`app/models/concerns/contact_opt_out.rb`). As origens são `prospecting`, `email_unsubscribe` e `manual` (:19). Grava sem validar o contato (:37-48). Contato novo, ou que troca telefone ou e-mail, herda a recusa da conta (:97-107). Essas colunas não entram na edição comum (:14).
- **Mescla:** `app/actions/contact_merge_action.rb`.
  - Move conversas, mensagens, inboxes, notas, chamadas, leads da Prospecção e registros do CRM (cards, follow-ups, convidados, convites, paradas de aviso) (:13-23, :68-107).
  - Nos atributos, o contato que fica tem preferência via `deep_merge` (:111-116).
  - Herda a condição de cliente com a data mais antiga (:127-132).
  - Herda a recusa mais firme (:138-152).
- **Nono dígito:** `app/services/contacts/ninth_digit_duplicate_merger.rb`. Fica o contato que tem o 9 (:1-3). Pula o par quando e-mail, identifier, empresa, bloqueio ou nome são diferentes (:10-13). Roda em modo de teste por padrão (:15). A importação reaproveita o contato com ou sem o 9 (`app/services/campaign_imports/contact_matcher.rb:9-23`).

**Empresa = `companies`** (só existe no Enterprise, atrás da flag `companies`) (`enterprise/app/models/company.rb`)
- Colunas: `name` (obrigatório), `domain`, `description`, `contacts_count`, `last_activity_at`, `additional_attributes`, `custom_attributes` (:3-15).
- O domínio é único por conta (:19, :34). **O nome não é único**: o índice de nome não tem UNIQUE (:21).
- **Não há CNPJ no modelo `Company` nem em código de empresa.** Procurei "cnpj" em `enterprise/app/models`, no controller e nos services de empresa e no front de Companies/Relationships, e não achei nada. Hoje CNPJ só aparece na Prospecção (`app/models/autonomia/prospecting/company_profile.rb:8`). O controller aceita `additional_attributes: {}` livre (`enterprise/app/controllers/api/v1/accounts/companies_controller.rb:98`), mas nenhuma chave de CNPJ é tratada.
- **Ligação pessoa → empresa:**
  - Uma empresa por contato (`belongs_to :company`, `enterprise/app/models/enterprise/concerns/contact.rb:6`).
  - O vínculo é gravado por `Companies::ContactMembershipService#assign/remove` (`enterprise/app/services/companies/contact_membership_service.rb:8-15`).
  - O contato copia o nome da empresa para `additional_attributes['company_name']` (concerns/contact.rb:46-54).
  - Na primeira vez que um contato recebe e-mail, ele é associado a uma empresa pelo domínio desse e-mail (concerns/contact.rb:18-40). A importação desliga isso com `skip_company_auto_association`.

**Negócio = `crm_cards`** (`app/models/crm/card.rb`)
- Colunas: `title`, `value_cents`, `currency`, `status`, `stage_id`, `pipeline_id`, `owner_id`, `contact_id`, `external_id` (único por conta), `metadata` e `custom_attributes` (jsonb) (:3-28, :65, :107-111).
- **O card não tem `company_id`.** A empresa só é alcançada pelo contato do card.
- Os campos do card são gravados juntando com o que já existe, com o card travado, em `cards_controller.rb:482-492`. Esse caminho **não valida o tipo** do valor, ao contrário do `ValueValidator` usado em contato e empresa.

**Definição de campo** (`app/models/custom_attribute_definition.rb`)
- Entidades: `conversation`, `contact`, `company` e `card` (:48).
- Tipos: `text`, `number`, `currency`, `percent`, `link`, `date`, `list`, `checkbox` (:49).
- Tem `attribute_description` (:6) e `attribute_values` para listas.
- A chave é única por conta + entidade (:21, :38-41) e não pode repetir um campo nativo (:25-32, :99-106).

## 2. Como um campo novo aparece na página do contato e da empresa

Há três caminhos para criar o campo, e só um deles cuida da exibição:

1. **`PATCH /relationships/configuration`** (`config/routes.rb:798-801`), que chama `Relationships::Configuration#update!` e depois `DefinitionWriter#save!`. É o caminho certo:
   - **Exige descrição** no campo novo (`definition_writer.rb:51-52`) e nome único por entidade, sem diferença de maiúsculas (:60-65).
   - Lista precisa ter opções únicas (:67-72).
   - Tipo, entidade e chave não mudam depois de criados (:42).
   - **Só aceita os tipos `text number link date list checkbox`** (`configuration.rb:10`); `currency` e `percent` ficam de fora.
   - O backend não gera a chave. Quem gera é o front, com `attributeKey(name)` (`app/javascript/dashboard/components-next/Relationships/presentation.js:19-29`).
   - O mesmo payload aceita `display_on: [...]`, que põe o campo nas telas (`presentation.rb:15-23`).
   - Edições ao mesmo tempo são tratadas por `revision` da configuração (`configuration.rb:47`) e da definição (`definition_writer.rb:45`). A conta fica travada durante a gravação (`configuration.rb:30`).
2. **`POST /custom_attribute_definitions`** (`app/controllers/api/v1/accounts/custom_attribute_definitions_controller.rb:11-15, 36-46`). Não exige descrição e não mexe nas telas.
3. **A importação de contatos** (`app/services/contact_imports/custom_attributes.rb:47-58`). Cria campo `text` **sem descrição** e **sem mexer nas telas**. O comentário em `attribute_columns.rb:7-8` diz que o campo "aparece na página do contato", e isso só vale em parte (ver abaixo).

**Regra de exibição**, gravada em `accounts.settings['relationships']`:
- Formato: `{ version, revision, surfaces: { <tela>: { mode: legacy|custom, ids: [...] } } }` (`configuration.rb:16-26`).
- As telas existentes são `contact_sidebar`, `contact_details` e `company_details` (`configuration.rb:6-7`). **Não há tela para card.**
- No front (`presentation.js:1-9`):
  - Sem configuração, ou em modo `legacy`: a lateral da conversa mostra **todos** os campos de contato, e `contact_details` e `company_details` mostram **nenhum**.
  - Em modo `custom`: aparecem só os ids da lista.
- Na prática: para um campo aparecer na página do contato (`ContactDetails.vue:251-256`) ou da empresa (`CompanyDetailView.vue:351`), o id dele **tem que entrar em `surfaces.contact_details.ids` ou em `company_details.ids`**. Hoje isso só acontece pelo caminho 1, com `display_on`. Um campo criado pela importação não aparece na página do contato até alguém marcá-lo.
- A seção de campos só aparece com as flags `relationships_attributes` e `custom_attributes` ligadas, e também `companies` no caso da empresa (`configurations_controller.rb:30-35`, `RelationshipFields.vue:27-28`).
- Editar um valor: `PATCH /relationships/:entity/:id/values` com `{key, value, previous}` (`values_controller.rb:11-18`, `value_patch.rb:7-23`).
  - Só aceita `contact` e `company` (`values_controller.rb:27`).
  - Recusa campo que tenha `regex_pattern` legado (`value_validator.rb:7-10`).
  - Formato da data: ISO `AAAA-MM-DD` (:48-50).

**Descrição e preenchimento automático no CRM:** a descrição é enviada ao preenchimento automático (`app/services/crm/ai/attribute_schema_builder.rb:45-48`), que a trata como a regra de preenchimento. Mas o esquema só inclui **contato, conversa e card**, sem empresa (:19-20, :29). O que for lido na conversa vai para o contato ou para o card avaliado (`attribute_extractor_applier.rb:16-23`). **Campo de empresa nunca é preenchido pela leitura das conversas.**

## 3. Permissões

**Não existe chave `relationships_*` de permissão.**
- As chaves aceitas estão em `CustomRole::PERMISSIONS` (`enterprise/app/models/custom_role.rb:57-94`).
- `relationships_*` existe apenas como **flag de recurso**: `relationships_attributes`, `relationships_navigation`, `relationships_company_media` (`app/javascript/dashboard/featureFlags.js:2-4`).

Como cada coisa é liberada hoje:

| O quê | Quem pode | Onde |
|---|---|---|
| `permission_granted?` em geral | No OSS, só administrador. No EE, também as chaves da função, e `_manage` implica `_view` | `app/models/account_user.rb:73-75`, `enterprise/app/models/enterprise/account_user.rb:7-14` |
| Ver a configuração | Administrador ou agente | `CustomAttributeDefinitionPolicy#index?` (:2-4), `configurations_controller.rb:7` |
| Criar campo e mudar as telas | `attribute_manage` | `custom_attribute_definition_policy.rb:10-20`, `configurations_controller.rb:13`; o front recebe `can_manage` em :9 |
| Gravar valor, editar contato ou empresa | Administrador, agente sem função personalizada, ou função com `contact_manage` | `relationship_record_write?` (`enterprise/app/policies/relationships/record_permissions.rb:7-12`) via `Enterprise::ContactPolicy` (:4-18) e `CompanyPolicy` (:20-34) |
| Importar e exportar | Administrador ou `contact_manage` | `enterprise/app/policies/enterprise/contact_policy.rb:20-26`, `contact_imports_controller.rb:11` |
| Apagar | Só administrador | `contact_policy.rb:54-56`, `company_policy.rb:36-38` |

## 4. Limites e lacunas para uma "Base de clientes" com pessoa, empresa e negócio

1. **A importação não cria negócio.** Nenhuma referência a `Crm::Card` em `app/services/campaign_imports` ou `app/services/contact_imports` (só jobs do CRM citam card). As colunas que se escolhem são só `name`, `phone`, `email` e `company` (`contact_imports_controller.rb:29-32`). Para criar cards seria preciso escolher funil e etapa, título e valor, e decidir a regra contra duplicado. O `external_id` único por conta (`card.rb:65,107`) serve como chave para não duplicar.
2. **Toda coluna extra vai para o contato** (`attribute_columns.rb:60`, `custom_attributes.rb:23-33`). Não há como mandar uma coluna para a empresa ou para o card, nem para "o card e também o contato".
3. **A importação cria campo só do tipo texto, sem descrição e sem exibição** (`custom_attributes.rb:51`). Isso enfraquece o preenchimento automático e deixa o campo fora da página do contato. Ela deveria criar pelo `DefinitionWriter` com `display_on`.
4. **Uma coluna da planilha não vira tipo `currency` ou `percent` pela tela nova** (`configuration.rb:10`), embora a importação saiba converter esses tipos (`attribute_value.rb:14,57-64`).
5. **Empresa sem CNPJ e sem nome único.** A empresa é achada pelo domínio de e-mail comercial e, se não der, pelo nome normalizado. Nos duplicados ganha a mais antiga (`app/services/campaign_imports/company_resolver.rb:5-7,28-33`). Duas filiais com o mesmo nome viram uma só, e um nome escrito diferente cria duplicata. Também não há tela de mescla de empresa.
6. **A importação não sobrescreve nada:**
   - Contato existente só ganha o que falta (`app/services/campaign_imports/contact_blank_fields.rb:13-19`, `custom_attributes.rb:27`).
   - Contato que já tem empresa diferente fica com ela (`company_linker.rb:68,83-86`).
   - Não existe modo "atualizar".
7. **Card sem empresa.** Um "dado de negócio que também é da empresa" não tem onde ficar no card; só no contato ou no próprio card.
8. **Campo de empresa fica fora do preenchimento automático** (ver seção 2).
9. **Card sem tela de exibição e sem validação de tipo.** Não há surface `card_*` em `configuration.rb:6-7`, e o `PATCH` do card não valida o tipo do valor (`cards_controller.rb:486-488`).
10. **Marcar como cliente na importação.** O contato importado com telefone ou e-mail entra como `lead` (`sync_attributes.rb:22-30`). Para a planilha "já são clientes" existe o método `become_customer!`, mas nenhum caminho de importação o chama hoje.
11. **Exige muitas flags ao mesmo tempo:**
    - `companies`, `custom_attributes`, `relationships_attributes` e `customer_base` (leitura nova, `app/services/campaign_imports/contact_reading.rb:12,78-79`).
    - `CAMPAIGN_JOURNEY_ENABLED` e `CAMPAIGN_IMPORT_ENABLED`; sem elas a importação responde 404 (`app/services/contact_imports/config.rb:1-8`).
12. **O preview de atributos já existe:** "N já eram seus contatos", campos novos e valores que não servem (`app/services/contact_imports/validator.rb:8-18`). Ele cobre o "mostrar antes de fazer" para o contato. Para empresa existe só a contagem (`company_preview.rb:22-33`), e para o card não existe nada.


## codigo: importacao

**Importação por planilha × Base de clientes: o que já existe, o que falta e onde encaixar**

A referência `3db6d348c2` aponta para o commit `d987e9dce9`, que é o HEAD da worktree `/Users/rodrigosilva/dev/worktrees/chat2you/relacionamentos-pesquisa`. Só fiz leitura, nada foi alterado. A pasta `docs/base-de-clientes/` tem só `PRD.md` e `BATERIA-F0.md`: não existe `specs/`.

Resumo em 4 pontos:
- A importação já resolve bem as partes difíceis: ler a planilha, achar as colunas de contato, não duplicar, mostrar prévia e ligar empresas.
- O que falta é o "tudo que não é contato". Toda coluna extra vira campo da pessoa, sem descrição e sempre como texto.
- Hoje nada vai para empresa nem para card. O tipo do contato não é preenchido e não dá para desfazer o lote.
- Achado importante: o campo criado pela importação não aparece na página do contato quando a conta já personalizou o layout. Isso já acontece hoje em produção.

## 1. O que a importação já faz bem

**Leitura do arquivo**
- Lê CSV e XLSX. Acha a linha do cabeçalho e a aba certa por um localizador único (`spreadsheet_reader.rb:43-52`).
- Limites: 10 MB, 50 mil linhas em CSV e 20 mil em XLSX (`campaign_imports/config.rb:10-20`).
- Com a flag `customer_base` ligada, a leitura nova aceita mais formatos (`contact_reading.rb:1-16, 37-52`):
  - celular escrito do jeito nacional;
  - número antigo sem o 9;
  - célula com vários valores (`cell_values.rb:12-21`);
  - planilha sem cabeçalho.
- A decisão de ligar sai da conta, sem estado global (`contact_reading.rb:14-16`, `audience_validator.rb:45-47`).

**Jev (quem reconhece as colunas)**
- Responde quatro perguntas: celular, e-mail, nome e empresa, cada uma podendo ser "não tem" (`typesafe_ai/audience_schema_resolver.rb:23-32`).
- Recebe só cabeçalho, contagens e formato mascarado, nunca o valor real (`audience_schema_resolver.rb:4-7, 88-90`).
- A máscara deixa visível só o DDD e o domínio do e-mail (`jev_mask.rb:1-19`).
- O país do telefone é uma pergunta à parte (`audience_schema_resolver.rb:39-51`). O 9 só é acrescentado quando o Jev diz "Brasil" com confiança e sobre a mesma coluna usada como celular (`phone_country.rb:22-25`).
- Quando não tem certeza, não chuta:
  - aceita a resposta só com confiança ≥ 0,8 (`spreadsheet_reader.rb:100-108`);
  - ao contrário, para em `needs_column_choice` e sugere a coluna (`spreadsheet_reader.rb:110-126, 175-180`);
  - a pessoa escolhe pelo `ChoiceSelect`, sem `<select>` nativo (`ContactImportColumns.vue:98-104`).
- A escolha manual é conferida no servidor (`column_choice.rb:13-21`) e gravada com trava (`draft_changes.rb:14-20`).

**Não duplicar contato**
- Dentro do arquivo: vale a primeira linha, as repetidas são recusadas (`audience_validator.rb:102-116`).
- Contra a base da conta: procura pelo celular, com ou sem o 9, depois pelo e-mail sem diferença de maiúscula (`importer.rb:103-108`, `existing_contacts.rb:20-45`).
- Contato que já existia só ganha o que falta: nome, celular e e-mail (`contact_blank_fields.rb:13-20`). Atributo que ele já tem é mantido (`custom_attributes.rb:23-33`).

**Prévia antes de gravar**
- Mostra "N já eram seus contatos · M novos" (`validator.rb` de contact_imports, linhas 8-18; `contactImportView.js:87-96`).
- Lista os campos novos e os valores que ficam de fora, sem mostrar o valor (`attribute_problems.rb:17-39`).
- Mostra o que vai acontecer com as empresas (`audience_validator.rb:127-132`, `company_preview.rb:22-30`).
- Gera um CSV das linhas recusadas, com o motivo e os dados mascarados (`audience_validator.rb:201-208`, `contact_imports_controller.rb:78-83`).

**Empresas**
- Cria ou reaproveita a empresa, procurando pelo domínio do e-mail e depois pelo nome normalizado.
- Nunca troca uma empresa que o contato já tem.
- Desfaz o que criou se a linha falhar (`company_linker.rb:1-19, 63-72, 144-147`).
- Tem a chave "Criar e ligar" (`contact_imports_controller.rb:43-51`).

**Colunas extras viram campos do contato**
- Reaproveita o campo que já existe, achando pela chave ou pelo nome (`attribute_columns.rb:45-50`).
- Cria um campo novo para o resto (`attribute_columns.rb:52-57`, `custom_attributes.rb:47-58`).
- Converte número, moeda, data (inclusive o número de dia do Excel), sim/não e lista (`attribute_value.rb:6-11, 36-94`).

**Gravação**
- Roda em segundo plano: blocos de 500 linhas, cada linha protegida, eventos de contato desligados durante a carga (`importer.rb:16-27, 76-94`).
- Pode ser reexecutada sem duplicar (`importer.rb:47-58, 67`).
- Guarda por linha o `contact_id`, se o contato já existia e o que aconteceu com a empresa (`importer.rb:139-147`, `db/schema.rb:1145-1173`).
- Só administrador ou função com `contact_manage` (`contact_imports_controller.rb:11`).

## 2. O que falta para a Base de clientes e onde cada coisa entra

| Falta | Situação hoje | Onde entra no código |
|---|---|---|
| **Classificar cada coluna como pessoa, empresa ou negócio** | O Jev só mapeia 4 colunas (`audience_schema_resolver.rb:23-32`). Toda coluna extra vira campo do contato sem perguntar (`spreadsheet_reader.rb:205-212`, `attribute_columns.rb:30-37`). | (a) Uma pergunta nova ao Jev por coluna extra: "pessoa / empresa / negócio / ignorar", com a opção "não sei" (`questions_for`, `audience_schema_resolver.rb:116-131`), na mesma regra de privacidade. (b) Guardar em `schema_resolution['extra_columns']` (hoje só as chaves, `audience_validator.rb:155`). (c) Um endpoint parecido com `PATCH columns` para a pessoa trocar o destino (`draft_changes.rb`, rota no controller). (d) `ContactImports::AttributeColumns` passa a receber o destino e a montar colunas por grupo. |
| **Decidir se o dado de negócio também vai para o contato** | Não existe. | Uma opção por coluna "negócio", guardada no mesmo `schema_resolution`. Na gravação, escreve nos dois lugares. Vale o mesmo critério da IA do CRM: "dado da pessoa vai para o contato; dado do pedido, para o card" (`crm/ai/attribute_extractor_applier.rb:16-21`). |
| **Campos de empresa** | `Company` tem `custom_attributes` (`enterprise/app/models/company.rb:8`) e existe `company_attribute` (`custom_attribute_definition.rb:48`), mas a importação só grava o nome da empresa (`company_linker.rb:97-104`). | Algo como `ContactImports::CustomAttributes` para empresa, chamado logo depois de `import_companies.link` (`importer.rb:83`). Só preenche o que está em branco, como no contato. Precisa ficar escondido sem a flag `companies` (`company_linker.rb:30-32`). |
| **Campos do card e criação do card no funil** | Não existe. O PRD deixou isso para depois da F1 (`PRD.md:114-116`) e para a F2 (`PRD.md:61`). | Chamar `Crm::Cards::Creator` (`crm/cards/creator.rb:4-27`), que já aceita funil, etapa, contato, valor, `custom_attributes` e `external_id`, dentro de `import_one`, depois do contato (`importer.rb:76-86`). A tela pede funil e etapa uma vez só. `external_id` é único por conta (`crm/card.rb:107`) e serve para não duplicar card ao reexecutar. Falta guardar `card_id` na linha da importação, que é tabela do fork, então pode ganhar coluna. Card ganho já promove o contato a cliente (`crm/card.rb:183-186`). |
| **Uma pessoa com vários negócios** | A segunda linha com o mesmo celular ou e-mail é recusada (`audience_validator.rb:107-110`). O PRD já marca isso como risco (`PRD.md:137-139`). | Com coluna de negócio no arquivo, a linha repetida deixa de ser erro: vira o mesmo contato com mais um card. A troca é em `add_duplicate_errors`, sob a flag. |
| **Descrição dos campos** | Os campos são criados só com chave, nome e tipo texto (`custom_attributes.rb:51`). A IA do CRM usa a descrição como regra principal (`crm/ai/attribute_schema_builder.rb:45-48`) e lê campos de contato, conversa e card, **não de empresa** (`attribute_schema_builder.rb:19-20, 28-29`). A coluna `attribute_description` já existe (`custom_attribute_definition.rb:6`). | Na prévia, cada campo novo ganha nome e descrição editáveis, com sugestão pronta. Hoje a prévia só mostra a lista de campos (`ContactImportColumns.vue:120-135`). Gravar em `create_definition` (`custom_attributes.rb:47-52`). Escolher o tipo em vez de sempre texto. Atenção: Relacionamentos só aceita os tipos `text number link date list checkbox` (`relationships/configuration.rb:10`), enquanto a importação converte também moeda e percentual (`attribute_value.rb:14`). |
| **Campos aparecendo no Relacionamentos** | A página do contato mostra só os campos escolhidos no layout dela (`ContactDetails.vue:251-256`, `Relationships/presentation.js:1-9`). No modo de layout original, essa página mostra **nenhum** campo; no modo personalizado, só os escolhidos. O campo criado pela importação **não entra no layout**, então fica escondido. | Ao criar o campo, chamar `Relationships::Presentation#display!` (`relationships/presentation.rb:15-23`), que já existe e é usado pelo `display_on` (`configuration.rb:52`). Não há lugar para campo de card nos layouts (`configuration.rb:6-7`). Isso continua na tela do card no CRM. |
| **Desfazer o lote** | Uma importação de contatos só pode ser apagada enquanto é rascunho (`campaign_import.rb:146-149`). O desfazer que existe só tira etiquetas (`undo_labels.rb:10-30`). A linha não guarda o valor anterior nem os campos preenchidos (`schema.rb:1145-1165`). | Um desfazer próprio de contatos, aproveitando a máquina de estados que já existe (`undo_status` e `undo_*_at`, `campaign_import.rb:40-43, 104-109`) e o mesmo padrão de trava (`undo_labels.rb:36-53`). Ele precisa saber, por linha, o que a importação preencheu: campos, tipo, empresa, card, recusa. Isso vai numa coluna nova da tabela de linhas da importação, que é do fork. Regras ainda abertas no PRD (`PRD.md:129-136`): não apagar contato que recebeu conversa nem empresa ligada a outro contato. |
| **Atualizar contato que já existe** | Só preenche o que está em branco (`contact_blank_fields.rb:13-20`, `custom_attributes.rb:27`). | Uma opção explícita "atualizar o que mudou", desligada por padrão, mostrada na prévia com quantos campos mudam. O valor antigo precisa ser guardado para o desfazer. O ponto de troca é `merge!` e `fill!`. |
| **Tipo do contato (lead ou cliente)** | O contato é criado sem tipo e nasce `visitor` (`importer.rb:80`, `contact.rb:10, 79`). Os cards criam `lead` (`crm/cards/contact_creator.rb:21`). | Em `import_one`: quem é cliente passa por `become_customer!` (`contact_customer.rb:12-20`), o resto vira `lead`, e cliente nunca volta a lead (`PRD.md:90-97`). A coluna que diz o tipo vem do Jev. Sem ela, a tela pergunta uma vez "todos aqui são clientes?". |
| **Recusa de mensagens (opt-out)** | Não é lida. As origens aceitas são só `prospecting email_unsubscribe manual` (`contact_opt_out.rb:19`). | Uma origem nova em `OPT_OUT_SOURCES` e na ordem de precedência da fusão de contatos (`contact_merge_action.rb:6`). Gravar por `opt_out!(source:)` (`contact_opt_out.rb:37`), nunca chamar `opt_in!`. |
| **Flag por conta e entrada própria** | A importação liga por variável de ambiente, para a instalação inteira: no servidor (`contact_imports/config.rb:6-8`, controller 88) e na tela (`contactImport.routes.js:10-12`). A rota fica em Contatos com a flag `CRM` (`contactImport.routes.js:18-25`). A página Relacionamentos só tem rota própria em `relationships/routes.js:8-23`. | Trocar para uma flag da conta (a `customer_base` já existe para a leitura, `contact_reading.rb:12-16`). Criar a rota "Base de clientes" dentro de Relacionamentos, reaproveitando `ContactImportPage.vue` e os componentes `components-next/ContactImport/*`. |
| **Prévia com exemplos e pergunta para coluna ambígua** | A prévia mostra só contagens. | `ready_attributes` (contact_imports/validator.rb:8-18) é onde entram exemplos mascarados. A pergunta em linguagem simples sai da resposta "não sei" do Jev. |

## 3. Riscos para levar em conta

- **Dado pessoal guardado sem máscara e sem prazo.** As colunas extras ficam em `campaign_import_rows.extra_values` (`schema.rb:1163`, `audience_validator.rb:98-100`). Com a base inteira passando por ali, isso pesa mais (`PRD.md:143-146`).
- **Textos da tela fora das regras de UX.** Hoje a tela diz "Colunas encontradas" e "Outras colunas viram atributos". "Atributo" é termo técnico: precisa ser reescrito.
- **Leitura confere com a produção.** A bateria F0 provou que, com a flag desligada, o resultado é idêntico ao `main` byte a byte (`BATERIA-F0.md:61-91`). Qualquer mudança nova precisa repetir essa prova.


## codigo: crm

# Base de clientes × CRM: como o código atual trata cards, contatos e campos

**Sobre a versão lida.** A worktree estava no commit `d987e9dce9`, 8 commits atrás do `3db6d348c2`. Comparei os dois: dentro do CRM só `app/services/crm/reports/*` mudou, e conferi direto no `3db6d348c2` as linhas que cito de `summary.rb:78-81` e `importer.rb:80`. Os outros arquivos citados são iguais nos dois commits.

## 1. Como uma importação poderia criar cards

**Requisitos do card**
- O card exige funil e etapa (`app/models/crm/card.rb:82-83`). A etapa tem que ser do mesmo funil (`card.rb:113,195-200`). O título é obrigatório (`card.rb:105`).
- O identificador externo (`external_id`) é único por conta (`card.rb:107`). Isso serve para reimportar a mesma planilha sem duplicar card, que é o mesmo truque da prospecção (`autonomia/prospecting/crm_card_converter.rb:35-40,108-110`).

**O ponto de entrada é `Crm::Cards::Creator`** (`app/services/crm/cards/creator.rb`)
- Aceita `status` e `custom_attributes` entre os campos (`creator.rb:4-7`).
- Sem usuário (`user`), o card nasce sem dono (`creator.rb:67-72`).
- O resultado do card segue o tipo do funil (`creator.rb:21`, `crm/cards/outcome.rb:14-19`):
  - em funil que conta como venda, ele fica ganho (`won`);
  - nos outros funis, um "ganho" pedido vira `resolved` (resolvido).

**Onde colocar o card.** Hoje não existe "funil padrão da importação".
- O sincronizador de conversas usa a etapa padrão da caixa ou a primeira etapa do funil (`crm/conversations/card_syncer.rb:203-205`).
- A importação teria que pedir o funil, ou criar um funil próprio.

**"Já é cliente" pode entrar de dois jeitos**
- **Opção A: card já ganho.** Quando o status muda para `won`, o sistema grava a data de fechamento (`closed_at`) e promove o contato a cliente (`card.rb:100,103,174-186`).
- **Opção B: sem card.** Marcar o contato como cliente direto (`contact_type: customer` + `customer_since`), como já faz o botão manual (`contacts/customers_controller.rb:7`).

**Precedente útil.** O `CrmCardConverter` da prospecção já cria empresa, contato e card numa transação por linha, com `external_id`. Ele chama a automação de entrada da etapa à parte (`crm_card_converter.rb:56-72,78-84`), porque o `Creator` não chama nenhuma (`crm_card_converter.rb:1-3`).

## 2. O que acontece com quem vira cliente

**Promoção** (`app/models/concerns/contact_customer.rb:12-20`)
- `become_customer!` grava `contact_type: :customer` e `customer_since = customer_since || agora`, com lock e sem validar o contato.
- Se o contato já é cliente, ele não muda nada (`:14`).
- Reabrir o card **não** desfaz a promoção. Só o botão manual desfaz (`release_customer!`, `customers_controller.rb:12`).

**Problemas de data**
- Um card criado já ganho grava a data de fechamento com a data de hoje (`card.rb:179`), e o "cliente desde" (`customer_since`) também sai com a data de hoje.
- Para guardar a data histórica da planilha, a importação teria que gravar `customer_since` e `closed_at` explicitamente.

**Visibilidade do contato importado**
- Com a flag `crm_v2`, a lista de contatos só mostra contatos `lead` e `customer` (`contact.rb:191-193`, `contacts_controller.rb:133`).
- O importador atual cria o contato sem tipo, então ele nasce **visitor** (`campaign_imports/importer.rb:80`, enum em `contact.rb:79`, padrão `visitor` em `contact.rb:10`).
- **Com crm_v2 ligado, o contato importado não aparece em Relacionamentos.** A Base de clientes precisa gravar `lead` ou `customer`, como o `ContactCreator` já faz com `lead` (`crm/cards/contact_creator.rb:21`).

**Aba Oportunidades** (`ContactManageView.vue:52-69`, `RelationshipOpportunities.vue`)
- Só aparece com `CRM_KANBAN_ENABLED`, permissão de CRM e a navegação nova.
- Mostra título, funil · etapa, situação, responsável e previsão. **Não mostra os campos próprios do card.**
- Endpoint: `config/routes.rb:256` → `crm/contact_opportunities_controller.rb`.

## 3. Campos do card e campos do contato

**Onde ficam as definições**
- Contato, empresa, conversa e card usam a mesma tabela `CustomAttributeDefinition`, separada pelo modelo do campo (`attribute_model`, em `custom_attribute_definition.rb:48`).
- A chave é única por conta **e por modelo** (`:40`). Logo, um campo de contato e um campo de card podem ter a mesma chave; o registro da IA separa os dois como `card:<chave>` (`attribute_extractor_applier.rb:168-171`).
- Existe `attribute_description` (`:6`). Os tipos disponíveis são texto, número, moeda, percentual, link, data, lista e caixa de marcar (`:49`).
- Algumas chaves são reservadas para card (`title`, `status`, `stage_id`...) e não podem virar campo próprio (`:31,105-112`).
- **As definições valem para a conta inteira, não por funil.** Todo campo de card aparece no esquema da IA de todo funil (`crm/ai/attribute_schema_builder.rb:26-32`).

**Como a IA preenche**
- `AttributeSchemaBuilder` manda nome, tipo, descrição e opções separados em contato, conversa e card (`attribute_schema_builder.rb:18-21,39-51`). O comentário em `:45-46` diz que a descrição é "o insumo mais forte da extração".
- O prompt (`ATTR_EXTRACTION`, em `crm/ai/classifier_prompt.rb:127-150`) define o contato como "dado da pessoa (vale para todos os pedidos dela)" e o card como "dado deste pedido". Ele proíbe mover uma chave de um grupo para outro.
- `AttributeExtractorApplier` grava dado de pessoa no contato, dado de conversa na conversa e dado de pedido no card (`:16-22`). No card, só grava se ele for o assunto atual (`:31-37`).

**Ponto crítico para a importação: a IA nunca sobrescreve campo preenchido.**
- Ela recusa com `already_filled` (`attribute_extractor_applier.rb:83,88-93`). Também exige confiança mínima de 0,6 (`:2,82`).
- Um valor importado prevalece para sempre sobre o que a IA ler na conversa, mesmo se estiver desatualizado.

**Não existe espelhamento card → contato.**
- "Dado de negócio também vai para o contato" exigiria duas definições, uma de contato e uma de card, e gravar nas duas.
- Depois disso, a IA preencheria cada uma por conta própria.
- Hoje a API do card aceita qualquer chave em `custom_attributes`, sem conferir se ela existe (`crm/cards_controller.rb:464,477,486-488`). Só a IA confere (`unknown_key`, `attribute_extractor_applier.rb:79`).

## 4. O que dispara ao criar card e contato em massa

### Ao criar card pelo `Creator`

| Efeito | Dispara? | Evidência |
|---|---|---|
| Registro de atividade `create` | Sim, um por card | `creator.rb:24`, `activity_logger.rb:13` |
| Webhook `crm.card.created` | Sim, se a conta tiver webhook inscrito | `crm/activity.rb:40,47-55` → `crm/webhooks/emitter.rb:18,51,75-79` → `webhook_listener.rb` (`crm_card_created` → `CrmDeliveryJob`) |
| Conversão Meta/Google (CAPI/offline) | **Não** ao criar, mesmo já ganho: o `Creator` registra só `create`, e esses envios ouvem só `won`/`lost`/`moved` | `emitter.rb:30-34`, `meta_capi_listener.rb:11-21`, `google_offline_listener.rb:2-10` |
| Automação de entrada da etapa | **Não** pelo `Creator` (só `Mover` e prospecção chamam) | `crm_card_converter.rb:2-3`, `mover.rb:58-68`, `stage_automations/runner.rb` |
| Atualização ao vivo do quadro | Não pelo `Creator` (quem chama é que faz) | `crm/cards/broadcaster.rb`, `cards_controller.rb:364`, `crm_card_converter.rb:32` |
| Promover o contato a cliente | Sim, se ganho em funil de venda | `card.rb:103` |
| Prazo de atendimento (SLA) | Não: o SLA aplicado sozinho é por **conversa**; o `sla_seconds` da etapa só aparece no quadro | `jobs/crm/sla_auto_apply_job.rb:4-16`, `kanban/board_payload_builder.rb:51` |

### Depois de criado, ainda aberto

- **IA paga em todo card parado, mesmo sem conversa.**
  - `StaleCardsJob` pega cards abertos com `last_activity_at` antigo (`jobs/crm/ai/stale_cards_job.rb:14-19`).
  - Card sem conversa conta sempre como "assunto atual" (`crm/cards/current_subject.rb:8-9`).
  - O `Evaluator` não para quando falta conversa: chama o classificador da IA (`crm/ai/evaluator.rb:12-29,56-75`).
  - O contexto, por sua vez, só devolve vazio (`context_builder.rb:74`).
  - Resultado: depois do tempo de "card parado" (`stale_hours`), cada card importado aberto gera **uma chamada paga**, com conversa vazia. Com movimento automático ligado no funil, a IA pode mover o card sem evidência.
  - Só não repete porque `last_evaluated_at >= last_activity_at` (`stale_cards_job.rb:30-37`).
  - Em 5 mil linhas, são 5 mil chamadas.
- **Follow-up automático: não dispara.** Exige conversa principal no WhatsApp e troca de pelo menos 2 mensagens de cada lado (`crm/follow_ups/auto_followup_planner.rb:50-61,74-78`).
- **Card duplicado quando o cliente escrever.**
  - O deduplicador só reaproveita o card aberto do contato se `inbox_id` e funil batem (`crm/conversations/auto_create_deduplicator.rb:32-44`).
  - Também exige que a última atividade caia na janela, 30 dias por padrão (`:3,42`).
  - Um card importado sem caixa (`inbox_id`) **não** é reaproveitado: nasce um segundo card (`card_syncer.rb:37-43,132-145`).
  - Se for reaproveitado, ele passa a ter conversa e a IA começa a avaliar e mover (`card_syncer.rb:49`).
- **Relatórios.** Ganhos e perdidos contam por data de fechamento no período (`reports/summary.rb:78-81`). Importar ganhos com a data de hoje infla a taxa de ganho e a receita do mês.

### Ao criar ou atualizar contato

- `after_create_commit` e `after_update_commit` disparam `contact.created` e `contact.updated` (`contact.rb:74-75,250-260`). Os ouvintes são:
  - webhook da conta (`webhook_listener.rb:54,60`);
  - tempo real (`action_cable_listener.rb:155,160`);
  - integrações (`hook_listener.rb:14-22`): a LeadSquared ouve `contact.updated` (`hook_listener.rb:66`).
- As regras de automação nativas não ouvem eventos de contato (`automation_rule_listener.rb`: só conversa e mensagem).
- **Já existe um jeito de silenciar esses eventos:** `CampaignImports::SuppressedContactEvents` (`campaign_imports/suppressed_contact_events.rb:6-12`), usado pelo `Importer`.
  - A promoção a cliente faz `save!` no contato, o que gera `contact.updated` (`contact_customer.rb:17`). Com a importação dentro desse bloco, a promoção também fica silenciada.
  - A consulta de localização por IP (`ip_lookup`) **não** é silenciada, mas só roda com a feature ligada (`contact.rb:213-217`).

## 5. Riscos, em ordem

1. **Contato importado invisível com crm_v2** (`importer.rb:80` + `contact.rb:193`). É preciso gravar `lead` ou `customer`.
2. **Uma chamada paga de IA por card aberto importado**, e possível movimento de etapa com conversa vazia (`stale_cards_job.rb:14-19` + `evaluator.rb:12-29`). O `Evaluator` não tem proteção para card sem conversa.
3. **Card duplicado quando o cliente escrever**, se o card importado não tiver caixa (`auto_create_deduplicator.rb:36-44`).
4. **Funil e relatórios poluídos.** Ganho importado entra no mês corrente (`card.rb:179`, `summary.rb:81`) e o "cliente desde" fica com a data de hoje (`contact_customer.rb:16`).
5. **Rajada de webhook** `crm.card.created` e `contact.*` para integrações externas, se não silenciar (`activity.rb:40`, `contact.rb:250-260`). O silenciador hoje cobre só contato, não o webhook de card.
6. **Valor importado trava a IA** naquele campo (`attribute_extractor_applier.rb:83`).
7. **Campo de card vale para a conta toda.** Campos criados pela importação entram no esquema da IA de todos os funis (`attribute_schema_builder.rb:26-32`). Sem descrição, a IA "adivinha pelo nome da chave" (`:45-46`).
8. **O plano está à frente do código.** O `PLANO.md` (R15, seção 4) fala em `promotes_contact` e `kind` no funil. O código tem `counts_as_sale`, e todo ganho em funil de venda promove o contato, sem opção (`crm/pipeline.rb:6`, `card.rb:103`).

**Caminho mais seguro, deduzido do código:** marcar o contato como cliente direto, com `customer_since` vindo da planilha e os eventos silenciados, sem criar card. Criar card só quando a pessoa escolher explicitamente o funil e a etapa. Nesse caso:
- gravar com `external_id` e `inbox_id`;
- sinalizar no `metadata` que veio da importação, para a IA e o `StaleCardsJob` pularem esses cards (isso não existe hoje e exigiria mudança de código);
- não chamar o `Runner` de automação.


## codigo: design-system

Levantamento da casa (só leitura). A worktree está em `d987e9dce9`, que descende de `3db6d348c2`. O `git diff --stat` entre os dois veio vazio, então o código é o mesmo do pedido. Todos os caminhos abaixo são relativos a `/Users/rodrigosilva/dev/worktrees/chat2you/relacionamentos-pesquisa`.

## 1. Já existe um guia visual da casa: começar por ele

`docs/guia-operante/GUIA-VISUAL.md` (03/10/2026) já reúne o padrão "premium no visual, simples no uso". Ele traz telas de referência (:15-21), superfícies, raios e sombra (:44-60), cor (:62-75), estados obrigatórios (:103-119), controles (:121-136), anti-padrões (:167-178) e um checklist de PR (:245-254). A remontagem de Relacionamentos deve partir dele, com as correções da seção 5.

## 2. Componentes prontos para reaproveitar

**Base do produto (components-next)**
- **Button**: `components-next/button/Button.vue`.
  - Variantes, cores e tamanhos em `button/constants.js:1-3`.
  - Alturas em Button.vue:159-162: xs h-6, sm h-8, md h-10, lg h-12. O md tem 40 px, então precisa de `min-h-11` (GUIA-VISUAL:125).
  - O primário é `bg-n-brand text-white` (:104).
- **ChoiceSelect**: `components-next/choice-select/ChoiceSelect.vue`. Substitui o `<select>`, com teclado WAI-ARIA, opção de 44 px (:58), grupos (:23), `compact` para filtros (:41) e `triggerId` para o rótulo (:43). Já é usado em Relacionamentos (`Relationships/ContactViewSelect.vue:60`, `AttributeDraftFields.vue:56`) e na importação (`ContactImport/ContactImportColumns.vue:98`).
- **Dialog**: `components-next/dialog/Dialog.vue`. É o `<dialog>` nativo, com `type alert|edit` (:10-14), `width sm…3xl` (:51-55) e `isLoading`/`disableConfirmButton`.
- **SidePanel**: `components-next/side-panel/SidePanel.vue`, com header, corpo rolável e footer (:121-155). Dois limites:
  - O botão de fechar é `sm`, ou seja, 32 px (:137-144).
  - Ele não prende o Tab (registrado na memória de regras de UX).
- **Gaveta com foco preso** (preferível ao SidePanel): `routes/dashboard/autonomia/agentes/components/AgenteGaveta.vue`. Usa `useModalFocus` (:36-40), vira folha de baixo no celular (:57), fechar com 44 px (:71) e rodapé em slot (:82-87). A base é `components-next/CampaignJourney/useModalFocus.js:1-20`.
- **Tabela**: `components-next/table/BaseTable.vue`, crua (`text-heading-3 capitalize` no th). Não é referência premium.
- **EmptyStateLayout**: `components-next/EmptyStateLayout.vue` é o padrão herdado do Chatwoot (h2 `text-3xl`, fundo esmaecido). Não segue a regra "1 frase + 1 botão". O vazio de referência é o de Automações (seção 3).
- **CardLayout**: `components-next/CardLayout.vue`, cartão neutro `rounded-xl bg-n-solid-2`.
- **Outros**:
  - Switch (`components-next/switch/Switch.vue`), sempre dentro de um label de 44 px com o texto do estado (`AutomacaoLinha.vue:116-144`).
  - Label, Banner, Spinner, Icon e TeleportWithDirection (lista em GUIA-VISUAL:160-165).

**Peças de jornada já feitas (copiar o padrão; DECISOES item 10 proíbe editar componente compartilhado)**
- **Etapas sem navegação**:
  - `automacoes/components/AutomacaoEtapas.vue:12-65`: Conte → Confira → Ligue, com `aria-current="step"` e visto na etapa feita.
  - `autonomia/agentes/components/AgentesEtapas.vue:19-90`: Conte · Confira · Comece. No celular vira "Etapa N de 3 · Nome" (:32-38) e o nome fica em slate-12 por contraste (:5-8).
- **Etapas navegáveis** (volta ao passo já feito): `components-next/CampaignJourney/JourneyStepper.vue:18-110`, com setas, Home e End.
- **Revisão com "Alterar" por bloco**: `components-next/CampaignJourney/StepReview.vue:105-133`, com aria-label "Alterar {bloco}" e número final num bloco navy (:188-193).
- **Prévia como o cliente vê**: `automacoes/components/AutomacaoResumo.vue:203-216`, um balão com nome de exemplo.
- **Ensaio "veja o que teria acontecido"**: `automacoes/components/AutomacaoEnsaio.vue:11-14, 120-178`. Não grava nada e anuncia o resultado por `role="status"`.
- **Modelos prontos em cartão-botão**: `automacoes/components/AutomacaoModelos.vue:14-72`, com grade `auto-fit minmax(18rem)`. Na versão de Agentes, o modelo vem com a conversa de exemplo num celular (`agentes/components/ModeloCartao.vue:44-90`, `CelularConversa.vue`).
- **Cartão-frase da lista**: `automacoes/components/AutomacaoLinha.vue:50-146`. Mostra ícone por tipo, frase "Quando → Faz" em pílulas, botão "Alterar" explícito (:104-115) e o interruptor com o texto do estado.
- **Rádio em cartões** (bom para "isto é da pessoa, da empresa ou do negócio?"): `agentes/components/EscolhaRadio.vue:4-90`, com role=radio, setas e opção desabilitada que mostra o motivo.
- **Botão com contraste AA**: `agentes/components/AgenteBotao.vue:42-62`. Primário `bg-n-blue-11`, variantes contorno, fantasma, perigo, aviso e branco, tamanhos md/lg/xl com mínimo de 44 px.
- **Erro padrão**: `agentes/components/AgenteErro.vue:4-53`. Diz o que houve, o que continua igual e oferece uma saída só.
- **Confirmação**: `agentes/components/AgenteConfirmacao.vue`, com Cancelar primeiro e principal de perigo.
- **Trilha e foco**: `components-next/onboarding/FirstSteps.vue:110-180` (anel de progresso), `FirstStepsFocus.vue:7-8` ("uma coisa de cada vez, com um único botão forte") e `FirstStepsTrail.vue:4-5`.
- **Letra maior para leigo**: `centralDeAjuda/composables/useTamanhoDaLetra.js:4-14`. São três tamanhos, o padrão é o do meio ("grande") e a escolha fica salva no perfil.

**Relacionamentos hoje (o que já existe para encaixar)**
- `routes/dashboard/relationships/RelationshipsHome.vue:72-178`: três cartões (Contatos, Empresas, Atributos) com ação sólida e uma dica em azul. Rotas em `relationships/routes.js`.
- Campos na ficha:
  - `components-next/Relationships/RelationshipFields.vue:26-66`, cujo vazio é tracejado (:55-65).
  - `FieldEditor.vue:29-40`: ícone por tipo (texto, número, moeda, %, data, link, lista, checkbox).
  - `FieldConfigurator.vue`: Dialog `width="xl"` (:304-315). **A descrição já é obrigatória ao criar** (:143; contrato em `docs/relationships/attributes-and-visibility.md:30`). Isso atende o "nome + descrição" de que a IA do CRM precisa.
- Superfícies onde o campo aparece: `contact_sidebar`, `contact_details` e `company_details` (`attributes-and-visibility.md:16-21`; `FieldConfigurator.vue:42-47`).
- Abas próprias com 44 px: `Relationships/RelationshipTabs.vue:33-59`.
- Migalha: `RelationshipBreadcrumb.vue`.
- Somente leitura: `RecordReadOnly.vue`.
- Importação atual: `routes/dashboard/contacts/import/ContactImportPage.vue`.
  - Etapas upload → lendo → revisão → resultado (:2-4, :249-330). A tela nunca nomeia o motor que lê as colunas (:4).
  - Zona de soltar arquivo (:262-278).
  - Aviso âmbar "Diga qual coluna tem cada informação" (:320-329).
  - Colunas com "Trocar" via ChoiceSelect: `ContactImport/ContactImportColumns.vue:3-4`.
  - A leitura nova fica atrás da flag `customer_base`: `app/services/campaign_imports/contact_reading.rb:2,12`.

## 3. O que define o "premium" da casa (padrões visuais)

1. **Herói navy**, um por tela: `bg-[#0D2344]`, `rounded-3xl`, dois anéis decorativos `border-n-blue-9/7` com `opacity-10/15`.
   - Título `text-3xl md:text-[2.5rem] font-bold tracking-tight` e texto `text-white/75` (`AutomacaoHeroi.vue:106-131`).
   - Dentro, um cartão branco `rounded-2xl shadow-2xl` com campo e CTA `min-h-12 rounded-xl` (:133-241).
   - Chips de ideia `bg-white/10 ring-white/20` (:249-259).
   - Agentes adiciona `dark:bg-[#12305E]` (`AgentesHeroi.vue:20`, `PaginaHeroi.vue:45`). Automações não tem essa variante escura.
2. **Página**: `bg-n-surface-1`, `max-w-6xl`, `gap-8`, `px-5 py-8 md:px-8 md:py-10` (`AutomacoesPage.vue:116-119`). Título de lista `text-3xl md:text-4xl font-bold` com um único CTA `size="lg" !min-h-12 !rounded-xl` (:201-220).
3. **Cartões**:
   - Cartão-botão `rounded-2xl ring-1 ring-n-weak bg-n-solid-1 shadow-sm`.
   - No hover, `-translate-y-0.5 shadow-lg ring-n-blue-7` (`AutomacaoModelos.vue:22`).
   - Ícone em bloco de `size-14 rounded-2xl` com cor semântica (`bg-n-*-3 text-n-*-11`).
   - Seção de leitura `rounded-3xl border shadow-md p-6` (`AutomacaoResumo.vue:77`).
4. **Contagens em pílula**: ponto colorido mais frase (`AutomacoesPage.vue:223-250`). Números grandes `text-4xl font-bold tabular-nums text-n-teal-11` (`AutomacaoEnsaio.vue:159`).
5. **Quatro estados com ramos nomeados**:
   - carregando: esqueleto `animate-pulse` mais `aria-busy` (`AutomacoesPage.vue:121-134`);
   - erro: ícone, frase e "Tentar de novo" (:136-158);
   - vazio que ensina: herói mais modelos (:160-198);
   - cheio.
6. **Cores com sentido**:
   - azul: quando/seleção; violeta/iris: condição ou selo "feito pelo Guia"; teal: faz/ligado/feito; âmbar: desligado/aviso; rubi: erro (`AutomacaoResumo.vue:40-71`, `AutomacaoLinha.vue:20-41`).
   - Tokens em `theme/colors.js:107-276`: `brand #2781F6` (:229), `surface`, `solid`, `weak`, `strong`, `card`.
   - Valores claro e escuro em `app/javascript/dashboard/assets/scss/_next-colors.scss:111-133` e `:263-284`.
7. **Tipografia e ícones**:
   - Fonte do sistema (`tailwind.config.js:10-20, 44-48`), com Inter disponível.
   - Ícones Lucide `i-lucide-*` sempre com `aria-hidden` (`tailwind.config.js:272-284`).
   - Animações prontas: `fade-in-up`, `card-select`, `shake` (:262-269).
8. **Acessibilidade como parte do acabamento**: alvo ≥ 44 px, `focus-visible:outline-2 outline-n-brand` e `aria-live` no que muda (GUIA-VISUAL:149-156).

## 4. Regras de texto (com exemplos reais aprovados)

- **Frase de pessoa, curta, com verbo.** O herói pergunta "O que você quer que aconteça sozinho?" e completa com "Escreva como se falasse com um colega… só liga quando você mandar." (`pt_BR/crm.json` → `AUTOMACOES.HEROI`).
- **Erro diz o que fazer**: "Não consegui carregar suas automações. Confira a internet e tente de novo." (`AUTOMACOES.LISTA.ERRO`).
- **Prévia com garantia**: "Confira antes de importar. Nada entra nos seus contatos até você importar." (`pt_BR/contactImportJourney.json` → `REVIEW_SUBTITLE`). O ensaio diz "Nada é enviado nem alterado." (`AUTOMACOES.ENSAIO.EXPLICA`).
- **Botões com verbo**: "Alterar", "Tentar de novo", "Testar com casos reais", "Usar este".
- **Vocabulário fechado de estado**, sem "Ligar" em Agentes (`docs/agentes-fase1/DECISOES.md:37-38`). A linguagem é neutra em gênero.
- **Sem nomear a tecnologia**: `ContactImportPage.vue:4`. Em Automações o assistente aparece como "Guia", a persona, nunca "IA".
- **Checklist de texto** em GUIA-VISUAL:145-147: nada em inglês e nenhuma palavra de sistema (evento, payload, webhook, job). Datas com `Intl` e `replaceAll('_','-')`.
- **Textos genéricos** (servem Hub2You e Autonomia) e **sem caixa alta**: memória `regras-ux-telas-leigo.md`.

## 5. Conflitos e lacunas encontrados (decidir antes do layout)

1. **Caixa alta.** A regra do Rodrigo proíbe, mas as referências usam `uppercase`:
   - `AutomacaoHeroi.vue:120`, `AutomacaoResumo.vue:108,134`, `AutomacaoModelos.vue:55`, `StepReview.vue:117`;
   - o próprio GUIA-VISUAL:89 prescreve `uppercase`.
   - Agentes, a referência mais nova, tem zero `uppercase`. **Seguir Agentes.**
2. **Contraste do primário.** `Button.vue:104` e o CTA de `RelationshipsHome.vue:148` usam `bg-n-brand` (#2781F6) com texto branco. Pela minha conta, isso dá cerca de 3,8:1, abaixo do AA para texto de 14 px. `AgenteBotao.vue:5-7` registra o mesmo problema e usa `bg-n-blue-11`.
3. **Herói sem tema escuro.** `#0D2344` está fixo em cerca de 20 arquivos. Só Agentes tem a variante `dark:`.
4. **Botões de 32 px em Relacionamentos.** `FieldConfigurator.vue:276-303` usa sm/xs sem `min-h-11`. O fechar do SidePanel também tem 32 px (`SidePanel.vue:137-144`).
5. **Texto atual de Relacionamentos fere a regra de leigo.** Exemplos de `pt_BR/relationships.json:3-12, 105-140, 163-165`:
   - "Centralize e organize… para fortalecer seus relacionamentos";
   - "Gerencie suas pessoas";
   - "Entidade: {name}";
   - "Local de exibição";
   - "A seleção de exibição não apaga os dados…";
   - mistura de "atributo" e "campo" ("Configurar campos" ao lado de "Criar atributo").
6. **Guia desatualizado sobre atributos.**
   - `porques.md:994-1002` diz que criar exige administrador, lista só seis tipos, manda "use regex" e aponta Configurações. O real é `attribute_manage`, sem regex no editor novo (`attributes-and-visibility.md:55-57`), e a entrada fica em Relacionamentos.
   - `porques.md:198` diz que "atributos novos são criados como texto". O `docs/base-de-clientes/PRD.md:32` fala em valores tipados. **A conferir no código.**
7. **Blocos do Guia que a remontagem vai precisar reescrever** (`lib/operator_guide/porques.md`):
   - `abrir_relacionamentos` (:2102-2109), `ficha_do_contato` (:1913-1922), `lista_de_empresas` (:1924-1932), `ficha_da_empresa` (:1952-1960);
   - `importar_contatos_com_colunas_e_empresas` (:191-198), `importar_contatos_por_csv` (:182-189), `marcar_contato_como_cliente` (:431-438);
   - oportunidades na ficha (:413-429, :1943-1950), `consultar_cadastro_sem_permissao_de_edicao` (:1934-1941), `consultar_midias_da_empresa` (:2111-2118).
   - Mudar rota ou permissão exige rodar `pnpm guia:build`, e tela nova sem bloco não passa no PR (CLAUDE.md do projeto).
8. **Documentos que já restringem a Base de clientes:**
   - `docs/base-de-clientes/PRD.md`: decisões D1-D4 (:46-53), F1 com tipo do contato, consentimento, pergunta em coluna ambígua, prévia com exemplos e desfazer (:80-116), riscos (:121-148).
   - `docs/relationships/visual-contract.md:15-25` e as exceções (:27-29): não inventar métricas nem promessas de IA.

## Arquivos principais

`docs/guia-operante/GUIA-VISUAL.md`, `docs/base-de-clientes/PRD.md`, `docs/relationships/visual-contract.md`, `docs/relationships/attributes-and-visibility.md`, `docs/agentes-fase1/DECISOES.md`, `app/javascript/dashboard/routes/dashboard/automacoes/`, `app/javascript/dashboard/routes/dashboard/autonomia/agentes/components/`, `app/javascript/dashboard/components-next/{CampaignJourney,Relationships,ContactImport,choice-select,dialog,side-panel,button,onboarding}/`, `app/javascript/dashboard/routes/dashboard/relationships/RelationshipsHome.vue`, `app/javascript/dashboard/routes/dashboard/contacts/import/ContactImportPage.vue`, `lib/operator_guide/porques.md`, `tailwind.config.js`, `theme/colors.js`.


## codigo: dados-reais

# Base de clientes depois da importação: o que o código em produção já faz

**Commit lido:** o HEAD da worktree é `d987e9dce9`, não `3db6d348c2`. Rodei `git diff 3db6d348c2 HEAD` e não houve diferença em arquivo nenhum, então o código é o mesmo. Nenhuma linha foi alterada.

**Resumo:** quase tudo para trabalhar a base já existe no backend. O que falta são três coisas:
- uma lista que mostre os dados da base;
- ações que cubram a base inteira, e não só a página aberta;
- uma ponte entre um segmento e uma campanha, um card ou um agente.

## 1. Ver

**O que já serve**
- **Lista de contatos:** busca por nome, e-mail, telefone e identificador (`contacts_controller.rb:124-127`). A ordem pode ser por nome, e-mail, telefone, atividade, criação, empresa, cidade ou país (`:3-10`).
- **Visões prontas:** Todos, Ativos agora, cada segmento e cada etiqueta, num seletor sem `<select>` nativo (`ContactViewSelect.vue:15-38,60`). Esse seletor só aparece com a flag `relationships_navigation` ligada.
- **Painel de resumo:** total, novos, ativos e com empresa, sempre nos últimos 30 dias (`relationships/summary.rb:3-8`, `RelationshipSummary.vue:21-42`).
- **Página do contato:** abas Oportunidades, Atributos, Histórico, Notas, Mídia e Mesclar (`ContactManageView.vue:75-100`).
  - Os campos personalizados aparecem na aba Atributos (`ContactCustomAttributes`). O `FieldEditor.vue:263,287` já mostra a descrição de cada campo.
  - "Lead ou cliente" aparece com a data, e pode ser marcado ou desfeito (`ContactCustomerSection.vue:30-37`).
  - A recusa de mensagens aparece com data e origem (`ContactOptOutSection.vue:33-60`).

**O que falta**
- **A lista é de cartões, não de colunas.** Cada contato mostra só nome, e-mail, telefone e `additionalAttributes.companyName` (`ContactsList.vue:91-109`, `ContactsCard.vue:156-163`).
  - Não mostra campo personalizado, etiqueta, lead/cliente, recusa, funil ou etapa.
  - O nome da empresa vem de `additional_attributes`, não da empresa ligada (`company_id`).
- **15 contatos por página** (`contacts_controller.rb:12`). Para trabalhar uma base grande, isso é pouco.
- **O "Histórico" é só a lista de conversas** (`ContactHistory.vue:13-27,41-48`). Não aparecem campanha recebida, mudança de etapa, importação de origem, recusa nem quando virou cliente.
- **Não existe relatório de contatos.** Em `settings/reports/` há agentes, caixas de entrada, etiquetas, equipes, SLA, CSAT e bot, nada de contatos. O resumo não conta leads, clientes nem quem recusou (`summary.rb:4-8`).
- **Empresas:** só busca e ordenação (`enterprise/.../companies_controller.rb:3-7,25`), 25 por página (`:9`).
  - Não há filtro, segmento, exportação nem ação em massa.
  - A rota só existe em instalações Cloud ou Enterprise (`companies/routes.js:20`).

## 2. Segmentar

**O que já serve**
- **Filtros avançados:** nome, e-mail, telefone, identificador, país, cidade, empresa (texto), criado em, última atividade, bloqueado e etiquetas (`contactProvider.js:77-200`, `filter_keys.yml:138+`).
- **Os campos personalizados do contato também viram filtro** (`contactProvider.js:53,66-75`, `filter_service.rb:64,88-89`).
- **Segmento salvo:** filtro com nome, que pode ser criado, editado e apagado (`ContactListHeaderWrapper.vue:167-241`).

**O que falta**
- **Faltam filtros importantes:**
  - lead ou cliente: `contact_type` existe (`contact.rb:79`), mas não está em `filter_keys.yml` nem em `contactProvider.js`;
  - recusou mensagens: `opted_out_at`;
  - "cliente desde": `customer_since`;
  - empresa ligada e campos da empresa;
  - funil, etapa ou valor do card;
  - recebeu ou respondeu tal campanha;
  - número de conversas;
  - importação de origem.
- **O segmento é de uma pessoa só.** `CustomFilter belongs_to :user`, a lista é filtrada por `user: Current.user` (`custom_filter.rb:20`, `custom_filters_controller.rb:30-31`), e há limite de segmentos por usuário (`:30`). A equipe não compartilha a mesma segmentação.
- **O construtor de filtro é técnico:** campo, operador, valor e E/OU. Para o padrão QI 70 seriam melhores segmentos prontos ("Clientes", "Leads", "Sem conversa há 60 dias", "Recusaram mensagens").

## 3. Agir

**Ações em massa**
- **Hoje existem só três:** pôr etiqueta, tirar etiqueta e apagar (`bulk_action_service.rb:8-15`, `ContactsBulkActionBar.vue:25-31`).
- **"Selecionar todos" pega só a página visível,** ou seja, 15 contatos (`ContactsIndex.vue:163-171`). Não existe "selecionar os 3.200 deste filtro".
- **Ações que não existem em massa:**
  - marcar como cliente ou lead;
  - marcar ou desfazer recusa;
  - ligar a uma empresa;
  - preencher um campo;
  - criar card no funil;
  - enviar para campanha;
  - entregar a um agente de IA.

**Campanha**
- **O público de campanha nasce só de planilha.** O passo "Quem vai receber" oferece só públicos salvos (`StepAudience.vue:3`).
- **Público é uma importação.** `CampaignImport` usa `flow: 'audience'` (`campaign_import.rb:64,118`) e a campanha se liga a ele por `CampaignAudienceLink` (`campaign_audience_link.rb:26-35`).
- **Quem recebe vem das linhas da planilha.** Só recebe o contato de uma linha que tinha celular ou e-mail válido, e cujo dado ainda é o mesmo (`campaign_journey/audience_contacts.rb:7-17,29-40`).
- **Consequência:** um segmento ou filtro da base não vira público. Também não achei serviço que crie público a partir de contatos existentes; procurei em `services/campaign_imports/` e nos controllers de campanha.
- **O caminho antigo do Chatwoot ainda existe no backend:** campanha por etiqueta (`whatsapp/oneoff_campaign_service.rb:52-54,79`). Na interface nova, o atalho de importar para campanha some quando `campaignJourneyEnabled` está ligado (`ContactListHeaderWrapper.vue:314-316`).
- **Importar contatos não vira público.** O `flow: 'contacts'` nunca aparece em Públicos nem em campanha (`campaign_import.rb:65-67`).
- **Não confirmei** se a tela nova de campanha ainda oferece etiqueta como público.

**Card do CRM**
- **A aba Oportunidades só lista e busca cards** (`RelationshipOpportunities.vue:97-175`). Os botões são atualizar, buscar e tentar de novo; não há criar.
- **Não há criar card nem em massa,** nem a partir de um segmento.

**Agente de IA**
- **Não há ação no contato nem na lista** que ligue o contato ou um segmento a um agente. Na página do contato as ações são enviar mensagem, ligar e bloquear (`ContactDetailActions.vue:15,47,55,65`).

**Exportação** (`Account::ContactsExportJob`)
- **O que funciona:** respeita o filtro, o segmento e a etiqueta atuais (`ContactExportDialog.vue:29-41`, `contacts_export_job.rb:59-68`). O arquivo sai com BOM UTF-8 e o link chega por e-mail (`:85-98`).
- **Exporta só colunas da tabela `contacts` e etiquetas** (`:70-77`). A tela não manda escolha de colunas, então saem sempre `id name email phone_number labels` (`:104-106`).
- **Ficam de fora:**
  - campos personalizados (só sairiam como o JSON bruto de `custom_attributes`, se alguém pedisse essa coluna);
  - empresa ligada;
  - lead/cliente com data;
  - recusa;
  - card e etapa.

## 4. LGPD e consentimento

**O que já serve**
- **Recusa de mensagens por contato, com três origens possíveis:** `prospecting`, `email_unsubscribe` e `manual` (`contact_opt_out.rb:19`). Grava quem marcou (`opted_out_by`) e quando (`:43`).
- **A recusa passa para o contato novo** que tenha o mesmo telefone ou e-mail (`:97-107`). Na mescla, vale a origem mais firme (`contact_merge_action.rb:5`).
- **Os envios respeitam a recusa:**
  - WhatsApp: `oneoff_campaign_service.rb:44-59`, e no EE marca o destinatário como pulado (`enterprise/.../oneoff_campaign_service.rb:17`);
  - SMS: `twilio/oneoff_sms_campaign_service.rb:23`;
  - Públicos: `audience_contacts.rb:40`;
  - prévia de quem não recebe: `audience_reachability.rb:3-8`;
  - follow-ups do CRM: `crm/follow_ups/*`.

**O que falta**
- **Não existe registro de consentimento (opt-in).** Não há base legal, origem do dado, data nem prova. A tabela `contacts` só tem as colunas de recusa (`db/schema.rb:1711-1714`). No modelo de contato, a palavra consent só aparece na Prospecção (`autonomia/prospecting/lead.rb`).
- **A trilha de recusa vai para o log, não para uma tabela** (`contact_opt_out.rb:109-111`).
- **Não há filtro, contagem nem ação em massa de recusa.**
- **Não há exportação dos dados de um contato** para atender um pedido do titular. Existe apenas apagar.

## 5. Duplicados e mesclagem

**O que já serve**
- **Mescla manual na aba Mesclar.** Move conversas, mensagens, caixas de entrada, notas, ligações, leads da Prospecção, cards, follow-ups, convites e reuniões do CRM (`contact_merge_action.rb:13-22,60-110`). Mescla atributos e campos personalizados (`:111`) e herda cliente e recusa.
- **A importação aproveita o contato que já existe** (`campaign_imports/contact_matcher.rb`, `existing_contacts_count`).

**O que falta**
- **Não há tela que encontre duplicados.** A mescla é um contato por vez e você tem que buscar o outro.
- **A mescla manual não leva etiquetas nem os vínculos de campanha.** Quem leva é o `NinthDigitDuplicateMerger`, que repõe `CampaignImportRow`, `CampaignRecipient`, `EmailCampaignRecipient` e `WhatsappApiCampaignRecipient` e soma as etiquetas (`ninth_digit_duplicate_merger.rb:5-8,19-20`).
  - Esse caminho trata só o 9º dígito brasileiro e roda por rake (`lib/tasks/contacts_ninth_digit.rake`).
  - Como os públicos dependem de etiqueta (`:7`), a mescla manual pode perder vínculos de campanha.

## O que já serve e o que falta, por tema

| Tema | Já existe | Falta para a Base de clientes |
|---|---|---|
| Ver | busca, ordem, resumo 30d, página do contato com campos | colunas configuráveis, status no cartão, histórico de eventos, relatório |
| Segmentar | filtro com campos personalizados, segmento salvo | filtros de lead/cliente, recusa, empresa, card/etapa e campanha; segmento da equipe; segmentos prontos |
| Agir | etiqueta, apagar (só a página visível) | selecionar o filtro inteiro; segmento vira público; criar cards em massa; entregar a agente; marcar cliente ou recusa em massa |
| Exportar | CSV respeitando o filtro | campos personalizados, empresa, status, card |
| LGPD | recusa com origem e herança | registro de consentimento, trilha numa tabela, exportação para o titular |
| Duplicados | mescla manual, mescla do 9º dígito | tela de duplicados, mescla manual que leve etiquetas e campanhas |
| Empresas | busca, ordem | filtro, segmento, exportação, ações em massa |

Todos os arquivos estão em `/Users/rodrigosilva/dev/worktrees/chat2you/relacionamentos-pesquisa/`.


## mercado: incumbentes

# Pesquisa de mercado: como HubSpot, Salesforce, Pipedrive, Zoho, Dynamics e Freshsales tratam base de clientes, pessoa, empresa, negócio e importação

**Escopo:** pesquisa web nas centrais de ajuda oficiais. Uso fontes de terceiros só quando a oficial não abriu ou não respondeu, e isso vem marcado. Uma lacuna: a página oficial do Salesforce Help sobre o Data Import Wizard não carregou (deu erro de CSS), por isso usei o SalesforceBen e outras páginas oficiais relacionadas.

---

## 1. HubSpot (referência mais completa)

**Jornada de importação, objeto único (cerca de 4 blocos e 14 passos):**
1. Data Management > Data Integration > Import data > "Advanced imports".
2. Escolher o objeto.
3. Escolher o modo: "Create and update", "Create new only" ou "Update existing only".
4. Enviar o arquivo ou colar dados de planilha, e escolher o idioma dos cabeçalhos.
5. Definir o identificador único e mapear as colunas.
6. Dar nome à importação, marcar consentimento e opções (segmento, base legal, contato de marketing, formato de data e número).
7. "Finish import".

Fonte: https://knowledge.hubspot.com/import-and-export/import-records-for-a-single-object

**Vários objetos (pessoa, empresa e negócio juntos):**
- "Advanced imports (all objects)" tem dois formatos:
  - **Single file:** cada linha mistura contato, empresa e negócio.
  - **Multiple files:** um arquivo por objeto, ligados por uma coluna em comum, como "Company name".
- Na tela de mapeamento, a coluna "HubSpot Property" mostra a qual objeto cada coluna vai, e a associação entre os objetos é criada sozinha.
- Em arquivo único sem identificador, linhas com dados idênticos viram um registro só, ligado a vários relacionados.
- "Association labels" (o papel da relação) exigem plano Pro ou Enterprise.

Fonte: https://knowledge.hubspot.com/import-and-export/import-objects

**Deduplicação:**
- O Record ID tem prioridade sobre qualquer outro identificador.
- Email identifica contato e Company Domain Name identifica empresa, ambos marcados com ícone de chave.
- Uma propriedade própria com valores únicos também pode ser identificador.
- Negócio não tem identificador natural. O HubSpot recomenda Record ID.
- A opção "Don't overwrite" protege valores que já existem.
- Erros são corrigidos dentro do próprio assistente, em "[x] errors" > "Edit errored values".

Fontes: as duas URLs acima.

**Criar campo durante a importação:**
- Sim: "Create new property" no menu da coluna abre um painel lateral. Não vale para atividades.
- Colunas não mapeadas travam o avanço. A pessoa precisa marcar "Don't import column" em cada uma ou "Don't import data in unmapped columns" para todas de uma vez.

Fonte: https://knowledge.hubspot.com/import-and-export/import-records-for-a-single-object

**Criar propriedade (campo):**
- O básico é Label e Field type.
- "Edit more options" abre as abas Details, Field type, **Documentation**, Rules, Sensitive Data, Manage access e Preview. Documentation é um contexto descritivo opcional que explica como preencher o campo.
- Mudar o tipo depois pode invalidar dados já gravados.

Fonte: https://knowledge.hubspot.com/properties/create-and-edit-properties

**Campo preenchido por IA ("smart property"):**
- A pessoa clica em "Create new property" > "Create with Data Agent" e escreve em linguagem natural o que precisa.
- O agente gera o nome, o tipo, o prompt e a fonte de dados, e a pessoa revisa e pode editar cada parte.
- Consome créditos mesmo quando o campo não é preenchido.
- Também dá para transformar uma propriedade existente em smart property.

Fontes: https://knowledge.hubspot.com/properties/create-smart-properties e https://knowledge.hubspot.com/workflows/use-ai-to-manage-data-in-workflows

Não achei documentação dizendo que a IA lê a "descrição" de uma propriedade comum. O HubSpot usa um **prompt separado** na smart property. Isso é diferente do nosso modelo, em que nome e descrição servem às duas coisas.

**Ficha do cliente (record page), em 3 colunas:**
- **Esquerda:** destaques (nome, e-mail), ações rápidas e "Key information".
- **Meio:** abas About (com resumo de IA), Activities (linha do tempo com filtros), Catch-up, Revenue e Intelligence.
- **Direita:** cartões de associações (empresa principal, negócios, tickets) e anexos.
- Edição no próprio lugar: passar o mouse, clicar no ícone e "Save".
- "View all properties" só lista os campos agrupados. "View property history" mostra quem mudou cada valor.
- O layout é configurável em Settings > Customize records.

Fonte: https://knowledge.hubspot.com/records/work-with-records

**Complexo demais para um leigo:**
- Escolher entre "Create and update", "Create new only" e "Update existing only".
- O conceito de Record ID e identificador único.
- Association labels.
- Base legal e consentimento.
- Escolher entre arquivo único e vários arquivos.
- Ter que decidir o destino de cada coluna não mapeada antes de avançar.
- Cinco a sete abas para criar um campo.
- Coluna do meio com cinco abas.

---

## 2. Salesforce (Data Import Wizard)

**Passos:**
1. Escolher o objeto e a operação (inserir, atualizar ou upsert).
2. Enviar o arquivo. Aceita só CSV, não aceita Excel.
3. Mapeamento automático, com ajuste manual.
4. Confirmar, vendo quantos campos foram e não foram mapeados.
5. Acompanhar em Setup > Bulk Data Load Jobs.

Fonte: https://www.salesforceben.com/introduction-to-the-data-import-wizard-for-salesforce/ (terceiro)

**Objetos suportados:**
- Contas e contatos (importados juntos em "Accounts and Contacts"), leads, campaign members, person accounts e objetos personalizados.
- **Não importa Opportunities** (o negócio), nem Cases, Products, Campaigns ou Contracts. Para esses, o caminho é o Data Loader ou a API.

Fontes: mesma URL acima e https://salesforcebreak.com/2026/03/19/data-import-wizard-data-loader-guide/

**Limites:** 50.000 registros e 90 campos por arquivo.

**Deduplicação (matching):**
- Contato por nome ou e-mail. Conta por "Account Name + Account Site". Atualização por Salesforce ID, que diferencia maiúsculas de minúsculas.
- Ignora maiúsculas e pontuação ("IBM" = "I.B.M."), mas não abreviações ("HP" ≠ "Hewlett Packard").
- Relato de comunidade: com o campo Site vazio, contas de mesmo nome foram fundidas sem querer.
- Por padrão o assistente só preenche campos vazios. Sobrescrever exige marcar "Overwrite existing account values", e nem assim um valor em branco apaga um preenchido.

Fontes: https://help.salesforce.com/s/articleView?id=for_accounts_and_contacts.htm&language=en_US&type=5 e https://help.salesforce.com/s/articleView?id=campaigns_import_contacts_new.htm&language=en_US&type=5

**Criar campo:** não achei fonte que confirme criação de campo dentro do assistente. Os campos vêm do Setup (Object Manager).

**Complexo demais para um leigo:**
- A operação pela palavra "upsert".
- O assistente fica escondido no Setup.
- Só CSV.
- Opportunity fora do assistente.
- Conceito de "Account Site".
- IDs que diferenciam maiúsculas de minúsculas.
- Acompanhar a importação numa fila de jobs técnica.

---

## 3. Pipedrive (o mais próximo do nosso público de pequenas empresas)

**Preparação do arquivo:**
- XLS, XLSX ou CSV, uma aba, com linha de cabeçalho, até 200 mil linhas e 50 MB.
- A regra da linha: "os dados de uma mesma linha são vinculados entre si". Pessoa, organização e negócio na mesma linha ficam ligados.
- Pessoa exige nome. Organização exige nome. Negócio e lead precisam estar ligados a uma pessoa ou organização.

**Jornada:**
1. Ferramentas > Importar dados > Importar de planilha.
2. Marcar quais tipos o arquivo tem (pessoas, organizações, negócios, leads).
3. Mapeamento automático pelo nome da coluna. O que não foi reconhecido a pessoa **arrasta** até o campo certo. Dá para **criar campo personalizado no próprio mapeamento**.
4. Prévia: dados no campo certo, ligações corretas, o que está faltando. Se faltar título no negócio, o sistema gera um a partir do nome da pessoa ou da organização.
5. Duplicados: mesclar com o existente. Em campo de múltipla escolha, "Overwrite" ou "Append".
6. Histórico de importações com contagem de adicionados, atualizados, mesclados e ignorados, mais um arquivo com as linhas ignoradas e o motivo de cada uma.
7. **Desfazer em até 48 horas**, só para administrador.

Fonte: https://support.pipedrive.com/en/article/importing-data-into-pipedrive-with-spreadsheets

**Criar campo:**
- Nome e tipo são obrigatórios, e o **tipo não pode ser mudado depois**.
- **Descrição** existe só para campos de negócio e lead, a partir do plano Growth. A equipe vê num ícone de informação ao lado do campo.
- Há grupos para organizar.
- Campo "importante" avisa quando falta (Growth). Campo "obrigatório" impede salvar (Premium).
- O campo pode aparecer na tela de detalhes, no modal de criação (opcional), nas colunas da lista e no mapeamento da importação.

Fonte: https://support.pipedrive.com/en/article/custom-fields

**Ficha da pessoa:**
- Barra lateral com um resumo fixo (etiquetas, e-mail, telefone, organização).
- Seção Details com os campos que a pessoa escolher.
- Negócios, leads e projetos ligados.
- Focus (próximas atividades, notas fixadas) e History (alterações, com filtro).
- "+Link an organization" cria a organização ali mesmo se ela não existir.
- Seções podem ser ocultadas e reordenadas, e isso vale só para o próprio usuário.

Fontes: https://support.pipedrive.com/en/article/contact-detail-view e https://support.pipedrive.com/en/article/detail-view-sidebar

**Complexo demais para um leigo:**
- Ir até "Personal preferences > Data fields" para criar campo fora da importação.
- Arrastar e soltar no mapeamento, que é ruim no toque.
- Escolher entre Overwrite e Append.
- O desfazer de 48 horas é restrito a administrador e às vezes depende do suporte.

---

## 4. Zoho CRM

- **Um módulo por vez.** Não achei importação de vários módulos num arquivo só. O assistente de migração também usa um CSV por módulo.
- **Ligação entre registros por coluna de lookup:** a linha traz o nome ou o ID do registro pai, como "Account name" num contato. Se faltar, o vínculo fica vazio.
- Terceiro recomenda a ordem contas, depois contatos, depois negócios. Se importar negócios antes das contas, o vínculo com a conta fica vazio.
- **Jornada:**
  1. Arquivo e codificação de caracteres.
  2. Layout.
  3. Opção de duplicado e campo único.
  4. Mapeamento, com "Apply Auto Mapping", "Reset" e "**Create New Fields**".
  5. Regras de atribuição, automações e tarefas.
  6. Finish.
- Depois de iniciada, a importação **não pode ser cancelada**. O artigo não fala em desfazer.
- **Duplicados:**
  - Campo único por módulo: lead e contato por e-mail, conta por nome, negócio pelo nome do negócio.
  - Ação para registros que coincidem: sobrescrever, pular ou clonar (FAQ). O assistente chama os modos de "Add as new", "Update existing only" e "Both".
  - "Don't update empty values" evita que célula vazia apague dado existente.
- Limite de 5.000 registros por lote em XLS e XLSX.
- **Conversão lead → contato/conta/negócio:** campos próprios do lead só passam adiante com "Lead Conversion Mapping" configurado no Setup. É análogo ao nosso "lead vira cliente". A fonte é terceira, a confirmar.

Fontes:
- https://help.zoho.com/portal/kb/articles/import-data (documenta a versão antiga do importador)
- https://help.zoho.com/portal/en/kb/crm-v2/faqs/data-administration/import/articles/crm-v2-exist-faqs-import
- https://www.codestringers.com/articles/how-to-import-data-into-zoho-crm (terceiro)

**Complexo demais para um leigo:** codificação de caracteres, layout, "clonar duplicado", ordem obrigatória de importação, lookup por nome exato, regras de atribuição e automação no meio da importação.

---

## 5. Microsoft Dynamics 365

- Um arquivo por rodada. Vários objetos só juntos num .zip.
- O mapeamento automático só funciona quando o cabeçalho é igual ao nome do campo.
- Na tela "Review Mapping", os campos obrigatórios aparecem primeiro. Coluna com valores fixos precisa casar com um "option set" (lista de opções), valor por valor.
- A ordem importa: contas antes dos contatos, senão o vínculo não é preenchido.
- Duplicados: opção "Allow Duplicates", em geral deixada em "Não", mais regras de duplicidade configuradas em Settings > Data Management. As linhas barradas viram falhas, exportáveis para corrigir e reenviar.

Fontes:
- https://learn.microsoft.com/en-us/dynamics365/customer-insights/journeys/import-data
- https://technet.microsoft.com/library/dn531083.aspx (legado)

Não achei a página atual do Dynamics 365 Sales no Learn.

**Complexo demais para um leigo:** praticamente tudo. Option sets, .zip para vários objetos, regras de duplicidade configuradas em outra área, chave alternativa.

---

## 6. Freshsales (Freshworks CRM)

- Importa contatos e contas juntos. O contato é ligado à conta quando o "Account name" do arquivo bate com uma conta existente.
- Negócios: a coluna "Related Contacts" aceita e-mails separados por ";". "Account Name" precisa ser o nome **exato**. Sem funil personalizado, o negócio cai no funil padrão.
- **Campos personalizados e opções de listas precisam ser criados antes da importação.** Não achei confirmação de criação de campo no mapeamento. Máximo de 100 campos personalizados de contato.
- Um campo do sistema não pode ser mapeado duas vezes. Coluna não mapeada é ignorada.
- Arquivo de até 5 MB.

Fontes:
- https://crmsupport.freshworks.com/support/solutions/articles/50000005537-how-to-import-contacts-and-accounts-together-link-contacts-to-existing-accounts-
- https://support.freshsales.io/support/solutions/articles/218558--importing-contacts-from-a-csv-file-
- https://support.freshsales.io/support/solutions/articles/222658-how-to-import-deals-from-csv-file-

O tratamento de duplicados ficou cortado no texto obtido. Não confirmado.

---

## O que os seis têm em comum

| Tema | Como o mercado faz | Quem faz melhor |
|---|---|---|
| Pessoa, empresa e negócio num arquivo | Uma linha liga tudo | HubSpot (single file) e Pipedrive. Zoho, Dynamics e Salesforce exigem ordem ou arquivos separados |
| A que objeto vai cada coluna | Destino escolhido coluna a coluna | HubSpot mostra o objeto na coluna. Pipedrive usa arrastar |
| Duplicado | E-mail para pessoa, domínio ou nome para empresa, ID para atualizar | Todos. O negócio não tem chave natural em ninguém |
| Não apagar dado bom | "Don't overwrite" ou "não atualizar com vazio" | HubSpot, Zoho e Salesforce |
| Criar campo na importação | Sim no HubSpot, Pipedrive e Zoho. Não confirmado no Freshsales (orienta criar antes) e no Salesforce | Pipedrive (simples) |
| Descrição do campo | HubSpot (aba Documentation). Pipedrive (só negócio e lead, plano pago, num ícone de informação) | Nenhum usa a descrição como instrução da IA. O HubSpot usa um prompt à parte |
| Prévia antes de gravar | Pipedrive tem prévia. Os demais mostram contagem ou confirmação | Pipedrive |
| Desfazer | Só o Pipedrive (48 horas, administrador). Zoho não cancela | Pipedrive |
| Relatório pós-importação | Pipedrive (contagens e arquivo de erros), Dynamics (aba Failures), HubSpot (corrige no assistente) | Pipedrive |
| Ficha do cliente | 3 colunas (HubSpot) ou barra lateral com resumo fixo e linha do tempo (Pipedrive) | Pipedrive é mais simples |

## Brechas que dá para explorar

O que nenhum deles resolve bem para quem não é técnico:

1. **Vocabulário técnico em toda parte:** "upsert", "Record ID", "lookup", "option set", "association label", "Overwrite/Append". Dá para trocar cada um por uma pergunta simples, por exemplo: "Já tem essa pessoa? Atualizo os dados dela".
2. **Ordem de importação e vínculo por nome exato** (Zoho, Dynamics, Freshsales). A regra "uma linha = uma pessoa, a empresa dela e o negócio dela" do Pipedrive e do HubSpot é o modelo certo.
3. **Ninguém pergunta "este dado é da pessoa, da empresa ou da venda?"** de forma guiada. Todos mostram uma lista de propriedades agrupadas por objeto. É aqui que a Base de clientes pode se diferenciar: cartões por coluna, com prévia de exemplos reais da planilha.
4. **Ninguém replica um dado de negócio para o contato** de forma explícita. O mais perto é o "Lead Conversion Mapping" do Zoho, configurado no Setup e não na importação.
5. **Descrição do campo como instrução da IA não existe em nenhum dos seis.** No HubSpot são duas coisas (Documentation e prompt da smart property). No Pipedrive a descrição existe só em plano pago. Um campo único de "nome + explicação curta" que serve à equipe e à leitura das conversas é diferencial.
6. **Desfazer e prévia são raros.** Só o Pipedrive tem os dois, e o desfazer é limitado.
7. **Tipo de campo imutável** (Pipedrive) e a advertência de que mudar o tipo invalida dados (HubSpot) mostram que vale escolher o tipo pelo leigo, inferindo pelos valores da coluna, com botão "Alterar".

## Lacunas da pesquisa

- A página oficial do Salesforce Data Import Wizard não carregou. Usei SalesforceBen, salesforcebreak.com e páginas oficiais relacionadas.
- Tratamento de duplicados no Freshsales: não confirmado.
- O desfazer no HubSpot não foi encontrado nos artigos lidos. Não afirmo que exista nem que não exista.
- A página atual do Dynamics 365 Sales não foi encontrada no Learn.


## mercado: brasil

# Pesquisa de mercado: base de clientes, importação de planilha, campos e ficha do cliente nos players brasileiros e de atendimento por WhatsApp

**Escopo e limites.** Usei só fontes públicas: centrais de ajuda e sites oficiais. Não abri conta em nenhum produto, então nada aqui vem de teste de tela.

Lacunas:
- **RD Station CRM:** a página de ajuda ajuda.rdstation.com (Salesforce) não carregou no fetch, só mostrou "CSS Error". O que trago sobre ela vem do resumo da busca e da página de planos.
- **PipeRun:** o domínio piperun.com está à venda (é outra empresa). O produto fica em crmpiperun.com, e usei só a central de ajuda.
- **Sem fonte oficial sobre importação:** Huggy, Blip e Octadesk (importação de organizações).

---

## 1. Como cada um chama e organiza a base

| Player | Pessoa | Empresa | Negócio | Nome do módulo / base |
|---|---|---|---|---|
| RD Station CRM | Contatos | Empresas | **Negociações** | Importação de "negociações, empresas e contatos" |
| RD Station Marketing | **Leads** | – | – | Base de Leads, com segmentações |
| Kommo | Contatos | Empresas | **Leads** (o card do funil) | "client database using three record types: leads, contacts, and companies" |
| Ploomes | Contato / **Pessoa** | **Cliente** / Empresa | Negócios (o módulo Leads foi desativado) | "Clientes" é o termo central ("Visão 360º de clientes") |
| Agendor | **Pessoas** | Empresas | Negócios | Abas Empresas / Pessoas / Negócios / Tarefas |
| Moskit (agora **Ollow**) | Contatos | Empresas | Negócios (e Projetos) | – |
| PipeRun | Pessoas | Empresas | **Oportunidades** | – |
| Bitrix24 | Contatos | Empresas | Negócios (e Leads) | "CRM > **Clientes** > Empresas/Contatos" |
| Octadesk | Contatos | Organizações | – (só o status "Lead ou Cliente") | "Gestão de contatos" |
| Huggy | Contatos | Organizações | – | Configurações > Campos personalizados |
| Blip | Contato com "**extras**" | – | – | Os campos livres se chamam *extras* |
| Zenvia | Contatos com "atributos" | – | – | Contatos > Importar contatos |
| Respond.io | Contacts com "Contact fields" | – | – | Contacts |

**Leitura.** Não há termo comum no mercado para o card do funil: chamam de negociação, negócio, lead ou oportunidade. Os CRMs nativos do Brasil (Agendor, Ploomes, PipeRun) falam "Pessoas / Empresas / Negócios". As ferramentas de WhatsApp quase não têm empresa e não têm negócio: são só contato com campos extras.

Fontes:
- [Kommo – campos](https://support.kommo.com/docs/customize-fields-in-lead-profiles.md)
- [Ploomes – importação de negócios](https://suporte.ploomes.com/pt-BR/articles/5792676-importacao-de-negocios)
- [Ploomes – home](https://www.ploomes.com/)
- [Agendor – home](https://www.agendor.com.br/)
- [Bitrix24 – importação vinculada](https://helpdesk.bitrix24.com.br/open/25908967/)
- [Octadesk – perfil de contato](https://help.octadesk.com/a/o-que-e-o-perfil-de-contatos-na-octadesk)
- [Blip – extras (comunidade)](https://community.blip.ai/outros-assuntos-4/campos-de-contato-no-blip-desk-4266)

---

## 2. Importação de planilha: separar pessoa, empresa e negócio

Este é o ponto mais próximo da "Base de clientes" que o Rodrigo quer.

| Player | Uma planilha cria os três ligados? | Como diz de quem é cada coluna |
|---|---|---|
| **Ploomes** | Sim | Em cada coluna, "Você precisa definir se aquele campo é um campo de **Negócio, Empresa ou Pessoa**". Para o negócio entrar no funil, a coluna Estágio precisa estar mapeada. Há uma marca "Detectar duplicado por este campo" para cada tipo. |
| **Kommo** | Sim ("Kommo can create and link all records during a single import") | Os nomes das colunas precisam ser **idênticos** aos dos campos, até em maiúsculas e minúsculas. A ordem do mapeamento pode ser salva como modelo. Aceita tag opcional e "Update existing data". Limite de 2 MB e 10 mil linhas, uma aba só, sem linha vazia. |
| **Moskit/Ollow** | Sim ("Contatos, Empresas, Negócios, Projetos ou todos simultaneamente") | A tela de mapeamento tem 3 colunas: cabeçalho, 1ª linha de dados e campo de destino. Dá para ignorar uma coluna. Negócio exige nome, fase, data de fechamento e motivo de perda. Os campos novos precisam ser criados antes, em Configurações. Gera um "arquivo de erros" com o motivo de cada linha recusada. |
| **PipeRun** | Empresas e pessoas juntas | Faz um "De > Para" automático pelo nome da coluna. Tem botão "**+ Novo campo customizado**" no meio do mapeamento (nome, se é de empresa ou pessoa, e tipo). Para pessoas pede **base legal da LGPD**. Para duplicados oferece 3 escolhas: "Atualizar os dados", "Manter cadastro e **complementar**" e "Descartar os dados novos". Os erros aparecem **na célula**, com correção em massa (limpar, aplicar valor padrão ou remover a coluna). |
| **Agendor** | Não. É uma importação por aba, e a ordem precisa ser Empresas, depois Pessoas, depois Negócios | Baixa-se a planilha modelo, e o botão "**Adicionar campo**" cria o campo durante a importação (nome, tipo e **seção do formulário**; só administrador). Mostra **prévia das primeiras 50 linhas** e termina em "Realizar importação". |
| **Bitrix24** | Não. São três importações em ordem | O vínculo é feito **pelo nome exato** ("TechNova Soluções" ≠ "Tech Nova Soluções"). Para duplicados: Permitir, Substituir, **Combinar** (só preenche o vazio) ou Pular. Negócio existente não é atualizado: vira duplicata. |
| **RD Station CRM** | Mapeia pelas categorias Empresa e Contato ("Buscar campo em todas as categorias") | Base legal da LGPD obrigatória. Mostra as 5 primeiras linhas. Duplicados: mesclar ou criar. Limite de 1.000 registros no Free e 10.000 nos planos pagos (fonte: resumo da busca e página de planos). |
| **Respond.io** | Só contato | Pergunta primeiro a **finalidade**: "Add new only / Update only / Add & update / Add all despite duplicates". Identificador: telefone ou e-mail. Opção "**Do Not Overwrite**". A tela de revisão mostra quantos serão adicionados, atualizados ou terão erro. Gera tag automática do lote. Aceita até 20 MB e 200 mil linhas. |
| **Zenvia** | Só contato | Cria o campo durante a importação (nome e tipo), com limite de 100 campos extras por organização. |

Fontes:
- [Ploomes – importação de clientes](https://suporte.ploomes.com/pt-BR/articles/5780574-importacao-de-clientes)
- [Ploomes – importação de negócios](https://suporte.ploomes.com/pt-BR/articles/5792676-importacao-de-negocios)
- [Kommo – importação](https://support.kommo.com/docs/import-data-into-kommo)
- [Ollow/Moskit – importação CSV](https://ajuda.ollow.com.br/pt-BR/articles/1343851-importando-dados-de-uma-planilha-csv-para-o-moskit)
- [PipeRun – importar empresas](https://ajuda.crmpiperun.com/como-importar-empresas)
- [Agendor – campos customizados](https://ajuda.agendor.com.br/pt-BR/articles/6801698-como-importar-clientes-com-campos-customizados)
- [Agendor – banco de dados](https://ajuda.agendor.com.br/pt-BR/articles/2014083-como-importar-meu-banco-de-dados-para-o-agendor)
- [Bitrix24](https://helpdesk.bitrix24.com.br/open/25908967/)
- [RD – importar negociações](https://ajuda.rdstation.com/s/article/Importar-base-de-dados?language=pt_BR)
- [RD CRM – planos](https://www.rdstation.com/planos/crm/)
- [Respond.io – importação](https://respond.io/help/contacts/contact-import)
- [Zenvia – importação](https://support.zenvia.com/kb/pt-br/article/452230/criar-arquivos-csv-para-importacao-zcc)

**O que nenhum deles faz:**
- **Perguntar se um dado de negócio também deve ir para o contato.** Em todos os casos, uma coluna tem um único destino.
- **Pedir descrição ao criar o campo.** Pedem só nome, tipo e, no máximo, a seção do formulário.
- **Interpretar a planilha.** O mapeamento é sempre por nome de coluna (Kommo exige nome idêntico) ou feito à mão.

---

## 3. Campos personalizados e preenchimento a partir da conversa

- **Kommo:** campos para lead, contato e empresa. Só o administrador cria. Podem ser obrigatórios por etapa. Dá para escolher se o campo aparece no card do lead, e os campos do contato e da empresa aparecem dentro do card do lead ("Contact fields", "Company fields"). O agente de IA tem a ação "Collect customer details and update the lead card" e o recurso "Enrich lead data". O "Set field" só existe nos planos Advanced e acima, e a própria documentação se contradiz sobre editar campos personalizados.
  - [Kommo – AI agent assist](https://support.kommo.com/docs/ai-agent-assist.md)
  - [Kommo – AI agent](https://www.kommo.com/support/crm/kommo-ai-agent/)
- **Respond.io:** o agente de IA atualiza campos do contato, mas só se as instruções citarem "o nome exato do campo ou o ID do campo". Não usa descrição do campo. Não cria campos. E "não conseguem detectar quando uma atualização… falha", ou seja, a falha é silenciosa.
  - [Respond.io – atualizar campos (pt)](https://respond.io/pt/help/ai-agent-actions/ai-agent-action-update-contact-fields)
- **RD Station CRM:** "O CRM se atualiza enquanto você vende." e "Nenhuma informação fica só na memória do vendedor." O vendedor atualiza por áudio ou texto. Os campos personalizados podem ser obrigatórios por etapa (5 no plano Free, ilimitados nos pagos) e aparecem no cartão do funil.
  - [RD CRM](https://www.rdstation.com/crm/)
  - [RD CRM – planos](https://www.rdstation.com/planos/crm/)
- **Agendor (Ava):** "Mantenha o CRM 100% atualizado com a Agente de IA" e "A IA que trabalha pelo vendedor, do registro ao follow-up". Capta informações de WhatsApp e ligações. Isso é alegação de marketing, sem documentação técnica do mapeamento para os campos.
  - [Agendor](https://www.agendor.com.br/)
  - [Ava](https://www.agendor.com.br/solucoes/ava)
- **Ploomes:** "alimenta sozinho o histórico do cliente" e "Estúdio IA" com "Construtor de Telas".
  - [Ploomes](https://www.ploomes.com/)
- **Octadesk:** "Campos de pessoas" (texto, sim/não, data, lista). A IA (WOZ) sugere respostas. Não achei fonte de que ela preencha campos.
  - [Octadesk – perfil de contato](https://help.octadesk.com/a/o-que-e-o-perfil-de-contatos-na-octadesk)
- **Huggy:** Configurações > Campos personalizados, com escolha entre Contatos e Organizações, tipo e obrigatório. A busca resumiu o que seria a Central de Ajuda, mas não abri a página.
- **Blip:** "extras" livres, aparecem no Desk em "informações", embaixo. Pela comunidade, não dá para filtrar por um extra específico (fonte antiga).
  - [Blip comunidade](https://community.blip.ai/outros-assuntos-4/buscar-contatos-por-extras-1996)

**Lacuna confirmada:** nenhum player documenta o uso da **descrição do campo** como instrução para a IA preencher. Respond.io e Kommo dependem do nome exato e de instruções escritas no agente. Campo com nome e descrição usados pela IA seria diferencial.

---

## 4. Ficha do cliente

- **Octadesk:** abas Perfil / Tickets / Produtos ou Serviços. O e-mail é a chave única, e se faltar é criado um fictício. Não é possível excluir nem bloquear contato, só inativar. A busca funciona só por nome, e-mail e telefone.
- **Kommo:** o card do lead concentra os campos do contato e da empresa vinculados. O contato tem "a full history of communications, tasks, and changes".
  - [Kommo – lead profiles](https://support.kommo.com/docs/lead-profiles.md)
- **Bitrix24:** cartão com aba "**Vínculos**", que mostra empresa, contato e negócio ligados.
- **Ploomes:** "Visão 360º de clientes" e "CRM que centraliza toda a jornada do cliente em um só lugar".
- **Agendor:** os campos customizados ficam em "**seções do formulário**" escolhidas ao criar o campo.

---

## 5. Linguagem com o pequeno empresário (trechos literais)

- **RD:** "Seu cliente está no WhatsApp. O CRM também." / "O CRM se atualiza enquanto você vende."
- **Agendor:** "Venda onde o Brasil conversa, com as conversas dentro do CRM." / "funil sempre em dia".
- **Kommo:** "Escale conversas, evite o caos." / "Responda 24/7 sem se cansar". Cobra em dólar, a partir de USD 20 por usuário. [kommo.com/br](https://www.kommo.com/br/)
- **Ploomes:** "constrói, você vende" / "100% Suporte nacional especializado" / "03 min Tempo médio de resposta".

**Padrão.** Todos falam do benefício (não perder venda, CRM em dia), não do recurso. RD, Agendor e Kommo citam "IA" de forma explícita no marketing. A regra do Rodrigo de não citar IA na interface é mais restritiva que a do mercado, e o espaço para se diferenciar está no texto das telas, não no marketing.

---

## 6. O que serve para a Base de clientes do Chat2You (interpretação minha, não fato)

1. **Classificar cada coluna em Pessoa, Empresa ou Negócio, como faz o Ploomes**, mas com a sugestão já pronta e um botão "Alterar". Ninguém pergunta "isso também vai para o contato?": é uma lacuna que podemos ocupar.
2. **Criar o campo sem sair da importação**, como o "Adicionar campo" do Agendor e o "+ Novo campo customizado" do PipeRun, acrescentando a **descrição**, que nenhum concorrente pede.
3. **Prévia com contagem antes de importar**, no estilo do Respond.io ("X novos, Y atualizados, Z com problema"). Mostrar as linhas, como o Agendor (50) ou o RD (5).
4. **Para duplicados, as 3 escolhas do PipeRun em linguagem simples**: atualizar, completar só o que falta, manter o que já tem. Padrão sugerido: completar.
5. **Correção na própria tela**, como o PipeRun (célula marcada e correção em massa), em vez de devolver um "arquivo de erros" como Moskit, Bitrix e Agendor. Para alguém de QI 70, baixar planilha de erro é beco sem saída.
6. **Evitar o que o mercado faz de pior:**
   - exigir ordem de importação (Agendor, Bitrix);
   - vincular por nome exato (Bitrix);
   - exigir cabeçalho idêntico ao campo (Kommo);
   - criar campo só em Configurações antes de importar (Moskit, Respond.io);
   - falha silenciosa da IA ao preencher campo (Respond.io admite isso na própria documentação).
7. **LGPD:** RD e PipeRun pedem base legal na importação. Fica como ponto a decidir com o Rodrigo, sem recomendação minha.


## mercado: novos-entrantes

# Pesquisa: CRMs novos com IA (Attio, Folk, Twenty, Clay, Day.ai, Lightfield, Affinity, Close, Clarify, HubSpot)

Pesquisado em 11/10/2026. Boa parte das fontes é do próprio fornecedor ou de concorrente, e isso vai marcado em cada caso.

## 1. O que cada um faz de diferente

### Attio (o mais maduro em modelo de dados e importação)
- **Modelo de dados**: tudo é objeto, atributo ou registro. Atributo do objeto fica no próprio registro e aparece em todo lugar. Atributo de lista vale só dentro daquela lista. https://www.automationjinn.com/blog/attio-custom-objects-data-model
- **Jornada de importação** (documentação oficial), em 6 passos:
  1. Escolhe o destino.
  2. Sobe o CSV.
  3. O sistema liga as colunas sozinho e oferece "+ Create new attribute" na hora.
  4. A pessoa revê os valores coluna a coluna: o dado original ao lado do convertido, aviso "Invalid format" e "Create missing select options".
  5. **Prévia** com o que será criado e atualizado, por objeto. O número é estimado: o sistema não confere uma linha contra outra, e linhas com o mesmo valor único viram um só registro.
  6. Roda em segundo plano, com progresso registro a registro e filtro Falhou/Planejado/Concluído.

  Fonte: https://attio.com/help/reference/imports-exports/csv-imports/import-data-into-attio-via-csv
- **Pessoa, empresa e negócio na mesma planilha**: o Attio **não** separa. Mandam dividir em importações separadas (Pessoas, depois Negócios). Empresa é criada a partir do domínio do e-mail, exceto e-mails públicos como Gmail. Sem uma chave única (e-mail ou domínio) mapeada, ele cria duplicata e só avisa com "Avoid creating duplicate records". Mesma fonte.
- **Duplicatas**: juntar registros é manual, um par por vez. A sugestão de junção usa só e-mail e domínio. A busca aproximada fica com apps de terceiros, como o Deduptio (com desfazer em 24h) e o Dedupe (junta sozinho acima de um nível de confiança e manda o resto para uma fila de revisão). https://attio.com/help/reference/managing-your-data/records/merge-and-delete-records · https://attio.com/apps/deduptio · https://attio.com/apps/dedupe
- **IA em 2026** (changelog oficial):
  - "Ask Attio", um agente que conversa sobre os dados, em 04/02.
  - "Ask Attio to take action" em 29/04.
  - "Custom context" em 28/05.
  - "Web research agent" como atributo de IA em 24/03.
  - Atributos de fórmula em 28/07.
  - "A more intuitive Ask Attio", que sugere o que perguntar, em 23/09.

  https://attio.com/changelog/2026 · https://attio.com/engineering/blog/ask-attio-a-technical-look-at-our-new-agent
- **Atributos de IA**: preenchem a partir de um critério escrito pela pessoa, gastam créditos e rodam por gatilho, não sozinhos. Só no plano Plus para cima. A fonte é uma análise de terceiros. https://www.stacksync.com/blog/attio-crm-2025-review-features-pros-cons-pricing
- **Página do registro redesenhada em 2026**:
  - nome, dados principais e ações juntos no topo e à esquerda;
  - seções que mudam de tamanho;
  - **busca entre todos os atributos**;
  - comentários num painel lateral;
  - automações recolhidas na linha do tempo, para reduzir ruído;
  - até 6 widgets arrastáveis.

  https://attio.com/changelog/2026/record-page-redesign

### Folk (o mais simples para quem não é técnico)
- **Campos mágicos**: a pessoa cria uma coluna, escolhe o tipo "Magic field" e escreve um pedido com variáveis como {Job title} e {Notes}. Depois seleciona as células e roda em lote. Na versão anterior, era um botão "Fill with AI" em campos de texto, data, seleção e número. O valor aparece na tabela, **no perfil do contato** e como variável em mensagens. https://help.folk.app/en/articles/7325564-magic-fields
- **Enriquecimento**: um clique, com a Dropcontact embutida. https://www.dropcontact.com/integration/folk
- **Campos por grupo**: cada campo personalizado vale só dentro do grupo onde foi criado. https://www.breakcold.com/de/blog/folk-crm-review
- **Duplicatas**: uma avaliação de mar/2025 diz que o Folk só detectava duplicata quando nome e sobrenome eram idênticos, mesmo com e-mail igual. Não achei confirmação de correção. https://at.trustpilot.com/review/folk.app

### Twenty (código aberto)
- A versão 2.0 saiu em 21/04/2026, com agentes, chat e MCP (o protocolo que deixa ferramentas de IA lerem e gravarem no CRM). Os modelos de dados podem ser escritos em código. https://wz-it.com/en/blog/twenty-crm-updates-1-3-0-1-4-0/ · https://github.com/twentyhq/twenty/releases
- Objetos e campos também se criam sem código, em Settings → Data model. A importação é por CSV ou API. https://twenty.com/partners · https://docs.twenty.com/user-guide/getting-started/capabilities/what-is-twenty
- Não achei um tipo de "campo preenchido por IA" nativo.

### Clay (enriquecimento)
- Funciona como uma planilha: cada linha é um registro e cada coluna é uma ação. A "cascata" consulta vários fornecedores de dados em sequência e para no primeiro que acerta. O Claygent é um agente que pesquisa na web. https://vantaige.io/es/blog/how-clay-works-waterfall-enrichment-2026
- Quem usa reclama da curva de aprendizado de 2 a 4 semanas e do gasto de créditos imprevisível. É ferramenta de especialista, o oposto do público com QI 70. https://amplemarket.com/blog/what-does-clay-really-do (fonte concorrente)
- A Attio integrou com o Clay em 30/03/2026. https://attio.com/changelog/2026

### Day.ai (CRM que se preenche lendo conversas)
- Campos personalizados nos objetos Organização e Oportunidade. Segundo a própria Day.ai: "AI auto-populates fields by analyzing all your conversations, meetings, and existing data", e cada campo leva em conta o resto do CRM. https://www.day.ai/resources/new-now-day-ai-fits-your-business
- **Importar negócios do jeito novo**: não copia negócios de outro CRM. A pessoa marca a empresa como prospect, cliente ou parceiro, e o sistema deduz a etapa pelas conversas, **mostrando o porquê**. Assim evita importar oportunidades mortas. https://www.day.ai/resources/solving-problems-with-crm-in-an-ai-native-way-deal-import-example
- Pontos fracos citados: curva de aprendizado e poucas integrações. https://www.coffee.ai/articles/day-ai-crm-startups-review/ (fonte concorrente)

### Lightfield (dos fundadores do Tome)
- Lançado em nov/2025. Rodada de US$ 47 milhões liderada pela a16z em 09/09/2026, com mais de 5.000 empresas cadastradas (número informado pela própria empresa). https://pulse2.com/lightfield-raises-47-million-series-a-to-build-ai-native-crm-for-companies-using-agents/
- **Agente de migração** (25/03/2026): lê os CSVs do HubSpot e de outros CRMs e liga sozinho contatos, empresas, negócios, campos personalizados, etapas e relações. Ele "confirms the import mapping before touching any data". O texto não diz se uma pessoa precisa aprovar. https://martechseries.com/sales-marketing/crm/lightfield-launches-one-hour-crm-migration-agent-enabling-startups-to-replace-hubspot-with-an-ai-native-crm-in-under-60-minutes/
- **Campo criado depois e preenchido para trás**: "Create a custom field like 'current CRM' at any point, and the system backfills from all past conversations". Também promete "No upfront field configuration", guardando tudo em bruto desde o primeiro dia. https://lightfield.app/blog/day-ai-review (fonte concorrente da Day.ai)

### Affinity
- Captura automática de e-mail, agenda e reuniões, e um mapa de "quem conhece quem". É voltado para fundos de investimento. Nada de novo em 2026 que eu tenha confirmado. https://sacra.com/chat/h/90f534a8-c49f-4335-8611-e8ba2e9b81eb/

### Close
- O importador é clássico, sem IA. Coluna não reconhecida vira sugestão de campo personalizado, criado como texto na hora de importar. Campos de seleção e status precisam existir antes. Pede datas em aaaa-mm-dd. https://help.close.com/docs/importing-leads-from-file

### Clarify
- Diz ser um CRM "autônomo": agentes registram e resumem ligações, enriquecem cadastros e atualizam negócios. https://aws.amazon.com/marketplace/pp/prodview-vkrkvx5hvhabc
- Críticas: funis e relatórios limitados, e preço incerto quando cresce. https://www.breakcold.com/blog/clarify-ai-crm-review (fonte concorrente)

### HubSpot (incumbente, mas a referência mais próxima do nosso "nome + descrição")
- **Smart properties**: o Data Agent "automatically generates a prompt based on your property name and field type". Também dá para **descrever em linguagem comum** o campo que se quer, e o sistema define nome, tipo, pedido e fonte. A pessoa edita antes de salvar.
- Fontes possíveis: ligações, e-mails, transcrições de reunião e notas do registro.
- Preenche manualmente, em lote, por agenda ou quando o registro é criado.
- Mostra as fontes do valor (botão AI → Sources), mas **não mostra nível de confiança**.
- Gasta créditos "even when a value isn't filled".

https://knowledge.hubspot.com/properties/create-smart-properties · https://knowledge.hubspot.com/data-management/use-data-agent

## 2. Tendência real ou exagero

**Tendência real** (vários fornecedores fazem e há documentação oficial):
1. **Campo = nome + descrição, preenchido pela IA a partir das conversas e da web.** Fazem isso HubSpot, Folk, Attio, Day.ai e Lightfield. Isso confirma a ideia do Rodrigo de usar nome e descrição.
2. **Prévia antes de gravar e importação em segundo plano com relatório por linha.** O Attio é a referência.
3. **Ligação automática das colunas, com criação de campo na própria importação** (Attio, Close, Lightfield).
4. **Mostrar de onde veio o valor** (HubSpot, Day.ai).
5. **Preencher para trás** quando um campo é criado depois (Lightfield).
6. **Agente que conversa com os dados e age** (Ask Attio, Twenty 2.0).

**Exagero ou ainda imaturo:**
- "CRM que se monta sozinho a partir de uma conversa sobre o negócio": **não achei nenhum produto que faça isso**. O mais perto é o HubSpot criando *um* campo a partir de uma descrição.
- Juntar duplicatas por IA dentro do próprio CRM: nos incumbentes e nos novos é exato e manual (Attio só por e-mail e domínio). A busca aproximada com fila de revisão fica com apps de terceiros, e os números de precisão são marketing.
- "Migração em 1 hora" e "zero clique": vêm de comunicado da empresa ou de concorrente, sem teste independente.
- Ferramentas que gastam créditos (Clay, HubSpot, Attio): o custo pesa e espanta o pequeno negócio.

## 3. O que levar para a Base de clientes do Chat2You

Esta parte é a minha leitura da pesquisa, não fato de fonte.

1. **Separar pessoa, empresa e negócio numa só planilha é uma lacuna de mercado.** O Attio manda dividir a planilha. O Pipedrive manda a pessoa arrumar antes de importar (https://support.pipedrive.com/hc/pt-br/articles/208039595). Só o Lightfield faz numa vez, e para migração de CRM. É um diferencial possível para o público leigo.
2. Copiar a **prévia e o relatório por linha** do Attio, mas sem a tela técnica de ligar colunas. Usar um cartão por coluna ("Esta coluna é da pessoa / da empresa / do negócio", com botão "Alterar").
3. **Duplicatas**: o mercado ainda não resolve isso nativamente. Para o público do WhatsApp, a chave natural é o **telefone**, que nenhum dos citados usa como chave principal. Sugestão: juntar sozinho só quando o telefone ou e-mail for idêntico, e mandar os casos aproximados para uma fila "Parecem a mesma pessoa?".
4. **Campos com nome e descrição**: seguir o HubSpot e sugerir a descrição a partir do nome. Seguir o Lightfield e preencher para trás pelas conversas antigas. Mostrar "de onde veio" de forma simples ("Visto na conversa de 12/09"), sem citar IA.
5. **Página do contato**: seguir o redesenho do Attio (essencial no topo, busca de campos, linha do tempo sem ruído) e o Folk (o campo aparece no perfil e serve de variável na mensagem).

Não verifiquei telas reais por login, nem a Kommo e a RD Station a fundo (a busca não trouxe nada sobre a Kommo). Também não confirmei se a correção de duplicatas do Folk e o tipo de campo de IA do Twenty existem hoje.


## mercado: import-ux

# Pesquisa de mercado: como as ferramentas de importação de planilha resolvem cada etapa

Todos os URLs abaixo eu li ou vi nos resultados de busca. Quase todo o material vem dos próprios fornecedores (documentação ou blog), então os números de acerto da IA são propaganda deles e ninguém confirmou de forma independente.

**O que não consegui confirmar:**
- O NN/g não tem artigo sobre importação de dados; usei o artigo deles sobre assistentes passo a passo (*wizards*).
- A página de recursos avançados do OneSchema deu 404. O que cito dele saiu do resumo da busca.
- No HubSpot, não achei quais campos o painel "Create a new property" pede, nem se uma mesma coluna pode virar campo do contato e do negócio ao mesmo tempo.
- O Folk faz enriquecimento na importação, mas não achei prova de que ele use IA para mapear as colunas.

## 1. As etapas são quase sempre as mesmas

- **Os importadores especializados usam de 3 a 4 telas**: enviar o arquivo, ligar as colunas, revisar e enviar. Assim fazem a Ingestro (antiga nuvo) e o Flatfile, e o CSVBox descreve a mesma sequência.
  - https://docs.ingestro.com/sdk/overview/
  - https://support.flatfile.com/articles/7763163677-importing-data-with-flatfile-overview
  - https://blog.csvbox.io/ai-feedback-user-import-errors/
- **O Dromo tem uma tela só para ligar valores de lista** (`matchValuesStep`), entre ligar as colunas e revisar. Ele também aceita um texto de ajuda por etapa (`helpText`).
  - https://developer.dromo.io/settings/
- **O Pipedrive faz: enviar → ligar colunas → prévia → repetidos.** Sobre a prévia, a documentação diz que é "your last chance to catch issues before the import is completed" ("sua última chance de pegar problemas antes de concluir").
  - https://support.pipedrive.com/en/article/importing-data-into-pipedrive-with-spreadsheets
- **O NN/g recomenda, para assistentes passo a passo:**
  - mostrar as etapas e destacar a atual;
  - não deixar pular etapa;
  - nomear o botão de avançar pela ação, em vez de "Próximo";
  - ter um botão "Voltar" visível;
  - deixar sair no meio e continuar depois sem perder nada;
  - cada etapa se explica sozinha, e a ajuda fica ao lado, sem cobrir a tela;
  - "reusing the user's selections from previous use as the defaults" (usar as escolhas da última vez como ponto de partida).
  - https://www.nngroup.com/articles/wizards/
- **Quando todas as colunas já batem, a ferramenta pula a tela de ligar colunas.** Fazem isso Dromo, OneSchema e Ingestro.
  - https://changelog.dromo.io/column-matching-is-skipped-if-all-headers-match-exactly
  - https://www.oneschema.co/blog/advanced-csv-import-features (404 na leitura; vale o resumo da busca)

## 2. Envio do arquivo

- **Mostrar arrastar e clicar juntos.** A Smashing recomenda uma área tracejada com um botão "enviar" dentro dela. Também recomenda instruções com menos de 100 palavras e uma opção de digitar à mão, para quem tem poucos dados.
  - https://smashingmagazine.com/2020/12/designing-attractive-usable-data-importer-app/
- **Oferecer planilha modelo para baixar.** O Dromo usa `templateDownloadFilename`; a Ingestro, `disableTemplates`; e o CSVBox recomenda um modelo com cabeçalhos e linhas de exemplo.
  - https://developer.dromo.io/settings/
  - https://docs.ingestro.com/sdk/settings
- **Perguntar se a primeira linha tem os nomes das colunas.** A Smashing recomenda; o Dromo tem `headerRowOverride`.
- **Assim que a planilha for lida, dizer o tamanho.** O exemplo do saasui é "4,812 rows detected" (4.812 linhas encontradas), antes de gravar qualquer coisa. Ele também recomenda oferecer colar dados e baixar modelo.
  - https://www.saasui.design/blog/saas-data-import-mapping-ux-patterns
- **Limite de linhas.** O Dromo avisa e descarta o que passar de `maxRecords`; a Ingestro bloqueia quem passa de `maxEntries`.

## 3. Ligar as colunas e criar campo novo

**Como as sugestões aparecem**
- **Coluna da planilha à esquerda, campo do sistema à direita, com um valor de exemplo.** A Smashing mostra isso no ClickUp. O saasui descreve "their column, an arrow, your field, with a sample value" (a coluna deles, uma seta, o seu campo, um valor de exemplo).
- **O Flatfile agrupa as colunas por situação**: recomendadas, ligadas antes, sem ligação, iguais e vazias. Ele destaca o que ainda precisa de atenção.
  - https://flatfile.com/product/mapping/
- **No Flatfile, passar o mouse mostra exemplos da coluna e a descrição do campo.** Também há um botão para desfazer todas as sugestões de uma vez.
  - https://support.flatfile.com/articles/8569925090-mapping-data
- **A Ingestro tenta ligar em camadas**: nome igual, depois o que foi feito antes, depois a IA, por fim nome parecido (confiança mínima de 0,6).
  - https://docs.ingestro.com/sdk/settings
- **A ferramenta lembra o que foi ligado da última vez.** O Dromo faz isso com `autoMapHeaders`; o CSVBox recomenda salvar a ligação como modelo.

**Coluna que não bate com nenhum campo**

O saasui resume as três saídas: "map it to a field, create a new custom field, or skip it" (ligar a um campo, criar um campo novo ou não importar). A Smashing recomenda três botões: "Confirm mapping" (confirmar), "Ignore this column" (não usar) e "Include as a custom field" (criar campo).

| Produto | Como trata a coluna desconhecida |
|---|---|
| Flatfile | Se ninguém ligar, a coluna fica de fora: "excluded from the import". Opção "Add as New Field" vira coluna nova na revisão. |
| Dromo | Com `allowCustomFields`, a pessoa cria o campo. `suggestCustomFirst` põe "Add custom field" no topo da lista. |
| Ingestro | `allowCustomColumns` cria coluna nova, mas só vale para aquela importação. |
| Attio | "+ Create new attribute" dentro da própria lista de campos. https://attio.com/help/reference/imports-exports/csv-imports/import-data-into-attio-via-csv |
| HubSpot | "Create a new property" abre um painel lateral. https://knowledge.hubspot.com/crm-setup/import-objects |
| Pipedrive | "If a field doesn't exist, add a custom field" (se o campo não existe, crie um). |
| Insycle | Coluna sem ligação ganha um ícone de alerta e precisa ser ligada à mão. https://support.insycle.com/hc/en-us/articles/6586816077847 |

Nenhum deles, nas fontes que li, pede uma descrição do campo novo. No Chat2You a descrição é obrigatória porque a IA do CRM depende dela, e esse é um ponto em que podemos fazer diferente.

**Valores de lista (por exemplo, "São Paulo" e "SP")**
- **O Flatfile abre uma tela separada para ligar cada valor.** Valor desconhecido tem duas saídas:
  - "Keep this value as is" (manter como está), que acrescenta o valor como nova opção da lista;
  - "Do not import" (não importar), que esvazia só aquela célula.
- **A Ingestro usa a IA para ligar as opções da lista.**

**Pessoa, empresa e negócio na mesma planilha**

Esta é a parte mais próxima da nossa "Base de clientes".
- **O HubSpot faz em uma planilha só.** A pessoa escolhe os tipos de registro, diz para cada um se é para "criar e atualizar", "só criar" ou "só atualizar", e liga cada coluna ao campo do tipo certo. Uma coluna em comum liga os registros entre si. Contatos são reconhecidos pelo e-mail e empresas pelo domínio do site.
  - https://knowledge.hubspot.com/import-and-export/import-objects
- **O Attio separa.** Pessoa é reconhecida pelo e-mail e empresa pelo domínio, e ele recomenda uma importação por tipo de registro.
- **O Pipedrive exige que negócio tenha pessoa ou empresa ligada.** Se o negócio vier sem título, ele monta um com o nome da pessoa ou da empresa.

## 4. Revisão, erros e correção na hora

- **Linha com problema fica em vermelho, com um filtro "só linhas com problema".** A Smashing recomenda as duas coisas.
- **Separar dois tipos de aviso.** Na Smashing, o ClickUp usa laranja para "a coluna bate, mas o valor não é um dos nossos"; o vermelho fica para dado obrigatório faltando.
- **O Dromo tem quatro recursos na revisão:**
  - um painel para pular de erro em erro (`enableNavigatingErrors`);
  - destaque das células corrigidas automaticamente (`highlightAutoFixes`);
  - pedidos de transformação feitos pela própria pessoa (`enableUserTransformations`);
  - permissão para acrescentar ou apagar linhas.
- **O OneSchema corrige em lote.** Tem correção automática, sugestões, localizar e substituir, filtro de erros e Excel com os erros marcados para baixar.
- **O que fazer com linhas que têm erro.** Três ferramentas oferecem as mesmas três escolhas: travar o envio, enviar sem as linhas com erro, ou enviar tudo assim mesmo.
  - Dromo: `invalidDataBehavior`, com `BLOCK_SUBMIT`, `REMOVE_INVALID_ROWS` (o padrão) e `INCLUDE_INVALID_ROWS`;
  - Ingestro: `completeImportAction`;
  - saasui: "import the valid rows now and handle the rest separately" (importar as linhas boas agora e cuidar do resto depois).
- **Escrever o erro para quem não é técnico** (CSVBox):
  - ruim: "Field email failed regex validation";
  - bom: "Please enter a valid email like…", com um exemplo;
  - travar só o erro grave e deixar os avisos passarem.
  - https://blog.csvbox.io/csv-errors-nontechnical/
  - https://blog.csvbox.io/validate-csv-before-db/
- **Dar um arquivo com as linhas que falharam.** O Pipedrive gera um arquivo com o motivo de cada falha, para corrigir e importar de novo; o CSVBox recomenda o mesmo.

## 5. Repetidos, confirmação e desfazer

- **Perguntar sobre repetidos com o número na frente.** O exemplo do saasui é "340 of these rows match existing contacts — update them, or skip?" (340 já existem: atualizar ou pular?). O Attio também pergunta. Campo em branco na planilha não apaga o que já existe, e só os campos ligados mudam.
- **Pipedrive com repetido**: oferece juntar os dois registros. Em campo de várias opções, a pessoa escolhe substituir ou somar.
- **Fechar com um resumo**: criados, atualizados, pulados e com erro. Importação grande roda em segundo plano, com barra de progresso de verdade (saasui).
- **Desfazer a importação:**
  - O Pipedrive desfaz em até 48 horas, pelo histórico, mas só administrador geral pode.
  - O HubSpot não tem botão de desfazer. Dá para filtrar e apagar o que uma importação criou. Valor sobrescrito só volta no plano Enterprise, em até 14 dias.
  - https://knowledge.hubspot.com/import-and-export/view-and-analyze-previous-imports

## 6. O que levar para um usuário leigo (QI 70)

Isto é a minha síntese a partir dos padrões acima, não regra de nenhum fornecedor.

1. **Quatro telas com nome de ação.** Enviar planilha → Conferir colunas → Ver como fica → Pronto. Mostrar as etapas no topo, ter "Voltar" e salvar o andamento (NN/g).
2. **Começar pronto.**
   - Ligar tudo automaticamente e lembrar o que foi feito da última vez.
   - Pular a tela de colunas quando tudo bater.
   - Na tela de colunas, mostrar primeiro só o que precisa de atenção, como o agrupamento do Flatfile, escrito em frase curta: "3 colunas precisam de você".
3. **Um cartão por coluna, nunca uma tabela técnica.** O cartão mostra o nome da coluna e 2 ou 3 exemplos reais, seguidos da pergunta "Isso é sobre…" com três botões grandes: **a pessoa**, **a empresa**, **a venda/negócio**. Depois vem "Guardar em: [campo] · Alterar". O HubSpot faz a mesma divisão por tipo de registro, mas escondida numa lista; aqui ela vira três botões. Se a resposta for "negócio", perguntar em seguida: "Guardar também na ficha da pessoa? Sim / Não".
4. **Coluna desconhecida: três saídas em botão** (padrão Smashing/saasui): "Usar campo que já existe", "Criar campo novo", "Não usar". Criar campo novo pede só duas coisas:
   - **Nome**, já sugerido a partir do cabeçalho;
   - **"Para que serve?"**, já escrito a partir das amostras, com o botão "Alterar". É essa descrição que o CRM usa para preencher o campo lendo as conversas.

   Diferente da Ingestro, o campo criado tem que ficar na conta e aparecer na ficha do contato, e não valer só para aquela importação.
5. **Valores de lista numa mini-tela à parte**, como o Flatfile faz: "‘Sao Paulo’ é o mesmo que ‘SP’? Sim / Manter como está / Deixar em branco".
6. **Erros escritos como conversa** (CSVBox). Exemplo: "12 clientes estão sem telefone. Corrigir agora · Importar sem eles".
   - Corrigir dentro da própria tela, com um botão "Próximo problema" (como o painel do Dromo).
   - Marcar as correções automáticas com uma cor suave (como `highlightAutoFixes`).
   - Por padrão, importar as linhas boas e oferecer a planilha das que ficaram de fora, como o arquivo de falhas do Pipedrive.
   - Não usar "regex", "campo obrigatório", "inválido", "registro" nem "objeto".
7. **Prévia antes de gravar.** Usar o número grande e mostrar 3 fichas de exemplo como ficarão: "Vamos criar 1.240 clientes, atualizar 340 e deixar 12 de fora". Quem já existe é reconhecido pelo telefone; para o WhatsApp esse é o equivalente ao e-mail do HubSpot e do Attio. Perguntar "Atualizar quem já existe?" com dois botões.
8. **Desfazer sem medo.** Um botão "Desfazer esta importação" no resumo e no histórico, por tempo limitado, como os 48 horas do Pipedrive. Ninguém que li dá esse botão para quem não é administrador, então seria um diferencial nosso. Fazer melhor que o HubSpot e guardar o valor antigo dos campos sobrescritos.
9. **Não citar IA na interface.** Em vez de "Mapeamento automático", escrever "Já arrumamos as colunas para você. Confira."

## Fontes

- https://smashingmagazine.com/2020/12/designing-attractive-usable-data-importer-app/
- https://www.nngroup.com/articles/wizards/
- https://developer.dromo.io/settings/
- https://changelog.dromo.io/column-matching-is-skipped-if-all-headers-match-exactly
- https://flatfile.com/product/mapping/
- https://support.flatfile.com/articles/8569925090-mapping-data
- https://support.flatfile.com/articles/7763163677-importing-data-with-flatfile-overview
- https://docs.ingestro.com/sdk/settings
- https://docs.ingestro.com/sdk/overview/
- https://www.oneschema.co/blog/advanced-csv-import-features (404 na leitura; uso só o resumo da busca)
- https://blog.csvbox.io/csv-errors-nontechnical/
- https://blog.csvbox.io/validate-csv-before-db/
- https://blog.csvbox.io/ai-feedback-user-import-errors/
- https://www.saasui.design/blog/saas-data-import-mapping-ux-patterns
- https://knowledge.hubspot.com/import-and-export/import-objects
- https://knowledge.hubspot.com/crm-setup/import-objects
- https://knowledge.hubspot.com/import-and-export/view-and-analyze-previous-imports
- https://support.pipedrive.com/en/article/importing-data-into-pipedrive-with-spreadsheets
- https://attio.com/help/reference/imports-exports/csv-imports/import-data-into-attio-via-csv
- https://support.insycle.com/hc/en-us/articles/6586816077847


## mercado: ux-leigo

## Pesquisa: UX para quem lê pouco e usa pouco o digital, aplicada a Relacionamentos e à Base de clientes

### 1. Dados que justificam desenhar para QI 70 e baixo letramento

**Brasil, Inaf 2024** (pesquisa de dez/2024 a fev/2025, 2.554 pessoas de 15 a 64 anos):
- 29% são analfabetos funcionais, cerca de 40 milhões de pessoas. É o mesmo índice de 2018.
- Entre quem trabalha, 27% são analfabetos funcionais, 34% ficam no nível elementar e só 40% têm leitura consolidada.
- O Inaf aplicou uma prova digital no celular. Uma das tarefas era preencher um formulário de inscrição. No grupo que acertou até 1/3 das tarefas:
  - 71% eram analfabetos funcionais;
  - 46% tinham entre 50 e 64 anos;
  - 27% tinham ensino médio completo. Ou seja, diploma não garante habilidade digital.
- Fontes: [UNICEF](https://www.unicef.org/brazil/comunicados-de-imprensa/analfabetismo-funcional-nao-apresenta-melhora-e-alcanca-29-por-cento-dos-brasileiros-mesmo-patamar-de-2018-aponta-novo-levantamento-do-inaf) e [relatório Inaf 2024 (PDF)](https://static.poder360.com.br/2025/08/dados-inaf-2024.pdf), seções "Alfabetismo e trabalho" e "Alfabetismo no contexto digital".

**Brasil, TIC Domicílios 2024** ([resumo executivo, Cetic.br](https://cetic.br/media/docs/publicacoes/2/20250512115624/tic_domicilios_2024_resumo_executivo.pdf)):
- 60% dos usuários de internet acessam só pelo celular. A leitura que fiz do Gráfico 1 dá cerca de 81% entre quem tem ensino fundamental e cerca de 86% nas classes DE. São valores aproximados.
- Só 45% usam copiar e colar. Só 19% já usaram fórmula em planilha.
- 34% da população está no nível mais baixo de "conectividade significativa". Nesse grupo, só 4% já criaram uma apresentação de slides, contra 38% no nível mais alto.
- 92% enviaram mensagens instantâneas. O canal que o cliente domina é a conversa.

**Exterior, NN/g** ([Writing for lower-literacy users](https://www.nngroup.com/articles/writing-for-lower-literacy-users/)):
- O comportamento observado é este:
  - leem palavra por palavra e não "passam o olho";
  - escolhem a primeira opção que parece servir;
  - pulam texto denso;
  - perdem o ponto onde estavam quando a página rola.
- Num estudo, o site foi reescrito para esse público. Entre os leitores com baixo letramento, o sucesso subiu de 46% para 82% e o tempo caiu de 22,3 para 9,5 minutos. Os bons leitores também melhoraram, de 68% para 93%.

**Lacuna:** a TIC Empresas não traz dado sobre habilidade digital de microempresa nos trechos que consegui ler. Não encontrei número confiável sobre o dono de pequeno negócio especificamente.

### 2. Regras verificáveis, com a origem de cada uma

**Linguagem**
- **L1.** Frases em ordem direta, curtas, com uma ideia por frase e na voz ativa. Usar verbo, não substantivo: "Importar clientes", e não "Importação de base". Fonte: [Lei 15.263/2025, art. 5º](https://www.lex.com.br/lei-no-15-263-de-14-de-novembro-de-2025/), incisos I, II, III, XII e XIV.
- **L2.** Nenhum termo técnico sem tradução. "Campo personalizado" vira "informação". "Atributo" vira "informação". "Mapear coluna" vira "O que tem nesta coluna?". "Funil" e "card" viram "negócio". Fonte: art. 5º, incisos IV e V. Como checar: lista de palavras proibidas revisada no PR.
- **L3.** O mais importante vem primeiro, nas telas de detalhe e no topo da página. Fonte: art. 5º, inciso X, e [NN/g](https://www.nngroup.com/articles/writing-for-lower-literacy-users/), "informação principal no topo".
- **L4.** Texto no nível de leitura do 6º ano nas telas de entrada e do 8º ano nas demais. Fonte: [NN/g](https://www.nngroup.com/articles/writing-for-lower-literacy-users/).
- **L5.** Testar o texto com o público, por exemplo com 3 a 5 donos de negócio reais antes de liberar. Fonte: art. 5º, inciso XVIII.

**Estrutura da jornada da Base de clientes**
- **J1.** Uma coisa por página: cada tela traz uma pergunta ou uma decisão. Fontes: [GOV.UK, form structure](https://www.gov.uk/service-manual/design/form-structure) e [question pages](https://design-system.service.gov.uk/patterns/question-pages/).
  - O título da tela é a própria pergunta: "Esta coluna fala de quem?".
  - As três respostas: Pessoa, Empresa, Negócio.
  - A tela seguinte: "Guardar também na ficha da pessoa?" Sim ou Não.
- **J2.** Botão principal "Continuar", e não "Próximo". O botão Voltar do navegador leva à tela anterior com as respostas mantidas. Fontes: [GOV.UK question pages](https://design-system.service.gov.uk/patterns/question-pages/) e [W3C COGA](https://www.w3.org/TR/coga-usable/), padrão 4.5.2.
- **J3.** Nunca pedir de novo um dado já informado. Preencher sozinho ou oferecer para escolher. Fontes: [WCAG 2.2, critério 3.3.7](https://www.w3.org/WAI/standards-guidelines/wcag/new-in-22/) e [gov.br, Simplificação de formulários](https://www.gov.br/governodigital/pt-br/estrategias-e-governanca-digital/transformacao-digital/ferramentas/simplificacao_de_formularios.pdf), prática 6.
- **J4.** Mostrar antes de fazer: uma tela de conferência antes de importar. Fonte: [GOV.UK check answers](https://design-system.service.gov.uk/patterns/check-answers/).
  - Dividir em blocos "Pessoa", "Empresa" e "Negócio".
  - Cada bloco tem um "Alterar" visível, que abre a pergunta já preenchida e volta direto para a conferência.
  - O botão final diz a ação: "Importar 312 clientes".
- **J5.** Indicador de progresso só se for necessário, e em texto simples: "Passo 2 de 4". O total precisa ser confiável. Fonte: GOV.UK question pages.
- **J6.** Começar pelo caso mais comum: modelo pronto e colunas já reconhecidas. Perguntar só o que ficou em dúvida. Fontes: GOV.UK form structure ("priorize os cenários mais comuns" e "perguntas condicionais") e [NN/g, Wizards](https://www.nngroup.com/articles/wizards/) ("defaults" com as escolhas anteriores).
- **J7.** Guardar o progresso e deixar terminar depois. Não perder trabalho por tempo esgotado. Fontes: [NN/g, Wizards](https://www.nngroup.com/articles/wizards/), "salvar e retomar", e [COGA 4.5.9](https://www.w3.org/TR/coga-usable/).
- **J8.** Cada pergunta diz por que está sendo feita, em uma frase curta, sem link. Aceitar "Não sei" quando fizer sentido, por exemplo "Não sei, pular esta coluna". Fonte: GOV.UK question pages (regras de hint e "Não sei").
- **J9.** Criar uma informação nova pede nome e descrição em tela própria. A dica explica para que serve a descrição: "Explique com suas palavras. Isso ajuda a preencher sozinho lendo as conversas". A dica não cita "IA". Fonte: GOV.UK question pages, "deixe claro por que pergunta" e dica em uma frase.

**Página de Relacionamentos (lista e ficha)**
- **P1.** Uma coluna principal e navegação linear. Nada de layout em várias colunas na entrada. Fontes: [NN/g](https://www.nngroup.com/articles/writing-for-lower-literacy-users/) e gov.br Simplificação de formulários, práticas 1 e 3.
- **P2.** No primeiro nível, só o que se usa sempre: buscar, abrir a ficha, adicionar e importar. Todo o resto fica num segundo nível com rótulo claro, por exemplo "Mais opções". No máximo 2 níveis. Fonte: [NN/g, Progressive disclosure](https://www.nngroup.com/articles/progressive-disclosure/).
- **P3.** Estado vazio com 1 frase e 1 botão, que leva direto à tarefa: "Você ainda não tem clientes aqui." e o botão "Trazer minha lista". Nunca mostrar "sem registros" enquanto a tela carrega. Fonte: [NN/g, Empty states](https://www.nngroup.com/articles/empty-state-interface-design/).
- **P4.** Todo ícone com texto visível, sem depender de passar o mouse. Fonte: [NN/g, Icon usability](https://www.nngroup.com/articles/icon-usability/), frase original "Icon labels should be visible at all times".
- **P5.** A ficha do contato mostra as informações criadas na Base, com nome e valor. Informação vazia aparece como "Não informado", não some. Fonte: GOV.UK check answers ("Not provided").
- **P6.** Busca que tolera erro de digitação, com o melhor resultado em primeiro lugar. Fonte: [NN/g](https://www.nngroup.com/articles/writing-for-lower-literacy-users/), item 7.
- **P7.** Pensar primeiro no celular. A maioria do público acessa só pelo celular (ver seção 1). Nada de arrastar como única forma de agir. Fontes: [WCAG 2.5.7](https://www.w3.org/WAI/standards-guidelines/wcag/new-in-22/) e TIC Domicílios 2024.
- **P8.** Nada de texto em movimento nem menus que abrem sozinhos ao passar o mouse. Fonte: NN/g, item 4.

**Erros e segurança**
- **E1.** O erro aparece junto do campo e também resumido no topo. As respostas ficam mantidas. A mensagem diz como resolver. Fonte: [GOV.UK, Error message](https://design-system.service.gov.uk/components/error-message/).
  - Bom exemplo: "Escolha de quem é esta coluna".
  - Evitar: "inválido", "ops", "desculpe", "por favor", "Ocorreu um erro" e "Campo obrigatório".
- **E2.** Desfazer depois de importar, ou pelo menos um aviso claro antes do passo que não tem volta. Fonte: [COGA](https://www.w3.org/TR/coga-usable/), 4.5.5 e 4.5.11.
- **E3.** Campo opcional marcado com "(opcional)". Nunca usar asterisco. Fonte: GOV.UK question pages.
- **E4.** Não exigir conta, número ou memória. Mostrar o exemplo real da planilha, como "Coluna B: Maria, João, Ana…", em vez de "Coluna B". Fonte: [COGA 4.7.5](https://www.w3.org/TR/coga-usable/), "não depender de memória nem de cálculo".

**Acessibilidade mínima**
- **A1.** Área de toque de pelo menos 24×24 px, que é o mínimo do [WCAG 2.5.8](https://www.w3.org/WAI/standards-guidelines/wcag/new-in-22/). Sua regra interna exige 44 px e é mais forte, então ela prevalece.
- **A2.** O elemento com foco nunca fica escondido por barra fixa ou rodapé. Fonte: WCAG 2.4.11.
- **A3.** A ajuda fica sempre no mesmo lugar, em todas as telas da jornada. Fonte: WCAG 3.2.6.
- **A4.** Nada de `<select>` nativo. Escolha entre 2 e 4 opções aparece como cartões ou botões de rádio grandes. Lista longa usa o ChoiceSelect. A regra é sua. A pesquisa reforça a escolha de opções visíveis, porque esse público lê cada opção em vez de escanear (NN/g).

**Lista de tarefas, só se a jornada ficar longa**
- **T1.** Se a Base de clientes passar de cerca de 4 passos ou puder ser feita em várias sessões, usar uma lista de tarefas com verbos ("Enviar planilha", "Conferir colunas", "Revisar e importar"). Status com no máximo 2 palavras simples ("Feito", "Falta fazer"). Vermelho só para erro. Antes disso, tentar reduzir os passos. Fonte: [GOV.UK, Complete multiple tasks](https://design-system.service.gov.uk/patterns/complete-multiple-tasks/).

### 3. O que fica de fora do primeiro nível
Segundo o [NN/g sobre wizards](https://www.nngroup.com/articles/wizards/), o passo a passo serve para tarefa rara e usuário iniciante. Para tarefa repetida, como editar a ficha várias vezes, é melhor um formulário direto. Na prática:
- **Importar a Base** usa passo a passo.
- **Editar o contato** usa a ficha com "Alterar" em cada bloco.

### 4. Limites desta pesquisa
- O site do design system do governo (gov.br/ds) é uma aplicação que a ferramenta de leitura não conseguiu abrir. Usei o [guia gov.br de Simplificação de formulários](https://www.gov.br/governodigital/pt-br/estrategias-e-governanca-digital/transformacao-digital/ferramentas/simplificacao_de_formularios.pdf), com 13 boas práticas, e a notícia da [versão 4.0 no Serpro](https://www.serpro.gov.br/menu/noticias/noticias-2024/design-system-4.0). Não confirmei as regras dos componentes do gov.br/ds.
- O texto do art. 5º da Lei 15.263 veio da cópia publicada no [Lex](https://www.lex.com.br/lei-no-15-263-de-14-de-novembro-de-2025/). O site do [Planalto](https://www.planalto.gov.br/ccivil_03/_Ato2023-2026/2025/Lei/L15263.htm) não respondeu.
- Os percentuais por escolaridade e classe da TIC Domicílios saíram da leitura do gráfico. O texto do resumo só confirma o total de 60% de acesso só pelo celular.


## mercado: premium-lgpd

# Pesquisa de mercado: Relacionamentos e Base de clientes

## Frente 1: design premium em páginas de cliente e listas

### Resumo do que cada produto faz (com fonte)

**Attio**
- A página de um registro (pessoa, empresa ou negócio) tem quatro partes:
  - **Topo:** botões de ação, que o administrador pode reordenar. Para pessoa: escrever e-mail, pôr numa lista, nota, tarefa, rodar automação.
  - **Destaques:** no alto da aba Visão geral, até 6 cartões com os campos que importam. No negócio, o exemplo é etapa, valor, pessoas ligadas e empresa.
  - **Coluna lateral à esquerda:** "Record Details" (obrigatória; mostra os 5 primeiros campos quando ninguém configurou) e as listas onde o registro está.
  - **Abas de relacionamento:** mostram registros ligados, como a equipe da empresa, a empresa da pessoa, e as pessoas e a empresa do negócio.
- A configuração vale por tipo de registro e só o administrador mexe.
- Fontes:
  - https://attio.com/help/reference/managing-your-data/records/configure-record-pages
  - https://attio.com/help/academy/introduction/record-pages
  - https://attio.com/help/reference/attio-101/attios-data-model/understanding-records
- Em ago/2025 a Attio redesenhou a edição em linha dos campos (seleção, local, domínio, e-mail, telefone, texto) "para ver e alterar com menos cliques". Em abr/2025 refez a linha do tempo de alterações. Fontes: https://attio.com/changelog/changelog-august-14-2025 e https://attio.com/changelog/changelog-april-15-2025
- **Importação da Attio** (é a referência mais próxima da Base de clientes):
  - Cada importação vai para um tipo de registro só. Planilha misturada é dividida: uma importação para Pessoas e outra para Negócios.
  - O campo novo é criado na própria tela de ligar colunas ("+ Create new attribute").
  - A chave contra duplicata é o e-mail (pessoa) e o domínio (empresa).
  - Pergunta se atualiza o registro existente ou cria outro.
  - Célula vazia não apaga dado que já existe.
  - Há "Review values" e "Preview import" antes de rodar.
  - Fonte: https://attio.com/help/reference/imports-exports/csv-imports/import-data-into-attio-via-csv
- **Campos preenchidos sozinhos (Attio):** o campo tem nome, prompt e descrição opcional. Se não acha valor, fica em branco e não cobra. Fonte: https://attio.com/help/reference/attio-ai/ai-attributes

**HubSpot** (incumbente, entrou como referência de importação e de campos preenchidos sozinhos)
- Importa vários tipos de registro de um arquivo só: contatos, empresas e negócios, já ligados entre si. É o oposto da Attio, que separa por tipo. Fonte: https://knowledge.hubspot.com/import-and-export/understand-the-import-tool
- Os "smart properties" geram a instrução a partir do nome e do tipo do campo. Antes de salvar, mostram uma prévia do resultado num registro real. Fonte: https://knowledge.hubspot.com/properties/create-smart-properties

**Stripe (página do cliente)**
- Duas colunas. A principal, à esquerda, tem o que muda: pagamentos, faturas, assinaturas. A secundária, à direita, tem o que é fixo: dados e metadados.
- Foi movida para a direita justamente para dar foco ao que muda.
- As ações mais usadas ficaram no cabeçalho ("Create payment", "Create invoice").
- Assinaturas canceladas passaram a aparecer na lista por padrão, sem ficar atrás de um botão.
- Fontes: https://support.stripe.com/questions/updates-to-the-customer-detail-page e https://docs.stripe.com/stripe-apps/patterns/full-page-apps.md

**Shopify (página do cliente)**
- Seções: resumo do cliente (contato, com menu "Manage"), nota interna, linha do tempo (inclui e-mails enviados, com aviso quando falhou), tags e situação de marketing.
- A situação de marketing é registrada por canal: e-mail, SMS e WhatsApp.
- Fonte: https://help.shopify.com/en/manual/customers/manage-customers
- A API de consentimento guarda o tipo de opt-in (CONFIRMED_OPT_IN, SINGLE_OPT_IN, UNKNOWN), seguindo boas práticas M3AAWG. Fonte: https://shopify.dev/docs/api/admin-graphql/latest/enums/CustomerMarketingOptInLevel
- Ferramentas de importação avisam para não marcar "aceita marketing" em massa sem consentimento real. Fonte: https://www.highviewapps.com/kb/update-your-customers-email-marketing-status/
- Não achei um redesign oficial da página do cliente em 2025.

**Linear (refresh de mar/2026)**
- Princípios descritos pelo próprio time:
  - "Não dispute atenção que não conquistou": a navegação recua e o conteúdo se destaca.
  - Barra lateral um pouco mais escura.
  - Menos ícones, e menores.
  - "A estrutura deve ser sentida, não vista": divisórias suaves; separador sem função sai.
  - Ações sempre no mesmo lugar do cabeçalho.
  - Cinza mais quente.
  - Lançado aos poucos, atrás de flag.
- Fontes: https://linear.app/blog/behind-the-latest-design-refresh e https://linear.app/changelog/2026-03-12-ui-refresh

**Notion (layout de página de banco de dados)**
- Até 15 campos fixados logo abaixo do título.
- Painel de detalhes à direita.
- Área principal para conteúdo longo.
- Busca por nome de campo, que acha inclusive campos ocultos.
- Fonte: https://www.notion.com/help/layouts

**Intercom**
- Achei só o perfil atual: conteúdo recente à direita, atributos, tags e segmentos. Fonte: https://intercom.com/help/en/articles/6988783-get-context-fast-with-user-and-company-profiles
- Não achei redesign em 2025.

**Superhuman:** não pesquisei a fundo. Nada a citar com fonte.

### Padrões que se repetem, aplicados ao Chat2You
O que segue é interpretação minha a partir das fontes acima.
1. **Uma tela para pessoa, empresa e negócio.**
   - No alto, o nome e uma faixa de até 6 destaques, como na Attio. Para pequena empresa: etapa do negócio, valor, último contato e de onde veio.
   - No meio, o que muda: conversas e negócios, como na coluna principal do Stripe.
   - Ao lado, o que é fixo: dados da pessoa, a empresa e os campos.
   - Empresa e negócios aparecem como cartões ligados, não como abas escondidas.
2. **As ações principais ficam no cabeçalho e sempre no mesmo lugar** (Stripe e Linear). Para QI 70: um botão principal ("Conversar") e o resto em "Mais".
3. **Edição dentro da própria página com 1 clique** (Attio 2025). O botão "Alterar" fica visível, sem precisar passar o mouse em cima.
4. **Menos peso visual:** divisórias suaves, navegação mais apagada, poucos ícones (Linear).
5. **Prévia antes de gravar** (Attio "Preview import", HubSpot "Preview result"). Isso confirma a regra "mostrar antes de fazer".
6. **Na Base de clientes, o campo é criado na própria tela de ligar colunas** (Attio). Nome e descrição ali mesmo, com prévia do valor num cliente real (HubSpot).
7. **Para quem vai cada coluna:** a Attio separa por tipo de registro e o HubSpot aceita tudo num arquivo. A ideia de perguntar "esta coluna é da pessoa, da empresa ou do negócio?" vai pelo caminho do HubSpot, mas mais simples.
8. **Duplicata:** chave clara (telefone e e-mail no nosso caso), a pergunta "atualizar ou criar?" e célula vazia não apaga dado (Attio).

## Frente 2: LGPD e WhatsApp para base importada

### O que diz a lei
LGPD, texto conferido em https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2018/lei/l13709.htm
- **Art. 7º, I e IX:** as duas bases possíveis são consentimento e legítimo interesse ("exceto no caso de prevalecerem direitos e liberdades fundamentais do titular").
- **Art. 8º, §2º:** "Cabe ao controlador o ônus da prova de que o consentimento foi obtido". Ou seja, é preciso guardar a prova.
- **Art. 8º, §5º:** o consentimento pode ser revogado "a qualquer momento", por "procedimento gratuito e facilitado".
- **Art. 10:** o legítimo interesse vale só para "situações concretas". O inciso II pede respeito às "legítimas expectativas" do titular.
- **Art. 10, §1º:** usar "somente os dados pessoais estritamente necessários".
- **Art. 10, §2º:** dever de transparência.
- **Art. 18, §2º:** o titular pode se opor ao tratamento feito sem consentimento.
- **Art. 37:** manter "registro das operações de tratamento [...], especialmente quando baseado no legítimo interesse". Isso apoia guardar a origem de cada contato importado.

### ANPD
- O Guia Orientativo de Legítimo Interesse saiu em 02/02/2024 (v1.0, 52 páginas).
- O teste de balanceamento tem três fases: finalidade, necessidade e balanceamento. O modelo do teste é recomendado, não obrigatório.
- Não consegui ler o PDF (a cópia do TCE-PB tinha só a capa). O resumo vem de fontes secundárias:
  - https://www.mattosfilho.com.br/unico/anpd-legitimo-interesse-lgpd/
  - https://confidata.com.br/blog/legitimo-interesse-lgpd-lia-exemplos-limites
  - glossário oficial: https://www.gov.br/anpd/pt-br/centrais-de-conteudo/materiais-educativos-e-publicacoes/glossario-anpd/l
- Segundo essas fontes secundárias, o guia dá como exemplo adequado mandar oferta de produto complementar a cliente que já compra. Não é o caso de lista comprada.
- Legítimo interesse não vale para dado sensível.
- **Precedente:** a primeira multa da ANPD foi de R$ 14,4 mil a uma empresa que oferecia disparo em massa por WhatsApp com lista de contatos sem base legal. A data não foi confirmada na fonte. https://convergenciadigital.com.br/governo/primeira-multa-da-anpd-foi-para-disparo-eleitoral-por-celular-e-whatsapp
- Não achei orientação da ANPD específica para WhatsApp nem para base importada. A afirmação de que "consentimento por e-mail não cobre WhatsApp" aparece só em blog de fornecedor, sem fonte primária. Não usar.

### WhatsApp / Meta
Política oficial: https://whatsappbusiness.com/pt-br/policy/
- **Seção 1:** só contatar quem deu o número e recebeu o pedido de opt-in, "confirmando que deseja receber".
- A empresa "é a única responsável por determinar o método de adesão" e deve "assegurar que forneceu avisos e obteve as permissões".
- Deve "respeitar todas as solicitações (dentro e fora do WhatsApp)" de quem quer bloquear.
- Proibido "surpreender" ou mandar spam.
- **Boas práticas:** opt-in separado por categoria de mensagem e instrução clara de como sair.
- A política **não fala de lista importada**: não autoriza nem proíbe. O que vale é ter o opt-in.
- **Mensagem iniciada pela empresa:** só com modelo aprovado. Opt-in sem consentimento leva a bloqueios e pode suspender a conta. Fontes secundárias:
  - https://docs.360dialog.com/docs/guides/best-practices
  - https://www.infobip.com/en/blog/how-to-collect-whatsapp-business-opt-ins
- **Botão de sair do marketing:** há um botão opcional nos modelos de marketing. Bloqueio alto derruba a qualidade do número. Fonte só de fornecedor, conferir na documentação da Meta: https://support.qiscus.com/hc/en-us/articles/13766924007577
- Desde 2025, o usuário escolhe que tipo de mensagem de empresa quer receber: https://tech.yahoo.com/general/articles/whatsapp-adding-much-needed-unsubscribe-192505866.html

### O que isso pede do produto
Isto é inferência minha, não é parecer jurídico.
1. **Guardar a origem de cada contato importado** (art. 37 e §2º do art. 8º): arquivo, data, quem importou e a resposta à pergunta "de onde vieram esses clientes?". Opções: já são meus clientes, se cadastraram, outro. Pode virar uma pergunta de 1 clique na prévia.
2. **Guardar a permissão por canal** (WhatsApp, e-mail), em três estados: sim, não, não sei. Seguir o modelo Shopify, que também registra o tipo de opt-in. Padrão do importado = "não sei", nunca "sim".
3. **Sair fácil e respeitado em todo lugar** (art. 18 §2º, art. 8º §5º, Seção 1 da Meta). Quem pediu para sair fica marcado e não entra em envio de marketing.
4. **Aviso curto, sem juridiquês**, antes de usar a base para marketing: "Só mande ofertas para quem já é seu cliente ou deixou você mandar."
5. **Dado sensível** (CPF/RG em seguro, por exemplo) não se apoia em legítimo interesse. A memória do projeto diz que esse dado é necessário ao negócio; o produto precisa tratar a base legal disso, não restringir o dado.

## Lacunas
- O PDF oficial do guia da ANPD não foi lido. Os trechos do guia vêm de resumos.
- Não há confirmação primária da Meta sobre o botão de sair do marketing nem sobre contato de lista importada.
- Superhuman e o redesign do Intercom ficaram sem fonte.
- Não há screenshot dos produtos: as descrições de layout vêm de documentação, não de inspeção visual.


## codigo: lacuna-1-Como são as planilhas reais dos clientes (PRD §6 sem resposta)

Nenhuma das 7 perguntas da F0 (`docs/base-de-clientes/PRD.md:150-159`) pode ser respondida com o que existe hoje. Não há nenhum arquivo real de cliente no repositório, e eu não consultei produção: isso exige seu OK e toca dado pessoal. O que encontrei abaixo mostra que boa parte da resposta já está guardada em produção, sem precisar abrir dado de pessoa.

## 1. O que a F0 realmente testou

- A própria `BATERIA-F0.md:7-10` diz que a decisão de 10/10 foi não esperar as 5 planilhas reais. Foram 68 planilhas fictícias, e "nenhum dado é de cliente" (linha 23).
- Os casos que imitam outros sistemas foram escritos por quem fez a bateria. Nenhum foi tirado de um arquivo exportado de verdade (todos em `script/evals/base_de_clientes/casos_dia_a_dia.rb`):
  - Kommo: c18, linhas 51-59;
  - RD: c19, linhas 62-67;
  - Pipedrive, o único com colunas separadas de pessoa, organização e negócio: c20, linhas 70-76;
  - HubSpot: c21, linhas 79-85.
- Também são fictícios os casos de "cliente desde" (texto solto numa coluna de observação, linha 42) e de consentimento (c22, linha 88).
- Não há caso de exportação do Google Contatos nem do WhatsApp Business.
- Atenção: esses arquivos de casos não existem na worktree de pesquisa. Só aparecem em outras worktrees, por exemplo `1282-link-curto-previa`.
- Por isso, nada confirma que o público tenha colunas de empresa ou de negócio. A separação pessoa/empresa/negócio ainda é hipótese.

## 2. O que produção já guarda e responde as perguntas sem expor dado pessoal

Cada importação feita na tabela `campaign_imports` guarda:

| Campo | Onde está no código | Pergunta que ajuda a responder |
|---|---|---|
| `extra_columns`: os cabeçalhos que não viraram nome, celular ou e-mail, escritos como no arquivo (`[{index, key}]`) | `db/schema.rb:1220`, montado em `spreadsheet_reader.rb:204-211` | 1, 2, 3 e 7, pelo nome da coluna; 6, pelo jeito do cabeçalho |
| `schema_resolution`: forma de leitura (Jev, automática ou manual), formato, linha do cabeçalho, colunas de e-mail e nome, `custom_columns` | `db/schema.rb:1221`, montado em `schema_resolver.rb:129-138` | 1 e 6 |
| `total_rows`, `duplicate_file_rows`, `source_format`, `source_byte_size`, `source_filename` | `db/schema.rb:1181-1188` | 4, 5 e 6 |

- Os limites atuais estão em `config.rb:10-19`: 10 MB por arquivo, 50 mil linhas em CSV e 20 mil em XLSX.
- Não usar `campaign_import_rows.extra_values` (`db/schema.rb:1163`). Ali estão os valores de cada pessoa, guardados sem máscara (PRD §5).
- Cuidado com os cabeçalhos: numa planilha sem cabeçalho, a linha lida como cabeçalho pode ser dado de uma pessoa (`BATERIA-F0.md:41-42`). Na consulta, contar só nomes de coluna, juntando várias contas, e descartar os que parecem telefone ou e-mail.
- O arquivo original some em 7 dias (`config.rb:43`). Para olhar 5 a 10 arquivos inteiros, eles teriam de vir direto dos clientes, com autorização deles.

## 3. Formatos de exportação dos sistemas (pesquisa web)

| Sistema | O que confirmei | O que falta confirmar |
|---|---|---|
| Kommo | Uma linha por negócio. Colunas: nome do negócio, empresa, contato principal, empresa do contato, responsável, etapa, valor da venda, criado em/por, modificado em/por, tags, tarefa mais recente, data de encerramento. Até 500 negócios por arquivo. "Contatos e empresas" é outra exportação. A fonte é de 2020 e o link hoje redireciona para uma página que dá 404. | As colunas da exportação de contatos e empresas |
| RD Station CRM | Exporta negociações, empresas e contatos. Desde jul/2024 permite mais de 10 mil negociações em CSV. | A lista de colunas. As do caso c19 não têm fonte. |
| RD Station Marketing | Nenhuma fonte encontrada para as colunas da exportação. | Tudo |
| Google Contatos | Exporta em "CSV do Google" ou vCard. Fontes de terceiros indicam cabeçalhos em inglês: `Given Name`, `Family Name`, `E-mail 1 - Value`, `Phone 1 - Type`, `Phone 1 - Value`, e também `Phone 2` e `Phone 3`. Não traz empresa nem negócio como coluna própria. | A lista exata, numa exportação de teste |
| WhatsApp Business (app) | Não tem exportação oficial de contatos nem de etiquetas. Só extensões de terceiros, sem vínculo com o WhatsApp, pagas e instáveis. | — |

O padrão que aparece: quem vem de um CRM (Kommo, RD, Pipedrive) traz arquivos centrados no **negócio**, com o contato e a empresa como colunas daquele negócio. Quem vem do celular ou do Google traz só a pessoa. Para esse público, a pergunta "o dado do negócio vai também para a pessoa?" só faz sentido para quem vem de um CRM. Isso ainda precisa ser confirmado com dado real.

## 4. Para fechar a lacuna

1. **Consulta em produção, com seu OK.** Só leitura, por psql (SSM + `docker exec psql`, nunca `rails runner`). Contaria:
   - os cabeçalhos mais frequentes em `extra_columns` e em `schema_resolution->'custom_columns'`, juntando todas as contas;
   - a distribuição de `total_rows`, de `duplicate_file_rows / total_rows` e de `source_format`;
   - o nome do arquivo apenas classificado em categorias (kommo, rd, export, contacts), sem mostrar o nome real.
   
   Isso responde a 1, 4, 5 e 6, e parcialmente a 2, 3 e 7.
2. **Arquivos inteiros da conta 16 e de mais 4 a 9 contas**, enviados pelos clientes com autorização, analisados fora do repositório e apagados depois.
3. **Uma exportação de teste em contas de demonstração** do Kommo (negócios e contatos), do RD CRM e do Google Contatos, para guardar os cabeçalhos exatos e trocar os casos c18 e c19, que hoje são inventados.

Fontes:
- [Kommo – exportar dados (2020, redireciona para página 404)](https://www.kommo.com/br/recursos/crm/exportar/)
- [RD Station – preços do CRM](https://www.rdstation.com/precos-crm/)
- [RD Station CRM – novidades de julho/2024](https://www.rdstation.com/blog/vendas/novidades-rd-station-crm-julho-2024)
- [Google – exportar contatos](https://support.google.com/contacts/answer/7199294?hl=pt-BR)
- [Missive – formatos de importação (cabeçalhos Google e Outlook)](https://missiveapp.com/docs/core-features/contacts/importing)
- [nas-forum – formato de importação do Google](https://www.nas-forum.com/forum/topic/74909-format-dimportation)
- [Extensão de terceiros WapiPro (Chrome Web Store)](https://chromewebstore.google.com/detail/hnehikponadjkjkbifpnkcimjhfbgndm)


## codigo: lacuna-2-Contradição sobre o tipo do contato importado (visitante ou lead)

O risco nº 1 do relatório de CRM é **falso**, pelo menos para a importação por planilha. O contato importado é salvo como `lead`, não como `visitor`. Não rodei spec nem consultei produção; a conclusão vem só da leitura do código.

**Por que o contato vira `lead` (worktree `relacionamentos-pesquisa`, HEAD `d987e9dce9`)**

1. O `importer.rb:80` do relatório é `app/services/campaign_imports/importer.rb:80`. Ele cria o contato com `account.contacts.create!(name:, phone_number:, email:)`, sem `insert_all` e sem `update_columns`. Por isso os callbacks do modelo rodam.
2. `app/models/contact.rb:77` tem `before_save :sync_contact_attributes`, sem condição. Ele chama `Contacts::SyncAttributes` (`contact.rb:246-248`).
3. `app/services/contacts/sync_attributes.rb:22-30` troca `visitor` por `lead` quando há e-mail, telefone ou dado social preenchido.
4. Toda linha importada tem telefone ou e-mail válido:
   - Nos fluxos de Públicos e Importar contatos, linha sem nenhum dos dois é recusada como `missing_contact` (`app/services/campaign_imports/audience_row_contacts.rb:3-5,14-15`).
   - No fluxo antigo de base de campanha, a coluna de telefone é obrigatória (`header_mapper.rb:74`).
5. `SuppressedContactEvents` só liga `Current.suppress_contact_events` (`suppressed_contact_events.rb:6-11`). Esse sinal é lido apenas em `dispatch_create_event` e `dispatch_update_event` (`contact.rb:251,257`). Ele não desliga o `before_save`.
6. Com `crm_v2`, a lista mostra `lead` e `customer` (`contact.rb:193`), então o contato importado aparece.

**Contato que já existia na conta**

- Se já tinha telefone ou e-mail, ele já tinha passado por `before_save` e já é `lead`.
- Se era `visitor` sem nenhum dos dois, `ContactBlankFields#fill!` grava o dado da planilha com `contact.update!` (`contact_blank_fields.rb:16-19`). Isso dispara o mesmo `before_save` e ele vira `lead`.

**Limites da conclusão**

- Nenhum spec cobre o `contact_type` na importação. `spec/services/campaign_imports/` não testa isso; só `spec/services/contacts/sync_attributes_spec.rb:17-32` testa o serviço isolado.
- Ficam como `visitor` contatos gravados por outros caminhos que pulam callbacks (`insert_all`/`upsert_all`, que aparecem em outros services). Isso não foi auditado porque está fora do importador.
- A confirmação em produção depende de você. Consulta só de leitura, pelo runbook (SSM + `docker exec psql`):
  ```sql
  SELECT c.contact_type, count(*)
  FROM campaign_import_rows r JOIN contacts c ON c.id = r.contact_id
  WHERE r.status = <valor de imported> GROUP BY 1;
  ```
  Antes de rodar, confira no schema o nome da coluna de contato em `campaign_import_rows` e o valor do enum `status`. Não conferi os dois.

**O que muda na F1**

Não há correção de visibilidade a fazer. O trabalho sobre "tipo do contato" fica limitado ao lado de cliente: a planilha poder marcar o contato como `customer`, que hoje só acontece quando o card é ganho (#1166/#1197). Vale também um spec de regressão de que o importador cria `lead`, para o comportamento não depender só da leitura do código.


## codigo: lacuna-3-Quando a leitura das conversas preenche um campo novo

**Leitura das conversas ao criar um campo novo: o que o código em produção faz**

Li `/Users/rodrigosilva/dev/worktrees/chat2you/relacionamentos-pesquisa` (HEAD `d987e9dce9`), sem alterar nada.

**Resposta curta:** hoje a tela de criar campo não pode prometer "preenche sozinho". O campo novo só recebe valor quando um card aberto, que é o assunto atual da conversa, é avaliado de novo. A leitura vê apenas as últimas mensagens. Um campo de empresa nunca é preenchido. Um valor que já existe nunca é corrigido.

**(a) Um campo novo é preenchido com as conversas antigas?** Não. Só quando há atividade nova, e mesmo assim só com as mensagens mais recentes.
- Criar o campo não dispara nada. Não há callback em `app/models/custom_attribute_definition.rb` e nenhum job ou listener usa a definição do campo.
- O campo novo só entra na lista de campos a preencher na próxima avaliação do card (`app/services/crm/ai/attribute_extraction.rb:17-21` monta essa lista a cada avaliação).
- A avaliação só acontece em três casos:
  - mensagem nova (`app/services/crm/conversations/card_syncer.rb:91-94` chama `observer.rb:8-13`, com espera de 15 s, `config.rb:8`);
  - foco ou assunto novo (`cards/focus.rb:13`, `subjects/identifier.rb:92`, `subjects/suggestion_responder.rb:56`);
  - o botão "Avaliar agora" (`interactive_operation.rb:35`).
- A leitura não vê o histórico inteiro. São no máximo 12 mensagens por conversa e 40 no total (`context_builder.rb:4-5`, `:137-156`). Um dado dito há 3 meses não entra.
- Cards fora disso nunca são lidos. A avaliação pula card que não está aberto (ganho ou perdido) e card que não é o assunto atual (`evaluator.rb:17-19`). Contato sem card não tem caminho nenhum, porque a leitura sempre parte de um card (`attribute_extractor_applier.rb:19-21`). **Para a Base de clientes isso pesa:** um cliente importado sem card aberto nunca terá campo preenchido pela conversa.
- Campo de negócio tem mais uma trava: só é gravado no card que é o assunto atual (`attribute_extractor_applier.rb:31-37`).

**(b) Com que frequência roda e quanto custa?**
- A leitura não faz uma chamada própria. Ela vai junto na mesma chamada que já classifica a etapa do card: a lista de campos entra no pedido (`evaluator.rb:69-73`) e os valores voltam na mesma resposta (`stage_classifier.rb:66`, `:79`). O custo extra de um campo novo é só o texto do nome e da descrição a mais em cada avaliação, mais o valor que volta.
- Frequência:
  - a cada mensagem, com espera de 15 s entre avaliações (`config.rb:8`, `evaluator.rb:16`);
  - mais uma rodada a cada 6 h (`config/schedule.yml:104-107`) para cards parados há mais de 168 h (`config.rb:11`, `stale_cards_job.rb:11-14`). Card que já foi avaliado depois da última mensagem é pulado (`stale_cards_job.rb:30-39`), então essa rodada não relê conversa sem novidade.
- O modelo é `gpt-6-luna`, com esforço `high` (`config.rb:14-16`, `:25`).
- O valor por conta não está no código. Cada chamada é registrada em `crm_ai_usage_events` (tokens e `cost_estimate`, em `app/models/crm/ai_usage_event.rb:5-17`), com o tipo `avaliacao_card` (`evaluator.rb:62`). Para ter o número é preciso consultar o banco de produção, o que não fiz porque exige o seu OK.
- A leitura pode ser desligada de duas formas: para todo o sistema, pela variável `CRM_AI_ATTR_EXTRACTION` (`config.rb:79-82`), ou por funil, pela opção `attribute_extraction_enabled`. Ela vem ligada nos funis novos (`pipeline.rb:70`). Num funil antigo sem essa opção, ela fica desligada (`config.rb:90-91`).

**(c) Campo de empresa e valor que já existe:** as duas lacunas se confirmam.
- O tipo de campo `company_attribute` existe (`custom_attribute_definition.rb:48`), mas a leitura só procura campos de contato, conversa e negócio (`attribute_schema_builder.rb:19-20`, `:29`). Também só grava nesses três (`attribute_extractor_applier.rb:19-21`). Campo de empresa nunca é preenchido.
- Qualquer valor que já está lá trava o campo para sempre: valor importado, digitado ou lido antes (`attribute_extractor_applier.rb:83`, `:88-93`). A leitura não sobrescreve, nem quando a conversa traz um dado mais novo.
- Abaixo de 60% de confiança o valor é descartado (`:2`, `:82`). Campo de lista só aceita uma das opções cadastradas, com o texto exato (`:126-130`).

**O que isso pede da tela de criar campo**
- Ao escolher "Empresa", avisar que esse campo não é preenchido pela conversa.
- No lugar de "preenche sozinho", algo como: "Vamos preencher quando o cliente falar disso numa conversa nova."
- Ao importar a planilha, avisar que o valor que vier dela não será trocado pela conversa.
- Para cumprir a promessa de preencher com o passado, como o Lightfield faz, é preciso construir:
  - uma passada sobre as conversas antigas, com custo próprio;
  - um caminho para contato que não tem card;
  - uma regra para atualizar valor que já existe.

Não confirmei o comportamento do Lightfield pelo código; isso fica com a parte de pesquisa na web.


## codigo: lacuna-4-Adoção real das flags e uso de Empresas em produção

A pesquisa continua em aberto. Ainda não há nenhum número de produção, porque a consulta só pode rodar depois do seu OK. A consulta está pronta, é só leitura e já rodou sem erro num banco local vazio. Por isso confirmei só a sintaxe; os números dependem da rodada em produção.

**O que o código já responde**

| Ponto | Situação no código | Fonte |
|---|---|---|
| `companies` | Desligada por padrão e marcada como premium | `config/features.yml:229-232`; `app/helpers/super_admin/account_features_helper.rb:6-7` |
| `crm_v2` | Desligada por padrão | `config/features.yml:195-197` |
| `relationships_attributes`, `relationships_navigation`, `customer_base` | Desligadas por padrão | `config/features.yml:283-286`, `:293-296`, `:330-333` |
| Ligar e desligar flags | Cada flag ocupa um bit num número da conta. Com isso a consulta conta as contas ligadas direto no banco | `app/models/concerns/featurable.rb:16-23` e `:48-50`; colunas em `db/schema.rb:83` e `:91` |
| Campos de contato, empresa e card | Ficam todos na mesma tabela, separados por tipo, e cada um tem uma descrição | Tipos em `app/models/custom_attribute_definition.rb:48`; descrição em `db/schema.rb:2725` |
| Vínculo contato com empresa | Os contatos têm `company_id` (`db/schema.rb:1710`). A tabela de empresas guarda quantos contatos cada uma tem | `db/schema.rb:1661-1675` |
| Limite de linhas da planilha | Excel: 20 mil linhas, ajustável pela variável `CAMPAIGN_IMPORT_MAX_XLSX_ROWS`. CSV: 50 mil | `app/services/campaign_imports/config.rb:15` e `:18-19`; aplicado em `app/services/campaign_imports/validator.rb:248` |
| Contatos por página | 15 | `app/controllers/api/v1/accounts/contacts_controller.rb:12` e `:153` |

O arquivo de flags é igual no `origin/main` e no worktree (HEAD `d987e9dce9`). Isso só vale se a produção estiver rodando o `main` atual: se a lista de flags mudar de ordem, os bits mudam. Não conferi qual versão está publicada.

**A consulta**

Arquivo: `/private/tmp/claude-501/-Users-rodrigosilva-dev-chat2you/09939abc-8e1e-4804-985d-af6c03010af6/scratchpad/adocao_relacionamentos.sql`

- Roda numa transação só de leitura (`BEGIN TRANSACTION READ ONLY`), com limite de 60 segundos por comando e de 2 segundos para trava, e termina em `ROLLBACK`.
- Traz só totais. Não sai nome, telefone, e-mail nem nome de conta.
- Responde cinco perguntas:
  1. Quantas contas ativas têm cada uma das cinco flags ligada.
  2. Tamanho da base de contatos por conta ativa: mediana, 90%, 99%, maior conta, e quantas passam de 15 mil, 20 mil e 50 mil.
  3. Quantas contas usam Empresas, quantas empresas existem e que fração dos contatos tem `company_id`.
  4. Quantos campos existem por destino (conversa, contato, empresa, card), em quantas contas, e quantos estão sem descrição.
  5. Quantas importações de planilha já foram feitas, e o tamanho de 90% delas e da maior.

**Como rodar (depois do seu OK)**

Seguindo a regra da memória: só `psql`, nunca `rails runner`.

1. Ler `docs/processo-de-release.md` e `docs/prospeccao_e0_rollout_rollback.md`.
2. Achar a instância que está no ar com `aws ec2 describe-instances` filtrando `running`. Ela muda a cada deploy.
3. Pelo SSM `AWS-RunShellScript`: mandar o SQL em base64, copiar com `docker cp` para `/tmp/q.sql` dentro do `chatwoot-web` e rodar `docker exec chatwoot-web sh -c 'psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -f /tmp/q.sql'`.
4. Se hub2you e Autonom.ia usam bancos separados, rodar uma vez em cada. Não confirmei se são separados.

**Como os números decidem o escopo**

- **Empresa como terceiro destino:** pode sair da primeira versão se, na parte 1, `companies` aparecer em menos de 5% das contas ativas e, na parte 3, a fração de contatos com empresa ficar perto de zero. O corte de 5% é meu, não veio de você nem do código.
- **Tetos de Excel e de 15 por página:** entram no escopo se, na parte 2, alguma conta passar de 20 mil contatos, ou se, na parte 5, a maior importação chegar perto de 20 mil linhas.
- **Descrição dos campos:** se a parte 4 mostrar muitos campos de card e de contato sem descrição, a IA do CRM está preenchendo esses campos sem saber para que servem. Aí a Base de clientes precisa pedir a descrição na hora de criar o campo e ajudar a corrigir os campos antigos.

Aguardo seu OK para rodar a consulta em produção.


## web: lacuna-5-Players brasileiros de WhatsApp para PME com 'base de clientes' não cobertos

**Lacuna fechada: concorrentes diretos de WhatsApp para PME e o que eles fazem depois de importar a base**

## Conclusão
O que diferencia esses produtos é o que acontece depois de importar: segmentos prontos com nome de gente, que viram público de uma campanha em um clique. Só o Zoppy e o Wati oferecem segmentos prontos. O Umbler entrega apenas etiqueta + disparo. O Kommo tem segmento por regra, mas pago e com cara de configuração técnica. No upstream do Chatwoot o risco de conflito é real e atual: tem trabalho em empresas e contatos ainda fora do nosso fork.

## Por player

**Zoppy (Brasil, varejo e e-commerce)** — https://www.zoppy.com.br
- Faz uma "matriz RFM automática" sem planilha, com segmentos de nome simples: "quem está pronto pra voltar", "quem está esfriando", "quem é campeão".
- Tem automação com gatilho de "reativação de inativos", ao lado de pós-venda, carrinho abandonado e aniversário. Envia por WhatsApp oficial da Meta, e-mail e SMS.
- A base vem "do ERP integrado ou de planilha" (Nuvemshop, Shopify, VTEX, Tray, Bling, Tiny…). O site não detalha a tela de importação.
- **Para nós:** são os rótulos certos para QI 70. Mas a matriz RFM depende de dado de compra (data e valor), que o Chat2You só tem se a coluna vier na planilha ou vier do negócio ganho no CRM.

**Wati (Índia, PME)** — https://support.wati.io/en/articles/11660835-how-to-use-predefined-segments-in-campaigns
- Tem segmentos predefinidos, criados sozinhos a partir do comportamento:
  - Highly Engaged: leu, clicou ou respondeu a 3 ou mais campanhas em 90 dias.
  - Winback: a última mensagem do cliente foi entre 30 e 90 dias atrás.
  - At Risk: a última mensagem foi há 90 dias.
  - All Valid Contacts: todos com telefone válido.
- O cliente escolhe o segmento dentro de "Create New Campaign". Só nos planos Pro e Business.
- A importação usa um CSV modelo com colunas fixas "Allow Campaign"/"Allow SMS" (consentimento) e colunas de atributo (https://support.wati.io/es/articles/11463442-como-actualizar-atributos-de-contactos-de-forma-masiva).
- Separa atributo (fica no contato) de tag (só classifica) (https://support.wati.io/en/articles/11463439-how-to-add-contact-attributes-to-a-contact-in-wati).
- **Para nós:** o Winback e o At Risk só usam a data da última conversa, que o Chatwoot já tem. Dá para ter segmentos prontos sem dado de compra. O consentimento entra como coluna obrigatória já na importação.

**Interakt (Índia)** — https://www.interakt.shop/?p=78703
- Segmenta pelo histórico de compras sincronizado da loja (Shopify/WooCommerce).
- Quem chega por anúncio Click to WhatsApp ganha a etiqueta automática "ctwa" e pode ser trabalhado de novo depois.
- Um concorrente (QuickReply.ai, portanto opinião parcial) chama a segmentação deles de "complexa e pouco intuitiva" (https://www.quickreply.ai/compare/interakt-vs-quickreply-ai).

**Umbler Talk (Brasil)**
- A importação aceita .vcf (recomendado) ou .csv, pelo caminho Contatos → três pontinhos → "Importar". O cabeçalho do CSV pode fazer a importação falhar (https://help.umbler.com/hc/pt-br/articles/4415969720205-Como-importar-e-exportar-contatos-no-Talk).
- O envio em massa sai da agenda, filtrando por etiquetas, ou direto de um arquivo. As variáveis do modelo de mensagem são primeiro nome, nome completo, e-mail, telefone ou texto fixo (https://help.umbler.com/hc/pt-br/articles/18866244828301-Envios-em-massa; o link deu 403, então a descrição vem do trecho da busca).
- Não tem segmento pronto nem reativação.
- **Para nós:** este é o piso do mercado. Superamos com segmentos prontos e com a prévia antes do envio.

**Digisac (Brasil)**
- Só achei páginas de integração: contatos e etiquetas sincronizados com Ploomes e Moskit (https://www.digisac.com.br/solucoes/integracoes/moskit).
- Não achei ajuda pública sobre importação, segmentos ou disparo. Lacuna aberta, não vou inventar.

**Leadster (Brasil)**
- Não é concorrente de base de clientes. É chatbot de site para captar e qualificar leads, com pontuação de lead (https://www.jivochat.com.br/blog/reviews/review-leadster.html).
- Não achei importação nem disparo para a base existente. Pode sair da lista.

**Kommo** — https://support.kommo.com/docs/how-to-create-segments-in-kommo
- Tem dois tipos de segmento:
  - **Manual:** a contagem não se atualiza sozinha; é preciso clicar em "Count leads". Usa regras como nome, valor, origem, etapa do funil e data da conversa.
  - **Automated:** a lista se atualiza sozinha, e só esse tipo dispara ações quando o lead entra ou sai do segmento.
- Os limites são 50 condições por segmento e 10 por grupo, com E/OU.
- Disponibilidade: manual a partir do plano Advanced, automático a partir do Pro.
- O broadcast exige "At least one saved Segment", só administrador pode enviar, e o WhatsApp precisa de modelo aprovado pela Meta (https://support.kommo.com/docs/marketing-campaigns.md).
- **Para nós:** o segmento do Kommo é por **lead/negócio**, não por pessoa. Isso confirma a separação entre pessoa e negócio. Mas o construtor de regras E/OU não serve para QI 70.

**RD Station CRM**
- Importa de planilha negociações, empresas e contatos. O limite é 1.000 linhas no plano gratuito e 10.000 nos pagos (https://www.rdstation.com/planos/crm/).
- Um usuário relata que, quando a planilha não tem os campos obrigatórios do funil, as oportunidades "travam" e não avançam de etapa. Também reclama da falta de instrução para preparar o arquivo (https://www.b2bstack.com.br/product/rd-station-crm/avaliacoes?page=124).
- **Para nós:** a prévia precisa avisar quais campos obrigatórios do funil estão faltando antes de criar os cards.
- A ajuda oficial da RD de novo não apareceu na busca. Lacuna parcial.

## Chatwoot upstream: risco no fork (verificado no repositório)
- O `upstream/develop` está 50 commits à frente do nosso HEAD (`15bbecffd7`). Os que tocam Relacionamentos:
  - `66275a535c` (30/09): classifica contatos como lead na criação/atualização (#16077, 13 arquivos).
  - `26ddaba230`: `contact_type` no webhook.
  - `351c96a213` (03/10): redesign das páginas de empresa e enriquecimento Context.dev (#16015, 66 arquivos, +2661/−1064). Mexe em `components-next/DetailsPageLayout.vue`, `TabBar.vue`, `settings/attributes/Index.vue` e `config/routes.rb`.
  - `e6c21b63de` (07/10): seletor de empresa no contato (#15988). Mexe em `components-next/Contacts/{ContactsCard,ContactsForm}`, `Pages/ContactDetails.vue`, `Pages/ContactsList.vue` e `contacts_controller.rb`. O próprio commit diz que deixou "CSV import association for a follow-up", ou seja, o upstream ainda vai mexer na importação ligando contato a empresa.
- O redesign de contatos do upstream é de 11/12/2024 (https://www.chatwoot.com/blog/changelog-audio-alerts-contact-redesign). Os segmentos do upstream são filtros salvos na barra lateral (https://www.chatwoot.com/hc/user-guide/articles/1677748953-group-your-contacts-using-filters-and-save-them-as-custom-segments).
- Nosso fork já tem componentes próprios dentro de `components-next/Contacts/`: `CampaignImport/`, `ContactCustomer/`, `ContactOptOut/`.
- **Recomendação:** antes de remontar a página, sincronizar com o upstream, no mínimo `351c96a213` e `e6c21b63de`. Fazer a nova página Relacionamentos/Base de clientes em arquivos próprios, sem editar `ContactsList.vue`/`ContactDetails.vue` do upstream.

## O que levar para o desenho
1. **Segmentos prontos com nome simples** (Zoppy e Wati): "Falou com você há pouco", "Sumiu há 1 a 3 meses", "Sumiu há mais de 3 meses", "Já comprou", "Comprou mais de uma vez". Cada um com 1 botão, "Mandar mensagem para esse grupo", e prévia de quantas pessoas recebem.
2. **Segmentos que funcionam sem dado de compra:** usar a última conversa, como o Wati faz. Os que dependem de compra usam data e valor vindos da planilha ou do negócio ganho.
3. **Consentimento na importação** (Wati: "Allow Campaign"): uma pergunta simples, "Essas pessoas aceitaram receber mensagens?", antes de liberar o disparo.
4. **Não copiar** o construtor E/OU do Kommo nem a importação que falha por causa do cabeçalho (Umbler). A prévia deve mostrar coluna por coluna e os campos obrigatórios que faltam (RD).

Ficou sem fonte primária: as telas da Digisac e a ajuda da RD.


## web: lacuna-6-LGPD e Meta: a importação deve registrar origem e permissão?

Resumo: as fontes oficiais não exigem que a importação pergunte a base legal da LGPD. Exigem que a empresa consiga provar de onde veio o contato e a permissão, e que respeite a recusa. A recomendação é uma pergunta de 1 clique sobre a origem da lista na prévia, gravada por lista, e não por contato e canal. Isso precisa da decisão do Rodrigo.

**O que dizem as fontes oficiais**

1. **ANPD, Guia de Legítimo Interesse** (versão 1.0, fev/2024). Li o texto do PDF inteiro, pela cópia do TCE-PB: https://tce.pb.gov.br/wp-content/uploads/2025/03/guia_legitimo_interesse.pdf
   - Para avaliar a "legítima expectativa", o guia manda olhar quatro coisas (p. 23):
     - se a empresa já tinha relação com a pessoa;
     - de onde vieram os dados: se foram coletados direto da pessoa, recebidos de outra empresa ou tirados de fonte pública;
     - em que contexto e em que época foram coletados;
     - se o uso combina com o motivo da coleta.

     O modelo de teste no anexo repete essas perguntas (p. 51).
   - O guia dá um exemplo de envio de promoção a quem já tem relação com a empresa. Ele aceita o legítimo interesse porque há relação prévia e um "mecanismo de descadastramento da lista de envios" (p. 18).
   - Manter o registro das operações é "obrigação legal" (art. 37) (p. 30). Já o teste de balanceamento é "boa prática e medida recomendável", não obrigatório (p. 31).
   - Entre as proteções, o guia pede um canal fácil para a pessoa "se descadastrar, de opor ao tratamento" (p. 52).
   - Não cabe legítimo interesse para dado sensível. Esta frase veio de resumo de escritório (Mattos Filho), não da minha leitura do PDF: https://www.mattosfilho.com.br/unico/anpd-legitimo-interesse-lgpd/

   **O que isso quer dizer para nós:** a ANPD não exige um campo "base legal" por contato. Mas a origem e o contexto da coleta são justamente o que a empresa precisa conseguir provar. Ninguém prova isso se a importação não grava a origem.

2. **Meta, regras de permissão (opt-in)**: https://developers.facebook.com/docs/whatsapp/overview/getting-opt-in
   - São só três exigências:
     - deixar claro que a pessoa está aceitando receber mensagens;
     - dizer o nome da empresa;
     - cumprir a lei local.
   - A permissão pode ser geral, sem citar o WhatsApp. Pode ser colhida fora dele: site, SMS, ligação, papel.
   - A página não fala de lista importada nem obriga a guardar registro.

3. **Política do WhatsApp Business**: https://whatsappbusiness.com/pt-br/policy/
   - Seção 1: só se pode contatar quem "have given you their mobile phone number".
   - Também da seção 1: "Você é a única pessoa responsável por determinar o método de adesão e garantir que obteve essa adesão".
   - Ainda na seção 1: é preciso respeitar pedidos de saída "dentro e fora do WhatsApp", "inclusive removendo-a da sua lista de contatos".
   - Seção 2: a conversa só pode começar com modelo de mensagem aprovado.
   - Nas boas práticas, recomenda pedir permissão que cubra os diferentes tipos de mensagem.

   **O que isso quer dizer para nós:** a responsabilidade de provar a permissão é do cliente, que é nosso usuário. Uma lista importada sem origem conhecida põe o número dele em risco.

4. **Botão para sair do marketing, confirmado em parte:**
   - **Oficial:** a página de componentes de modelo diz que um uso comum do botão de resposta rápida é sair do marketing. O exemplo traz "Unsubscribe from Promos": https://developers.facebook.com/docs/whatsapp/business-management-api/message-templates/components
   - **Oficial:** a pessoa pode parar as ofertas daquela empresa no próprio WhatsApp ("Offers and announcements"). A partir daí a mensagem não é entregue: vem o erro 131050, e o webhook `user_preferences` avisa: https://developers.facebook.com/documentation/business-messaging/whatsapp/templates/marketing-templates/
   - **Não confirmado em página da Meta:** o subtipo de botão "Marketing opt-out", com o texto "Stop promotions". Só achei em fornecedores (Qiscus, indigitall, Clickatell). Um deles diz que o botão não tira o contato da lista: quem tira é a empresa. https://support.qiscus.com/hc/en-us/articles/13766924007577

**O que existe no código hoje**

- Só existe recusa (opt-out). As origens são `prospecting`, `email_unsubscribe` e `manual` (`app/models/concerns/contact_opt_out.rb:19`). A mudança vai só para o log (`contact_opt_out.rb:109-111`), sem registro de quem mudou nem quando.
- Não há permissão (opt-in), nem origem, nem base legal no contato.
- `CampaignAudienceLink` liga a campanha a um `campaign_import`, sem campo de origem nem de permissão (`app/models/campaign_audience_link.rb:1-37`).
- Nenhuma ocorrência de `131050` ou de `user_preferences` em `app/`, `lib/` e `enterprise/`. Ou seja, quem para as ofertas pelo próprio WhatsApp não vira recusa no Chat2You.
- A Prospecção já guarda a recusa com data e autor (`consent_refused_at` e `consent_refused_by_id` em `app/models/autonomia/prospecting/lead.rb:10,63`). É o único lugar com trilha de verdade.

**Recomendação para decidir com o Rodrigo**

| Opção | O que é | Prós | Contras |
|---|---|---|---|
| A. Nada novo | Importa como hoje | Zero atrito | Ninguém consegue provar de onde a lista veio. Risco ao número do cliente |
| **B. 1 pergunta por lista (recomendada)** | Na prévia: "De onde vieram esses contatos?" Respostas: "São meus clientes" / "Pediram para receber" / "Comprei ou peguei de outro lugar". Grava a origem, a data e quem importou na importação | Atende às perguntas da ANPD (p. 23 e 51) e à exigência da Meta de ter permissão. Uma tela, sem termo técnico | Precisa de coluna nova no `campaign_import` ou numa tabela própria do fork, nunca em tabela do Chatwoot |
| C. Permissão por contato e por canal | Coluna da planilha ou marca por contato e canal | É a prova mais forte | Mais complexa do que as fontes pedem. Ninguém sabe preencher |

Junto com qualquer opção, dois itens independentes:

- Ligar o webhook `user_preferences` e o erro 131050 a `opt_out!`, com uma origem nova, `whatsapp_marketing`.
- Gravar a mudança de recusa numa trilha de verdade em vez de só no log.

Fica para o Rodrigo decidir:
- **Bloquear ou só avisar:** o que fazer com "Comprei ou peguei de outro lugar". Recomendo bloquear o envio de campanha e deixar importar só para atendimento.
- **Base legal:** se pergunta ou não. Recomendo não perguntar "base legal" na interface: é termo técnico e nenhuma fonte exige.

Ressalvas:
- O PDF da ANPD que li é a cópia do TCE-PB, não o do gov.br. O conteúdo é a versão 1.0 com a capa da ANPD.
- Não li a LGPD em si (texto da lei), só o guia.
