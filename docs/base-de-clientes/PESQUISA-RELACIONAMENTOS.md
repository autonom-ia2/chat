# Base de clientes e nova página de Relacionamentos: o que trazer e como trazer

Este relatório junta 16 levantamentos: 6 sobre o código em produção (`d987e9dce9`, que tem o mesmo código de `3db6d348c2`) e 10 de pesquisa de mercado e de UX. Os caminhos de código partem da raiz do repositório. Quando o caminho começa por `components-next/` ou `routes/`, a base é `app/javascript/dashboard/`. Ainda não há nenhum número de produção: as duas consultas de leitura estão prontas e esperam o seu OK.

---

## 1. Resumo executivo: as 5 decisões que a pesquisa sustenta

1. **Diferencial: classificar cada coluna em pessoa, empresa ou negócio.** Ninguém pergunta isso de forma guiada. O Ploomes pede o destino coluna a coluna, mas com cara técnica. O Attio manda dividir a planilha. Nenhum produto pergunta se um dado do negócio "vai também para a pessoa". A ideia é um cartão por coluna, com a sugestão já marcada e um botão "Alterar". O motor de importação atual é reaproveitado.
2. **Toda informação criada nasce com nome e "Para que serve?" e já aparece na ficha.** Hoje a importação cria o campo só como texto, sem descrição e fora da ficha (`app/services/contact_imports/custom_attributes.rb:47-58`). Isso tem que mudar. A promessa precisa ser honesta: a conversa preenche só em conversa nova, nunca em campo de empresa e nunca por cima de um valor que já existe.
3. **Na v1, o negócio é opcional e sempre escolhido pela pessoa.** O padrão para quem "já é cliente" é marcar o contato como cliente com a data da planilha, sem criar card. Card só entra quando a pessoa escolhe o funil e a etapa. Ele leva `external_id` e não dispara automação nem leitura automática.
4. **Prévia com números e fichas de exemplo, e desfazer do lote.** Só o Pipedrive tem os dois, e o desfazer dele é só para administrador, por 48 h. O padrão para quem já existe é "completar só o que falta".
5. **Uma pergunta por lista: "De onde vieram esses contatos?"** A resposta fica gravada no lote. Junto, quem recusar ofertas pelo próprio WhatsApp passa a contar como recusa no Chat2You (erro 131050 e webhook `user_preferences`).

E a página: **cada registro tem um lugar só para as informações**, e a Home deixa de ser vitrine e vira tela de trabalho, com dados reais e uma ação principal.

---

## 2. Onde estamos (código em produção)

### 2.1 O que existe e serve: reaproveitar

| Peça | Por que serve | Fonte |
|---|---|---|
| Motor de importação | Lê CSV e XLSX, acha o cabeçalho, roda em segundo plano em blocos de 500 linhas, pode rodar de novo sem duplicar e guarda o resultado por linha | `spreadsheet_reader.rb:43-52`, `importer.rb:16-27,47-58,139-147` |
| Leitura de colunas sem citar IA | Recebe só o formato mascarado. Aceita a coluna com confiança ≥ 0,8; abaixo disso pede a escolha à pessoa (`needs_column_choice`) | `audience_schema_resolver.rb:4-7,23-32`, `spreadsheet_reader.rb:100-126`, `ContactImportPage.vue:4` |
| Não duplicar | Acha a pessoa pelo celular com ou sem o 9, depois pelo e-mail. Repetida dentro do arquivo é recusada. Contato que já existe só ganha o que falta | `existing_contacts.rb:20-45`, `audience_validator.rb:102-116`, `contact_blank_fields.rb:13-20` |
| Prévia | "N já eram seus contatos · M novos", campos novos, valores que não servem e CSV das linhas recusadas com dados mascarados | `contact_imports/validator.rb:8-18`, `attribute_problems.rb:17-39`, `audience_validator.rb:201-208` |
| Empresa na importação | Acha pelo domínio do e-mail e depois pelo nome normalizado. Nunca troca a empresa de quem já tem uma. Desfaz o que criou se a linha falhar | `company_linker.rb:1-19,63-72,144-147` |
| Gravar um valor com segurança | `PATCH /relationships/:entity/:id/values` usa `previous` e devolve 409 em conflito | `values_controller.rb:11-18`, `FieldEditor.vue:154-186` |
| Criar campo do jeito certo | `DefinitionWriter` exige descrição e nome único. `display_on` põe o campo na tela | `definition_writer.rb:51-65`, `presentation.rb:15-23`, `configuration.rb:52` |
| Lead vira cliente | `become_customer!` guarda a primeira data. Card ganho promove o contato | `contact_customer.rb:12-30`, `crm/card.rb:103,184-186` |
| Recusa de mensagens | Tem origem e autor, passa para contato novo com o mesmo telefone ou e-mail, e as campanhas respeitam | `contact_opt_out.rb:19,37-48,97-107`, `audience_contacts.rb:40` |
| Silenciar eventos na carga | `SuppressedContactEvents` | `suppressed_contact_events.rb:6-12` |
| Peças de UX já aprovadas | Etapas, revisão com "Alterar", prévia, ensaio, modelos, rádio em cartões, erro padrão, gaveta com foco preso | `CampaignJourney/StepReview.vue:105-133`, `automacoes/components/AutomacaoEnsaio.vue`, `agentes/components/EscolhaRadio.vue`, `AgenteGaveta.vue`, `AgenteErro.vue` |
| Textos já no tom certo | Seções "Cliente" e "Mensagens ativas" | `ContactCustomerSection`, `ContactOptOutSection` (`pt_BR/contact.json`) |

### 2.2 O caso dos campos que aparecem à direita e não à esquerda

A ficha tem **três editores para o mesmo dado**:
1. "Campos personalizados", à esquerda (`RelationshipFields`/`FieldEditor`, tela `contact_details`).
2. A aba "Atributos", à direita (`ContactCustomAttributes.vue`). Ela mostra **todos** os campos, divididos em usados e não usados.
3. A lateral do atendimento (`conversation/customAttributes/CustomAttributes.vue:293-345`, tela `contact_sidebar`).

A regra de exibição fica em `components-next/Relationships/presentation.js:1-9`:
- Sem configuração, ou em modo `legacy`: a lateral mostra todos os campos, e `contact_details` e `company_details` mostram **nenhum**.
- Em modo `custom`: aparecem só os ids da lista `surfaces.<tela>.ids` (`configuration.rb:16-26`).

Por isso **um campo criado pela importação aparece na aba Atributos, à direita, e não aparece à esquerda**. A importação cria o campo sem chamar `display!`. Pior: a ficha vazia diz "Nenhum campo destacado nesta ficha… continuam disponíveis na aba Atributos" (`pt_BR/relationships.json:164-165`), ou seja, o próprio texto manda a pessoa para a outra tela. Isso **já acontece hoje em produção**.

### 2.3 O que está quebrado ou confunde o leigo

- **Home de Relacionamentos** (`RelationshipsHome.vue:37-175`): cerca de 15 textos de marketing e nenhum dado. Usa jargão: "Atributos personalizados", "definições de campos". O card de Empresas exige `['administrator','agent']` (`:52`), mas a rota aceita `contact_view` (`companies/routes.js:14-19`).
- **Lista de contatos:**
  - "Importar" fica escondido no menu ⋮ (`ContactMoreActions.vue:24-77`), e os ícones de importar e exportar estão trocados (`:45,57`).
  - Os botões são só ícone, sem texto (`ContactHeader.vue:68-106`).
  - A seleção para ação em massa só aparece ao passar o mouse (`ContactsList.vue:75-77`), então não funciona no celular.
  - Dá para editar dentro do card e também na ficha.
  - Os vazios têm emoji.
  - Provável bug: `toggleExpanded` não existe em `ContactEmptyState.vue:52`.
- **Ficha do contato:**
  - Cerca de 10 blocos e até 6 abas. A aba padrão é Notas (`ContactManageView.vue:36`).
  - O formulário não tem rótulos e mostra 8 redes sociais (`ContactsForm.vue:36-56,293-330`).
  - A empresa existe de dois jeitos: o texto livre `companyName` e o vínculo `companyId` (`ContactsForm.vue:44,100-104`). A lista mostra o texto livre, não a empresa ligada (`ContactsCard.vue:156-163`).
  - Configurar a conta e preencher o registro estão misturados: "Configurar campos" e "Criar atributo" aparecem dentro da ficha (`FieldConfigurator.vue:272-292`).
- **Oportunidades:**
  - Abrem em outra aba (`RelationshipOpportunities.vue:172-178`).
  - O vazio culpa o filtro mesmo quando a pessoa não tem negócio nenhum (`:255-269`).
  - Não mostram os campos próprios do card.
- **Tela de Atributos em Configurações:**
  - Mostra o tipo cru em inglês (`AttributeListItem.vue:52`) e a chave com ícone de chave (`:59-65`).
  - O formulário antigo pede "Regex".
  - Provável bug: `ENTITY_LABELS.card` não existe (`pt_BR/relationships.json:158-162`).
- **FieldConfigurator:** mostra "Entidade", "Restaurar padrão" sem explicar e os tipos "(legado)". Não tem prévia. Usa checkbox cru (`FieldEditor.vue:310-322`).
- **Navegação:**
  - Com a navegação nova, Segmentos e Etiquetas saem da barra lateral (`ContactViewSelect.vue:15-38`).
  - As rotas de importação não acendem o item no menu (`Sidebar.vue:1386-1399`).
- **Design:**
  - O primário `bg-n-brand` (#2781F6) com texto branco dá cerca de 3,8:1, abaixo do AA (`Button.vue:104`).
  - Botões de 32 px no FieldConfigurator e no SidePanel.
  - `uppercase` aparece nas referências de Automações e no próprio GUIA-VISUAL:89. Agentes não usa.

### 2.4 Limites técnicos reais

| Limite | Fonte |
|---|---|
| Card exige funil, etapa do mesmo funil e título | `crm/card.rb:82-83,105,113,195-200` |
| Card **não tem `company_id`**. A empresa só é alcançada pelo contato | `crm/card.rb:3-28` |
| `external_id` do card é único por conta e serve para não duplicar | `crm/card.rb:65,107` |
| `Crm::Cards::Creator` aceita funil, etapa, contato, valor, `custom_attributes` e `external_id`. Não chama automação de etapa | `crm/cards/creator.rb:4-27`, `crm_card_converter.rb:1-3` |
| Card criado já ganho grava `closed_at` e `customer_since` com a data de **hoje**, o que infla o relatório do mês | `card.rb:179`, `contact_customer.rb:16`, `reports/summary.rb:78-81` |
| Gravar campo do card não valida o tipo e aceita qualquer chave | `cards_controller.rb:464,477,482-492` |
| Campo de card vale para a conta inteira e entra na leitura de todos os funis | `attribute_schema_builder.rb:26-32` |
| Empresa: só `name` é obrigatório; **sem CNPJ**; nome não é único; domínio é único | `enterprise/app/models/company.rb:3-21,34` |
| Empresa é Enterprise e premium, atrás da flag `companies`, desligada por padrão | `config/features.yml:229-232` |
| Uma empresa por contato | `enterprise/.../concerns/contact.rb:6` |
| Importação escolhe só nome, celular, e-mail e empresa. Toda coluna extra vira campo **texto** do contato | `contact_imports_controller.rb:29-32`, `attribute_columns.rb:60`, `custom_attributes.rb:51` |
| Tela nova de campos aceita só `text number link date list checkbox`; moeda e percentual ficam de fora | `relationships/configuration.rb:10` |
| Não há tela de exibição para card, só `contact_sidebar`, `contact_details` e `company_details` | `configuration.rb:6-7` |
| A conversa **nunca** preenche campo de empresa | `attribute_schema_builder.rb:19-20,29`, `attribute_extractor_applier.rb:19-21` |
| A conversa **nunca sobrescreve** um valor, nem o importado | `attribute_extractor_applier.rb:83,88-93` |
| A conversa lê no máximo 12 mensagens por conversa e 40 no total, só com atividade nova e só a partir de card aberto que seja o assunto atual. Contato sem card nunca é preenchido | `context_builder.rb:4-5`, `evaluator.rb:17-19`, `attribute_extractor_applier.rb:19-21,31-37` |
| Importação não sobrescreve. Não existe modo "atualizar" | `contact_blank_fields.rb:13-19`, `company_linker.rb:68,83-86` |
| Não há desfazer da importação de contatos. A linha não guarda o valor anterior | `campaign_import.rb:146-149`, `undo_labels.rb:10-30`, `db/schema.rb:1145-1165` |
| Uma pessoa com vários negócios: a 2ª linha com o mesmo celular é recusada | `audience_validator.rb:107-110` |
| Contato importado nasce `lead`, não `visitor`, por causa do `before_save`. O risco nº 1 do relatório de CRM **é falso** | `contact.rb:77,246-248`, `sync_attributes.rb:22-30` |
| Cards importados abertos e parados podem gerar uma chamada paga cada um, com conversa vazia (5 mil linhas = 5 mil chamadas) | `stale_cards_job.rb:14-19`, `current_subject.rb:8-9`, `evaluator.rb:12-29` |
| Card importado sem `inbox_id` não é reaproveitado quando o cliente escreve, e nasce um segundo card | `auto_create_deduplicator.rb:32-44` |
| Segmento é de um usuário só; ação em massa pega só os 15 da página; público de campanha só nasce de planilha | `custom_filters_controller.rb:30-31`, `ContactsIndex.vue:163-171`, `audience_contacts.rb:7-17` |
| Exportação sai só com `id name email phone_number labels` | `contacts_export_job.rb:104-106` |
| São muitas flags: `companies`, `custom_attributes`, `relationships_attributes`, `customer_base` (sem nenhuma referência no front) e as variáveis `CAMPAIGN_JOURNEY_ENABLED`/`CAMPAIGN_IMPORT_ENABLED`, que valem para a instalação inteira | `contact_imports/config.rb:1-8`, `contact_reading.rb:12-16` |
| Valores extras de cada pessoa ficam sem máscara e sem prazo em `campaign_import_rows.extra_values` | `db/schema.rb:1163` |

---

## 3. Mercado

| Produto | Como importa | Separa pessoa, empresa e negócio? | Ficha | Copiar | Evitar |
|---|---|---|---|---|---|
| **HubSpot** | Assistente de cerca de 14 passos. Escolhe criar e/ou atualizar. Cria campo no mapeamento | Sim, num arquivo só: a coluna mostra o objeto e a ligação é automática ([import-objects](https://knowledge.hubspot.com/import-and-export/import-objects)) | 3 colunas. A edição no lugar pede passar o mouse ([work-with-records](https://knowledge.hubspot.com/records/work-with-records)) | Smart property: descreve o campo, ele gera e mostra prévia num registro real ([smart-properties](https://knowledge.hubspot.com/properties/create-smart-properties)) | Record ID, "upsert", 5 a 7 abas para criar um campo, coluna não mapeada trava o avanço, sem desfazer |
| **Salesforce** | Só CSV, escondido no Setup | Contas e contatos sim. **Negócio não** ([SalesforceBen](https://www.salesforceben.com/introduction-to-the-data-import-wizard-for-salesforce/), terceiro) | — | Não apagar com valor vazio | Vocabulário técnico, fila de jobs |
| **Pipedrive** | Planilha; mapeia sozinho e o resto se arrasta; cria campo no mapeamento | Sim: "uma linha = tudo ligado"; o negócio sem título ganha um gerado | Lateral com resumo fixo, negócios ligados, histórico | Prévia, relatório com arquivo de falhas, **desfazer em 48 h** ([Pipedrive](https://support.pipedrive.com/en/article/importing-data-into-pipedrive-with-spreadsheets)) | Arrastar (ruim no toque), Overwrite/Append, desfazer só para administrador, descrição do campo só em plano pago |
| **Zoho / Dynamics / Freshsales** | Um módulo por vez, ou .zip | Não: exigem ordem e vínculo por nome exato | — | "Não atualizar com vazio" | Ordem obrigatória, *option set*, lookup por nome exato, campo criado antes |
| **Ploomes** (BR) | Uma planilha | **Sim**: "definir se o campo é de Negócio, Empresa ou Pessoa"; coluna de Estágio obrigatória para o funil ([Ploomes](https://suporte.ploomes.com/pt-BR/articles/5792676-importacao-de-negocios)) | "Visão 360º" | A pergunta por coluna | Tela técnica, sem sugestão pronta |
| **Kommo** | Uma planilha | Sim, mas o cabeçalho tem que ser **idêntico** ao campo ([Kommo](https://support.kommo.com/docs/import-data-into-kommo)) | Campos do contato e da empresa dentro do card do lead | Salvar o mapeamento como modelo | Cabeçalho idêntico, segmento E/OU pago |
| **PipeRun** (BR) | "De > Para" automático | Empresa e pessoa | — | "+ Novo campo" no meio do mapeamento; 3 escolhas para repetidos (atualizar, **complementar**, descartar); erro corrigido na célula ([PipeRun](https://ajuda.crmpiperun.com/como-importar-empresas)) | Pedir "base legal" com o termo técnico |
| **Agendor** (BR) | Uma aba por vez, em ordem | Não | Seções do formulário | "Adicionar campo" na importação; prévia de 50 linhas ([Agendor](https://ajuda.agendor.com.br/pt-BR/articles/6801698-como-importar-clientes-com-campos-customizados)) | Ordem obrigatória |
| **Moskit/Ollow, Bitrix24** | Uma planilha (Moskit) ou três importações (Bitrix) | Sim (Moskit); por nome exato (Bitrix) | Aba "Vínculos" (Bitrix) | Tela com cabeçalho, 1ª linha e destino (Moskit) | Arquivo de erros como beco sem saída; campo criado antes |
| **RD Station CRM** | Negociações, empresas e contatos | Por categoria | Campos no cartão do funil | — | Oportunidades travam quando falta campo obrigatório do funil ([B2B Stack](https://www.b2bstack.com.br/product/rd-station-crm/avaliacoes?page=124)) |
| **Respond.io** | Só contato | — | — | Pergunta a finalidade; revisão com adicionados, atualizados e com erro; etiqueta do lote ([Respond.io](https://respond.io/help/contacts/contact-import)) | IA que falha em silêncio e depende do nome exato do campo |
| **Wati** | CSV modelo com colunas de permissão ("Allow Campaign") | — | — | Segmentos prontos pela última conversa: Winback 30-90 dias, At Risk acima de 90 ([Wati](https://support.wati.io/en/articles/11660835-how-to-use-predefined-segments-in-campaigns)) | Modelo de colunas fixas |
| **Zoppy** (BR) | ERP ou planilha | — | — | Rótulos de gente: "quem está esfriando", "quem é campeão" ([Zoppy](https://www.zoppy.com.br)) | RFM depende de dado de compra |
| **Umbler Talk** (BR) | .vcf ou .csv | — | — | É o piso do mercado | Cabeçalho que derruba a importação |
| **Attio** | 6 passos: cria atributo na hora, revisa valores (original ao lado do convertido), prévia por objeto, progresso por linha ([Attio](https://attio.com/help/reference/imports-exports/csv-imports/import-data-into-attio-via-csv)) | **Não**: manda dividir a planilha | Redesenho de 2026: essencial no topo, busca entre os campos, linha do tempo sem ruído, até 6 destaques ([changelog](https://attio.com/changelog/2026/record-page-redesign)) | Revisão de valores, prévia, página do registro | Duplicata só por e-mail ou domínio; créditos |
| **Folk** | — | — | O campo aparece no perfil e serve de variável na mensagem | "Magic field" simples ([Folk](https://help.folk.app/en/articles/7325564-magic-fields)) | — |
| **Day.ai / Lightfield** | Lightfield: agente que lê o CSV e liga tudo ([MarTech](https://martechseries.com/sales-marketing/crm/lightfield-launches-one-hour-crm-migration-agent-enabling-startups-to-replace-hubspot-with-an-ai-native-crm-in-under-60-minutes/)) | Lightfield sim | Day.ai mostra "por quê" a etapa foi deduzida | Preencher para trás ao criar campo; mostrar a origem do valor | Promessas sem teste independente |
| **Flatfile / Dromo / Ingestro** | 3 a 4 telas; pula o mapeamento quando tudo bate ([Dromo](https://changelog.dromo.io/column-matching-is-skipped-if-all-headers-match-exactly)) | — | — | Agrupar o que precisa de atenção; tela de valores de lista; "Próximo problema"; importar as boas e separar o resto | Mapeamento em tabela técnica |

**Lacunas que nenhum concorrente cobre (é aqui que a gente se diferencia):**
1. A pergunta guiada "isso é da pessoa, da empresa ou do negócio?" com sugestão pronta.
2. "O dado do negócio também vai para a pessoa?". Em todos os produtos, uma coluna tem um destino só.
3. A descrição do campo servindo de instrução para a leitura. O HubSpot separa Documentation de prompt; o Pipedrive só tem descrição em plano pago.
4. Desfazer aberto a quem não é administrador, guardando o valor antigo.
5. Telefone como chave principal. Ninguém usa, e para o WhatsApp é a chave natural.

**Contexto do fork:** o `upstream/develop` está 50 commits à frente. Dois deles mexem nas mesmas telas: `351c96a213` (redesenho de empresas, 66 arquivos) e `e6c21b63de` (seletor de empresa no contato, que promete mexer na importação).

---

## 4. UX para QI 70 e design premium: regras verificáveis

**Por que importa:**
- 29% dos brasileiros são analfabetos funcionais. Entre quem trabalha, só 40% têm leitura consolidada ([Inaf 2024](https://static.poder360.com.br/2025/08/dados-inaf-2024.pdf)).
- 60% dos usuários de internet acessam só pelo celular, e só 45% usam copiar e colar ([TIC Domicílios 2024](https://cetic.br/media/docs/publicacoes/2/20250512115624/tic_domicilios_2024_resumo_executivo.pdf)).
- Num estudo, reescrever o texto subiu o sucesso de quem lê pouco de 46% para 82% ([NN/g](https://www.nngroup.com/articles/writing-for-lower-literacy-users/)).

| # | Regra | Como conferir | Referência |
|---|---|---|---|
| L1 | Frase curta, voz ativa, verbo no botão ("Trazer minha lista", não "Importação de base") | Revisão de texto no PR | [Lei 15.263/2025, art. 5º](https://www.lex.com.br/lei-no-15-263-de-14-de-novembro-de-2025/) |
| L2 | Lista de palavras proibidas na interface: atributo, entidade, chave, campo personalizado, mapear, segmento, mesclar, card, legado, UTC, registro, inválido, IA | Lista revisada no PR (conferência manual, não filtro automático) | art. 5º IV-V; `GUIA-VISUAL.md:145-147` |
| L3 | Nível de leitura do 6º ano nas telas de entrada | Teste com 3 a 5 donos de negócio antes de liberar | NN/g; art. 5º XVIII |
| J1 | Uma pergunta por tela, e o título é a pergunta ("Esta coluna fala de quem?") | Cada tela tem 1 botão principal | [GOV.UK question pages](https://design-system.service.gov.uk/patterns/question-pages/) |
| J2 | Botão "Continuar", "Voltar" visível e respostas mantidas | — | GOV.UK; [W3C COGA 4.5.2](https://www.w3.org/TR/coga-usable/) |
| J3 | Nunca pedir de novo algo já dito; usar a última escolha como ponto de partida | — | [WCAG 3.3.7](https://www.w3.org/WAI/standards-guidelines/wcag/new-in-22/); [NN/g Wizards](https://www.nngroup.com/articles/wizards/) |
| J4 | Conferência antes de gravar, em blocos Pessoa / Empresa / Negócio com "Alterar"; botão final com o número ("Trazer 312 clientes") | — | [GOV.UK check answers](https://design-system.service.gov.uk/patterns/check-answers/); `StepReview.vue:105-133` |
| J6 | Começar pronto: pular a tela de colunas se tudo bater e mostrar primeiro só o que precisa de atenção ("3 colunas precisam de você") | — | Dromo/Flatfile |
| J7 | Salvar o andamento e deixar continuar depois | — | NN/g Wizards; COGA 4.5.9 |
| J8 | Aceitar "Não sei, pular esta coluna" | — | GOV.UK |
| E1 | Erro junto do campo, dizendo o que fazer, sem "ops" nem "inválido"; o resto continua igual | — | [GOV.UK error message](https://design-system.service.gov.uk/components/error-message/); `AgenteErro.vue:4-53` |
| E4 | Mostrar exemplos reais ("Maria, João, Ana…") em vez de "Coluna B" | — | COGA 4.7.5 |
| P2 | No primeiro nível só buscar, abrir ficha, adicionar e trazer lista; o resto em "Mais opções"; no máximo 2 níveis | — | [NN/g progressive disclosure](https://www.nngroup.com/articles/progressive-disclosure/) |
| P3 | Vazio = 1 frase + 1 botão; nunca "sem registros" enquanto carrega | — | [NN/g empty states](https://www.nngroup.com/articles/empty-state-interface-design/) |
| P4 | Ícone sempre com texto visível; nada que dependa de passar o mouse | Hoje já falha em `ContactHeader.vue:68-106` e `ContactsList.vue:75-77` | [NN/g icon usability](https://www.nngroup.com/articles/icon-usability/) |
| P5 | Informação vazia aparece como "Não informado", não some | — | GOV.UK |
| P7 | Celular primeiro; nada de arrastar como único jeito | — | WCAG 2.5.7 |
| A1 | Alvo de toque ≥ 44 px (`min-h-11`) | Conferir no FieldConfigurator e no SidePanel | regra interna > WCAG 2.5.8 |
| A4 | Sem `<select>` nativo: 2 a 4 opções em cartões-rádio (`EscolhaRadio.vue`); lista longa com `ChoiceSelect` | Hoje há `<input>` cru em `FieldEditor.vue:310`, `ContactCustomAttributes.vue:134`, `RelationshipMedia.vue:417` | regra do Rodrigo |

**Premium da casa.** O ponto de partida é `docs/guia-operante/GUIA-VISUAL.md`, com estas correções:
- Seguir **Agentes** como referência: zero `uppercase` (corrigir também GUIA-VISUAL:89), botão primário `bg-n-blue-11` por contraste (`AgenteBotao.vue:5-7,42-62`) e herói navy com variante `dark:bg-[#12305E]` (`AgentesHeroi.vue:20`).
- Herói navy único por tela (`AutomacaoHeroi.vue:106-131`), página `max-w-6xl` (`AutomacoesPage.vue:116-119`), cartões `rounded-2xl ring-1 ring-n-weak` e números grandes `tabular-nums`.
- Cores com sentido: teal = feito, âmbar = aviso, rubi = erro.
- Os quatro estados nomeados: esqueleto com `aria-busy`, erro com "Tentar de novo", vazio que ensina e cheio.
- O que vem do mercado: navegação que recua e estrutura que "se sente, não se vê" ([Linear](https://linear.app/blog/behind-the-latest-design-refresh)); na ficha, o que muda no centro e o que é fixo ao lado ([Stripe](https://support.stripe.com/questions/updates-to-the-customer-detail-page)); até 6 destaques no topo e busca entre as informações ([Attio](https://attio.com/changelog/2026/record-page-redesign)).

---

## 5. LGPD e WhatsApp: o que a Base de clientes precisa registrar e mostrar

**O que as fontes exigem:**
- **LGPD:** quem guarda os dados tem de provar o consentimento (art. 8º §2º). O registro das operações é obrigatório, "especialmente quando baseado no legítimo interesse" (art. 37). A pessoa tem direito de se opor (art. 18 §2º) ([Planalto](https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2018/lei/l13709.htm)).
- **ANPD** ([guia, v1.0](https://tce.pb.gov.br/wp-content/uploads/2025/03/guia_legitimo_interesse.pdf)): para avaliar a "legítima expectativa", olha a relação prévia, **a origem dos dados** e o contexto e época da coleta (p. 23 e 51). Aceita oferta a quem já é cliente quando há como se descadastrar (p. 18). Não exige um campo "base legal" por contato.
- **Meta:** só contatar quem deu o número e aceitou; a empresa é a única responsável pela permissão; tem de respeitar pedidos de saída "dentro e fora do WhatsApp" ([política](https://whatsappbusiness.com/pt-br/policy/), [opt-in](https://developers.facebook.com/docs/whatsapp/overview/getting-opt-in)). Quem desliga as ofertas no próprio WhatsApp gera o erro **131050** e o webhook `user_preferences` ([Meta](https://developers.facebook.com/documentation/business-messaging/whatsapp/templates/marketing-templates/)).
- **Precedente:** a primeira multa da ANPD (R$ 14,4 mil) foi por disparo em massa por WhatsApp sem base legal ([Convergência Digital](https://convergenciadigital.com.br/governo/primeira-multa-da-anpd-foi-para-disparo-eleitoral-por-celular-e-whatsapp)).

**O que existe hoje:** só a recusa, com três origens (`contact_opt_out.rb:19`), e a trilha dela vai para o log (`:109-111`). Não há permissão, origem nem base legal. `131050` e `user_preferences` não aparecem em lugar nenhum do código.

**O que a Base de clientes precisa ter:**
1. **Na prévia, uma pergunta por lista:** "De onde vieram esses contatos?". Respostas: "São meus clientes" / "Pediram para receber" / "Peguei de outro lugar". Gravar com a data, quem importou e o nome do arquivo, numa coluna do `campaign_import` (tabela do fork).
2. **A ficha mostra a origem** ("Veio da lista de 12/10, por Ana") e a situação de mensagens com a linguagem da seção que já existe (`ContactOptOutSection`).
3. **Nunca marcar "aceita mensagens" em massa.** O padrão do importado é "não sei" ([aviso Shopify](https://www.highviewapps.com/kb/update-your-customers-email-marketing-status/)).
4. **Ligar `131050` e `user_preferences` a `opt_out!`** com uma origem nova, `whatsapp_marketing`. Pôr essa origem também na ordem de precedência da mescla (`contact_merge_action.rb:6`). Gravar a recusa numa tabela de trilha, não só no log.
5. **Aviso curto antes de usar a base em campanha:** "Só mande ofertas para quem já é seu cliente ou deixou você mandar."
6. **Dado sensível** (CPF/RG em seguro) é necessário ao negócio e não se restringe (memória do projeto). Mas não se apoia em legítimo interesse, então fica como ponto jurídico em aberto.
7. **`extra_values` sem máscara:** definir um prazo de guarda e apagar depois de importar (`db/schema.rb:1163`, PRD §5).

---

## 6. Proposta de conceito

### 6.1 Nova página de Relacionamentos

> **Termos (decidido em 11/10/2026, alinhado com o Multifunil):** a lista é **Contatos**, todo mundo que está na base. **Cliente** é só o estado de quem comprou (`contact_type = customer`, selo e "Cliente desde"). Quem não comprou aparece como "Ainda não compraram"; "Interessado" não entra no produto. "Base de clientes" fica como nome do épico; na tela, o verbo é "Trazer minha lista".

**Estrutura e navegação.** Um item na barra lateral, "Relacionamentos", com abas no topo (`RelationshipTabs.vue`, 44 px):

| Aba | Conteúdo | Observação |
|---|---|---|
| **Contatos** (padrão) | Lista de pessoas | É a primeira tela |
| **Empresas** | Lista de empresas | Só com a flag `companies` |
| **Informações** | As perguntas da conta (o que hoje é "Atributos") | Separa configurar de preencher; só quem tem `attribute_manage` |
| **Listas trazidas** | Histórico de importações, com "Desfazer" | Pode morar dentro de Clientes, em "Mais opções" |

**Primeira tela, com dados:**
- Título "Contatos" e um botão principal: "Trazer minha lista", se a base estiver vazia ou pequena; senão "Adicionar contato". O outro fica como segundo botão, com texto visível.
- Busca grande, que tolera erro de digitação, por nome, telefone ou e-mail.
- Pílulas com números reais: "820 clientes · 1.400 ainda não compraram · 32 não querem mensagens". Os dados saem de `contact_type` e `opted_out_at`, que ainda não estão no `/summary` (`summary.rb:4-8`).
- Grupos prontos em botões, com nomes de gente: "Falou com você há pouco", "Sumiu há 1 a 3 meses", "Sumiu há mais de 3 meses", "Clientes", "Não quer mensagens". O Wati faz isso só com a última conversa. Faltam os filtros `contact_type` e `opted_out_at` em `filter_keys.yml` e `contactProvider.js`.
- **Cartão do contato:** nome, telefone, empresa ligada (não o texto livre), selo Cliente (quem não comprou fica sem selo), etapa do negócio aberto e um botão "Abrir". **Sem edição dentro do cartão.** Uma caixa de seleção visível dá a ação em massa no toque.
- Em "Mais opções": exportar, juntar repetidos, grupos salvos e etiquetas.

**Estados vazios (1 frase + 1 botão):**
- Conta sem contatos: "Você ainda não tem contatos aqui." → **Trazer minha lista**.
- Busca sem resultado: "Ninguém com esse nome." → **Limpar busca**.
- Empresas: "Nenhuma empresa ainda." → **Adicionar empresa** (hoje não tem botão, `CompaniesIndex.vue:190-197`).
- Negócios na ficha: "Esta pessoa ainda não tem negócio." → **Criar negócio**. Nunca culpar o filtro.
- Informações na ficha: "Nenhuma informação extra ainda." → **Criar informação**, só para quem pode.

**Ficha do contato:**
- **Cabeçalho:** nome, selo "Cliente desde 03/2024" e "Veio da lista de 12/10". Um botão principal, **Conversar**; o resto em "Mais" (ligar, bloquear, juntar com outro, apagar).
- **Faixa de até 6 destaques:** etapa do negócio, valor, último contato, empresa, mensagens (sim/não) e 1 informação escolhida.
- **Centro (o que muda):** conversas e negócios como cartões. O negócio abre **no lugar**, numa gaveta (`AgenteGaveta.vue`), sem nova aba.
- **Lateral (o que é fixo):**
  - "Dados": rótulos visíveis e "Alterar" por bloco. As 8 redes sociais vão para "Mais dados".
  - "Empresa": cartão ligado, com "Trocar".
  - "Informações": **lugar único**. Some a aba "Atributos" (`ContactCustomAttributes`/`CompanyCustomAttributes`) e some o modo `legacy`, que esconde tudo. Os campos mostrados por padrão são **todos os da conta**, com "Não informado". Busca quando houver mais de 10. A gravação reaproveita o `FieldEditor` (`/values` + `previous`).
- **Notas e histórico:** abas secundárias. O histórico precisa ganhar os eventos que hoje não aparecem: virou cliente, recusa, lista de origem.

### 6.2 Jornada da Base de clientes (uma ação por tela)

Etapas visíveis em texto: **Enviar → Conferir → Ver como fica → Pronto** (padrão `AgentesEtapas.vue`). O andamento fica salvo no rascunho do `campaign_import`, que já existe.

| # | Tela (título = pergunta) | Ação principal | Como funciona / base no código |
|---|---|---|---|
| 0 | "Traga sua lista" | **Escolher planilha** | Área de soltar + botão (`ContactImportPage.vue:262-278`); "Baixar planilha de exemplo"; uma frase: "Nada entra até você confirmar." |
| 1 | "Lendo sua planilha…" → "Encontramos 4.812 linhas" | (automático) | `spreadsheet_reader`; limites de 10 MB, 50 mil linhas em CSV e 20 mil em XLSX (`config.rb:10-20`) explicados em frase simples se estourar |
| 2 | "Qual coluna tem o celular?" (só se houver dúvida) | **Continuar** | `needs_column_choice` + `ContactImportColumns`; **pulada** quando a confiança é ≥ 0,8 |
| 3 | "Arrumamos suas colunas. 3 precisam de você." | **Conferir** | Lista em cartões: as já resolvidas recolhidas, as duvidosas abertas |
| 3a | Para cada coluna duvidosa: **"Esta coluna fala de quem?"** com exemplos ("Ouro, Prata, Bronze…") | Cartões-rádio: **A pessoa · A empresa · O negócio · Não usar** | Pergunta nova ao Jev por coluna extra, com "não sei" (`audience_schema_resolver.rb:116-131`); gravar em `schema_resolution['extra_columns']`; trocar o destino com um endpoint como o `PATCH columns` (`draft_changes.rb`). Empresa só aparece com a flag `companies` |
| 3b | Se escolheu Negócio: **"Guardar também na ficha da pessoa?"** | Sim / Não | Grava duas definições (contato e card) e escreve nas duas; não há espelhamento hoje |
| 3c | Coluna sem informação parecida: **"Criar uma informação nova"** | **Criar** | Nome sugerido do cabeçalho; **"Para que serve?"** já escrito a partir dos exemplos, com "Alterar"; tipo deduzido dos valores, com "Alterar". Grava pelo `DefinitionWriter` + `display!` (resolve o caso da seção 2.2). Na empresa: "Esta informação você preenche à mão." Texto honesto: "Vamos preencher quando o cliente falar disso numa conversa nova." |
| 3d | Lista com valores parecidos: "'Sao Paulo' é o mesmo que 'SP'?" | Sim / Manter como está / Deixar em branco | Padrão Flatfile; listas precisam de opções únicas (`definition_writer.rb:67-72`) |
| 4 | **"Essas pessoas já são suas clientes?"** | Todas / Nenhuma / Tem uma coluna que diz | `become_customer!` com `customer_since` da planilha quando houver; cliente nunca volta a lead pela importação |
| 5 | Só se houver colunas de negócio: **"Em que funil e etapa esses negócios entram?"** | **Continuar** | `ChoiceSelect`, funil e etapa uma vez só; `Crm::Cards::Creator` com `external_id` e marca de origem no `metadata`; aviso se faltar coluna exigida pelo funil (lição do RD) |
| 6 | **"De onde vieram esses contatos?"** | 3 cartões | Grava a origem, a data e quem importou no lote (seção 5) |
| 7 | **"340 já estão aqui. O que fazer com eles?"** | **Completar só o que falta** (recomendado) / Atualizar com a planilha | Hoje só existe completar (`contact_blank_fields.rb`); "Atualizar" exige guardar o valor antigo e mostra quantos campos mudam |
| 8 | **"Veja como fica"** | **Trazer 1.240 contatos** | Números grandes: "Vamos criar 1.240, completar 340, deixar 12 de fora". 3 fichas de exemplo como vão aparecer (padrão `AutomacaoResumo`). Blocos Pessoa / Empresa / Negócio / Origem com **Alterar** (`StepReview.vue`). Problemas em frase: "12 estão sem telefone. Importar sem eles · Ver quais". Hoje a prévia de empresa só conta, e de card não existe (`company_preview.rb:22-33`) |
| 9 | **"Trazendo seus contatos…"** → **"Pronto"** | **Ver meus contatos** | Progresso real, em segundo plano. Resumo: criados, completados, de fora. Link "Baixar os que ficaram de fora". Botão **Desfazer esta importação** com prazo visível |

**Desfazer:** usar a máquina de estados que já existe (`campaign_import.rb:40-43,104-109`, padrão `undo_labels.rb:36-53`). Para isso, cada linha da importação passa a guardar o que fez: contato criado ou completado e com quais campos e valores anteriores, empresa criada ou ligada, card criado, mudança de tipo. Regras: não apagar contato que já recebeu conversa nem empresa ligada a outro contato (`PRD.md:129-136`).

**Proteções da carga:**
- Eventos de contato silenciados (já é assim).
- Silenciar também o webhook `crm.card.created` (`activity.rb:40`).
- Não chamar automação de etapa.
- Cards importados fora do `StaleCardsJob` e do `Evaluator` até ter conversa (exige código novo).
- `inbox_id` preenchido para o card ser reaproveitado quando o cliente escrever.

---

## 7. Decisões em aberto para o Rodrigo

| # | Decisão | Opções e trade-off | Recomendação |
|---|---|---|---|
| D1 | **Empresa como 3º destino na v1** | (a) Sim: completo, mas depende da flag premium `companies`, sem CNPJ e com nome não único, e a conversa não preenche. (b) Só pessoa e negócio: menor, mas reabre a tela depois | Rodar antes a consulta de adoção (`scratchpad/adocao_relacionamentos.sql`). Se `companies` estiver em menos de cerca de 5% das contas e quase nenhum contato tiver `company_id`, a empresa fica só como "nome da empresa" na v1 |
| D2 | **Criar negócio na importação na v1** | (a) Marcar como cliente sem card: seguro e simples. (b) Card opcional com funil e etapa: entrega a separação completa, mas tem os riscos de IA paga, card duplicado e relatório inflado (seção 2.4) | (a) como padrão e (b) só depois das proteções da seção 6.2 |
| D3 | **Nome do card na interface** | "Negócio" (Agendor, Ploomes, Pipedrive) · "Oportunidade" (atual em `crm.json`) · "Venda" | "Negócio", igual em Relacionamentos e no CRM |
| D4 | **Atualizar quem já existe** | Só completar (hoje) / oferecer "Atualizar" | Completar como padrão; "Atualizar" só com valor antigo guardado e desfazer |
| D5 | **Origem e permissão** | A nada novo · **B uma pergunta por lista** · C permissão por contato e canal | B. Para "Peguei de outro lugar": importar para atendimento e **bloquear campanha**. Não usar o termo "base legal" na tela |
| D6 | **Desfazer: prazo e quem pode** | 48 h só administrador (Pipedrive) / 7 dias para quem tem `contact_manage` | Quem importou ou `contact_manage`, 7 dias (o arquivo original já some em 7 dias, `config.rb:43`) |
| D7 | **Promessa de preenchimento pela conversa** | (a) Só em conversa nova (é o que existe). (b) Construir a leitura do histórico para trás, caminho para contato sem card e regra para atualizar valor (custo de IA novo) | (a) na v1, com texto honesto; (b) como fase própria depois de medir o custo em `crm_ai_usage_events` |
| D8 | **Valor importado trava a leitura para sempre** | Manter / permitir que a conversa atualize valor vindo de planilha | Manter na v1 e mostrar na ficha "Veio da planilha" |
| D9 | **Sincronizar com o upstream antes de remontar** | Antes (custo agora) / depois (conflito garantido) | Antes: `351c96a213` e `e6c21b63de`. A nova página em arquivos próprios |
| D10 | **Consultas de leitura em produção** (adoção das flags, tamanho das bases, cabeçalhos mais comuns em `extra_columns`) | Rodar / não rodar | Rodar com OK, por psql (SSM + `docker exec`), só totais. A separação pessoa/empresa/negócio ainda é **hipótese**: as 68 planilhas da F0 são fictícias (`BATERIA-F0.md:7-10,23`) |
| D11 | **Grupos prontos e "mandar mensagem para esse grupo"** | Na v1 / depois | Grupos prontos na v1 (só filtros). Grupo virar público de campanha fica em fase própria: hoje o público só nasce de planilha (`audience_contacts.rb:7-17`) |
| D12 | **Informações por padrão na ficha** | Todas, com "Não informado" / só as escolhidas | Todas, com busca. O configurador fica para ordenar e esconder, não para fazer aparecer |

---

## 8. Riscos e o que NÃO fazer

**Riscos:**
1. **Card importado aberto gera chamada paga** com conversa vazia e pode mudar de etapa sem evidência (`stale_cards_job.rb:14-19`, `evaluator.rb:12-29`). Nenhum card entra antes da proteção.
2. **Card duplicado** quando o cliente escrever, se faltar `inbox_id` (`auto_create_deduplicator.rb:36-44`).
3. **Relatório inflado:** ganho importado conta no mês corrente (`card.rb:179`, `summary.rb:81`).
4. **Empresas fundidas ou duplicadas** por nome (`company_resolver.rb:5-7,28-33`), e não existe tela para juntar empresas.
5. **Informação de card vale para todos os funis** e pesa no pedido de cada avaliação (`attribute_schema_builder.rb:26-32`).
6. **Conflito com o upstream** nas mesmas telas (seção 3, contexto do fork).
7. **Dado pessoal sem prazo** em `extra_values`.
8. **Guia da Plataforma:** os blocos de `porques.md` mudam (`abrir_relacionamentos`, `ficha_do_contato`, `importar_contatos_*`, `marcar_contato_como_cliente` e outros). Rodar `pnpm guia:build` e `autonomia:guia:formatos:check`. Tela nova sem explicação não passa no PR.
9. **Leitura nova da planilha:** com a flag desligada, o resultado tem de continuar idêntico ao `main` byte a byte (`BATERIA-F0.md:61-91`). Repetir essa prova a cada mudança.

**O que NÃO fazer:**
- Não prometer "preenche sozinho com tudo que o cliente já disse". O código não faz isso.
- Não citar IA, Jev ou modelo na tela.
- Não criar campo pela importação sem descrição e sem exibição, que é o bug de hoje.
- Não exigir ordem de importação, cabeçalho idêntico ou vínculo por nome exato (Agendor, Bitrix, Kommo).
- Não devolver "arquivo de erros" como única saída: corrigir na tela ou importar sem as linhas ruins.
- Não usar arrastar e soltar como único jeito de mapear (Pipedrive) nem construtor de regras E/OU (Kommo).
- Não marcar "aceita mensagens" em massa.
- Não criar card já ganho com a data de hoje.
- Não editar `ContactsList.vue` e `ContactDetails.vue` do upstream: construir em arquivos próprios (construção aditiva no fork).
- Não manter dois editores para o mesmo dado nem o modo `legacy` que esconde campos.
- Não usar `<select>` nativo, caixa alta, emoji em vazio ou `bg-n-brand` com texto branco em botão de texto.
- Não decidir D1, D2 e D5 sem os números de produção (D10).