# E1 (#2894) — o que o backend já tem para cada tela de Relacionamentos

Levantamento só de leitura feito em 11/11/2026 sobre a worktree do protótipo (base da main daquele dia). Cada linha cita o arquivo e a linha lidos. Classe A = existe pronto; B = existe em parte; C = não existe.

A E1 ficou maior do que parecia. O backend já entrega a Ficha da pessoa quase inteira e as escritas simples. Faltam três coisas: os grupos e contagens da Lista, alguns campos de empresa, e o "Trazer". Para o "Trazer", a base mais próxima não é o `DataImport`: é a importação de contatos #1006 (`campaign_imports` com `flow: contacts`). Ela tem prévia e problemas por linha, mas não tem perguntas, conserto de linha, porcentagem nem Desfazer.

Caminhos relativos à worktree `/Users/rodrigosilva/dev/worktrees/chat2you/2894-relacionamentos-prototipo`. Rotas em `config/routes.rb`.

**Formatos que as fontes devolvem hoje** (todo método da fonte real lança `FONTE_REAL_PENDENTE`: `fonte/listaFonte.js:240-252`, `fichaFonte.js:73-81`, `trazerFonte.js:249-267`, `acoesDaListaFonte.js:55-67`):
- **Pessoa:** `id, name, email, phone_number, thumbnail, blocked, contact_type, customer_since, last_activity_at (segundos), created_at, additional_attributes{city, company_name, social_profiles}, custom_attributes{cpf…}, labels[], company_id, opted_out_at, opt_out_source` (`demo/base.js`, `pessoaDoPlano`).
- **Empresa:** `id, name, domain, cnpj, created_at, contacts_count, customers_count, last_activity_at`.
- **Grupos** (`fonte/grupos.js:50-71`):
  - pessoas: `clientes`, `falou_ha_pouco` (≤30d), `sumiu_1_a_3_meses` (30–90d), `sumiu_mais_de_3_meses` (>90d), `nunca_conversou` (sem `last_activity_at`), `nao_quer_mensagens` (`opted_out_at`);
  - empresas: `com_clientes` (`customers_count>0`), `sem_pessoas`, `sem_conversa_3_meses`.

## Lista

| método da fonte | o que a tela precisa | backend existente | classe | o que falta |
|---|---|---|---|---|
| `listar({aba:'pessoas', grupo, busca, ordem, filtros, pagina})` → `{itens, total, temMais}`, 25 por página | linhas de pessoa com os campos acima; busca por nome, e-mail, empresa, telefone e CPF; filtros empresa, etiqueta, cidade e "chegou em" | `ContactsController#index` (`contacts_controller.rb:19`), `#search` (`:28`, procura em name/email/phone/identifier, `:124-127`), `#filter` (`:62` com `Contacts::FilterService`). Rotas `routes.rb:1025-1031`. Ordem: `sort_on` name, last_activity_at, created_at (`:3-7`). JSON em `_contact.json.jbuilder:1-19` | B | (1) 15 por página fixo (`:12`), a tela usa 25. (2) O JSON não traz `labels`. (3) `filter_keys.yml` não tem `contact_type`, `opted_out_at` nem `company_id`, e `last_activity_at` não aceita `is_not_present` (linhas 207-213), então "clientes", "nunca conversou" e "não quer" não dá para filtrar. (4) Busca e filtro são endpoints separados. A busca não olha `company_name` nem `cpf` e não ignora acento. (5) `company_id` só sai com a flag `companies` (`_contact.json.jbuilder:15`) |
| `listar({aba:'empresas'…})` | `name, domain, cnpj, contacts_count, customers_count, last_activity_at` | `CompaniesController#index`/`#search` (`enterprise/.../companies_controller.rb:16,25`), 25 por página, ordena por name, domain, created_at, last_activity_at e contacts_count (`:3-7`). JSON em `enterprise/app/views/api/v1/models/_company.json.jbuilder:1-12` | B | `cnpj` fica em `additional_attributes.cnpj` (índice em `db/schema.rb:1993`), mas o JSON só passa `city` (`_company.json.jbuilder:7`). `customers_count` não existe (`schema.rb:1982-1997`). Não há filtro por grupo. A busca é só por nome e domínio (`:31`) |
| `contagens(aba, {busca, filtros})` → `{grupoId: n}` | número de cada pílula, respeitando busca e filtros | não achei | C | endpoint novo de contagem por grupo (`COUNT(*) FILTER` por grupo), com o mesmo escopo da lista |
| `resumo()` → `{total, clientes, sumiu_1_a_3_meses, empresas:{total, sem_conversa_3_meses}}` | frase do topo | `ContactsController#summary` (`:24`) e `CompaniesController#summary` (`:21`) usam `Relationships::Summary` (`app/services/relationships/summary.rb:3-28`). Rotas `routes.rb:1004,1027` | B | as métricas são outras e de 30 dias (`new_in_period`, `active_in_period`, `with_company`, `inactive_in_period`). Faltam clientes, 30–90d e empresa >90d |
| `listarTodos(pedido)` → `{itens, total}` | "Marcar todas as N" | não achei | C | endpoint que devolva os ids da consulta inteira, ou a ação em grupo aceitar a própria consulta em vez de ids |
| `opcoesDeFiltro()` → `{empresas, etiquetas, cidades}` | opções da gaveta "Mais filtros" | etiquetas: `LabelsController#index` (`labels_controller.rb:5`, `routes.rb:1160`). Empresas: `companies#index`, paginado | B/C | cidades: não achei endpoint de valores distintos. Empresas vêm paginadas (25) |
| `acoes.funis()` → `[{id, nome, etapas:[{id, nome}]}]` | escolher funil e etapa | `Crm::PipelinesController#index` (`crm/pipelines_controller.rb:11`) e `stages#index` (`routes.rb:327`) | B | o JSON do funil não traz etapas (`_pipeline.json.jbuilder`), são 1+N chamadas. Exige CRM ligado (`crm/base_controller.rb:2`) |
| `acoes.etiquetas()` → `[string]` | lista de etiquetas | `labels#index` | A | — |
| `acoes.criarCards({pessoas, funilId, etapaId})` → `{criados, deFora:[{id, nome, motivo}]}` | um card por pessoa; quem já tem card fica de fora com o motivo | só por card: `Crm::CardsController#create` (`cards_controller.rb:84`, params `:596`). Em lote, só para leads da Prospecção (`prospecting/leads_controller.rb:67`, `CrmCardBatch` com no máximo 30) | C | lote a partir de contatos. Não há regra de "já tem card neste funil": `Crm::Card` não valida isso (`app/models/crm/card.rb:133-141`) |
| `acoes.aplicarEtiqueta({pessoas, etiqueta})` → `{aplicadas}` | etiquetar em lote | `BulkActionsController#create` type Contact (`bulk_actions_controller.rb:7-9`, `routes.rb:101`) roda em job (`Contacts::BulkAssignLabelsService`) | B | é assíncrono e responde `head :ok`, sem contagem |
| `acoes.apagar({pessoas})` → `{apagadas}` | apagar em lote | mesmo endpoint com `action_name:'delete'` e `Contacts::BulkDeleteService` (`bulk_delete_service.rb:10-16`) | B | assíncrono e sem contagem. Contato que não sai só aparece na Auditoria (`:40-45`) |
| (Mandar mensagem) | — | não passa por nenhuma fonte (`useEnvio.js` só embrulha uma ação) | — | fora do escopo das fontes |

## Ficha da pessoa

| método | o que a tela precisa | backend existente | classe | o que falta |
|---|---|---|---|---|
| `pessoa(id)` | os campos de pessoa, mais `social_profiles` e `labels` | `contacts#show` (`contacts_controller.rb:60`) | B | `labels` não sai no JSON. Etiquetas vêm à parte em `contacts/:id/labels` (`routes.rb:1042`) |
| `conversas(id)` → `[{id, canal, trecho, quando, situacao}]` | últimas conversas | `Contacts::ConversationsController#index` (`contacts/conversations_controller.rb:6-12`), 25 mais recentes, filtradas por permissão (`:25-30`) | A | só precisa mapear canal, status e última mensagem do JSON da conversa |
| `cards(id)` → `[{id, titulo, funil, etapa, valor, situacao}]` | cards da pessoa | `Crm::ContactOpportunitiesController#index` (`crm/contact_opportunities_controller.rb:3-10`, `routes.rb:314`), JSON em `profile_opportunities_controller.rb:49-54` | B | 5 por página fixo (`:4`). O padrão `active` tira os arquivados. Valor oculto sem `sales_value_view` (`:53`) |
| `notas(id)` → `[{id, autor, quando, texto}]` | notas | `Contacts::NotesController#index` (`contacts/notes_controller.rb:6-8`, `routes.rb:1044`), JSON em `_note.json.jbuilder` | A | — |
| `arquivos(id)` → `[{id, nome, tipo, quando}]` | arquivos das conversas | `Contacts::AttachmentsController#index` (`contacts/attachments_controller.rb:6-19`, `routes.rb:1052`), 100 por página | B | não há campo de nome do arquivo, só `data_url` e `extension` (`_attachment.json.jbuilder:3-13`) |
| `origem(id)` → `{tipo:'lista', nome, quando}` ou `{tipo:'canal', canal, quando}` | de onde a pessoa veio | `CampaignJourney::ContactOriginsController#show` (`contact_origins_controller.rb:8-13`, `routes.rb:284`): marcas de anúncio e públicos | B/C | as importações de contato (#1006) ficam de fora de propósito (`:46-53`). O "canal da primeira conversa" não sai pronto (conversas vêm da mais nova para a mais antiga, até 25) |
| `salvar(id, dados)` | name, email, phone, additional e custom attributes | `contacts#update` (`:96-102`, mescla attributes `:189-205`). `company_id` pela versão enterprise (`enterprise/.../contacts_controller.rb:21-33`) | A | o demo zera `company_id` quando o nome da empresa muda (`demo/ficha.js:298-307`). O backend não faz isso: decisão de regra |
| `marcarCliente(id)` | vira cliente | `Contacts::CustomersController#create` (`contacts/customers_controller.rb:6-9`, `routes.rb:1046`) | A | — |
| `guardarNota(id, texto)` | cria nota | `NotesController#create` (`:12-14`) | A | — |
| `liberarMensagens(id)` | tira a recusa | `Contacts::OptOutsController#destroy` (`contacts/opt_outs_controller.rb:17-24`, `routes.rb:1045`) | B | só desfaz recusa `manual` e `campaign_reply` (`:8,18-20`). As outras (`prospecting`, `email_unsubscribe`, `follow_up_reply`, em `contact_opt_out.rb:23-29`) respondem 422, e a tela precisa explicar isso |

## Ficha da empresa

| método | o que a tela precisa | backend existente | classe | o que falta |
|---|---|---|---|---|
| `empresa(id)` | name, cnpj, domain, contacts_count, customers_count, last_activity_at | `companies#show` (`companies_controller.rb:36`) | B | `cnpj` não sai (`_company.json.jbuilder:7`) e `customers_count` não existe |
| `pessoasDaEmpresa(id)` | pessoas completas | `Companies::ContactsController#index` (`companies/contacts_controller.rb:15-18`, `routes.rb:1012`) | B | 15 por página, ordem por nome. Confirmar se usa o mesmo JSON de contato (não abri `companies/contacts/_contact`) |
| `conversasDaEmpresa(id)` → também `pessoa` | conversas das pessoas da empresa | `Companies::ConversationsController#index` (`companies/conversations_controller.rb:4-14`, `routes.rb:1021`), as 20 mais recentes | A | — |
| `cardsDaEmpresa(id)` → também `pessoa` | cards da empresa | `Crm::CompanyOpportunitiesController#index` (`company_opportunities_controller.rb:6-18`, `routes.rb:322`, só enterprise), com `include_contact` | B | 5 por página. O demo devolve todos |
| `salvarEmpresa(id, {name, cnpj, domain})` | gravar | `companies#update` (`:43-45`), mescla `additional_attributes` (`:110-116`) | B | grava `additional_attributes.cnpj`, mas não devolve. Sem validação de CNPJ (só índice único) |

## Trazer minha lista

Base para comparar: `ContactImportsController` (`contact_imports_controller.rb`, `routes.rb:300-307`).

| método | o que a tela precisa | backend existente | classe | o que falta |
|---|---|---|---|---|
| `ler(arquivo)` → `{id, arquivo, colunas[{nome, destino, duvidosa}], perguntas[], resumo{total, novas, completadas, comProblema}, exemplos[3], problemas[]}` | enviar, ler e mostrar a prévia | `#create` (`:28-37`) e depois `ValidateJob` (assíncrono). `#show` (`:24`) devolve `schema_resolution`, `validation_summary` (com `existing_contacts`, `contact_attributes`, `attribute_problems`, em `contact_imports/validator.rb:12-17`), `total_rows`/`valid_rows`/`invalid_rows` e os 20 primeiros `problem_rows` (`show.json.jbuilder:5-12`) | B | leitura assíncrona (exige consulta repetida). Sem `exemplos` (`sample_contact` só existe para públicos, `campaign_import_audiences_controller.rb:139`). Sem `perguntas`. Destinos só `name/phone/email/company` (`spreadsheet_reader.rb:12`), sem cidade, cliente ou telefone da empresa |
| `responder(leituraId, respostas)` | "são clientes?" e "esse telefone é de quem?" | não achei | C | guardar respostas em `options`. O importador marcar cliente (`become_customer!`) e gravar telefone da empresa |
| `trocarDestino(leituraId, coluna, destino)` | mudar o destino da coluna | `#columns` (`:40-50`, `ColumnChoice`, `DraftChanges#choose_columns`) | B | aceita só índices de `name/phone/email/company`, não destinos livres (cidade, informação, não guardar) |
| `consertar(leituraId, linha, valor)` | corrigir a linha | não achei | C | endpoint por linha. As linhas guardam só o telefone e o e-mail mascarados (`campaign_import_rows`, `schema.rb:1432-1460`), não o valor cru |
| `deixarDeFora(leituraId, linha)` / `reabrir(…)` | estado por linha | não achei. Linha inválida já fica de fora automaticamente | C | um estado manual por linha |
| `trazer(leituraId)` → `{trazidaId}` | confirmar | `#confirm` (`:64-77`) e `ImportJob` | A | — |
| `andamento(trazidaId)` → `{porcentagem, situacao, total, novas, completadas}` | barra de progresso | `#show`: `status`, `imported_contacts_count`/`existing_contacts_count` (só gravados no fim, `importer.rb:162-174`) | B | `processed_records` existe (`schema.rb:1480`), mas o importador não grava e o JSON não mostra. Dá para tirar a porcentagem de `rows.status_imported.count / valid_rows`, só que não está exposto |
| `historico()` → `[{id, arquivo, quando, quem, total, situacao, porcentagem}]` | listas trazidas | `#index` (`:17-22`, `index.json.jbuilder:1-23`) | B | não traz o nome do arquivo (comentário `:1`, está só no `show`) nem a porcentagem. Situações diferentes das da tela (enum `campaign_import.rb:86-104`) |
| `previaDoDesfazer(id)` → `{tira, ficam, devolve}` | quem sai, fica ou volta | não achei | C | ver o detalhe abaixo |
| `desfazer(id)` | desfazer | `#destroy` só vale para rascunho (`deletable?` em `campaign_import.rb:153-157`). `undo_labels` é só para campanha e só tira etiquetas (`campaign_imports_controller.rb:79-110`, `undo_labels.rb:15-25`) | C | job novo de desfazer |

**O que as tabelas já guardam e o que não guardam:**
- **`data_imports`** (`schema.rb:3637-3662`, o caminho antigo `contacts#import`, `contacts_controller.rb:34-43`, mais `DataImportJob`):
  - guarda: `status, total_records, processed_records, processing_errors`, o anexo `failed_records`, `stats`/`cursor`/`source_*` (para Intercom e Freshdesk);
  - não guarda qual contato foi criado ou atualizado. `data_import_items` e `data_import_mappings` (`:3601-3636`) só servem às integrações. O job faz `Contact.import(... on_duplicate_key_ignore)` (`data_import_job.rb:73-80`). Não serve como base.
- **`campaign_imports` (#1006)** (`schema.rb:1462-1519`):
  - guarda: arquivo, `user_id`, contagens (`total/valid/invalid_rows`, `imported/existing/failed_contacts_count`, `new_contacts_count`, `existing_contacts_updated_count`), contadores de empresa, `undo_status` e as datas de desfazer;
  - guarda por linha: `contact_id`, **`was_existing_contact`** (criado ou já existia, `importer.rb:152-159`), `company_id`, `company_result`, `extra_values`, `error_messages`.
- **O que nenhuma tabela guarda:**
  - os valores anteriores do contato. `ContactBlankFields#fill!` só preenche campos vazios (`contact_blank_fields.rb:13-19`) e `CustomAttributes#merge!` só acrescenta chaves (`custom_attributes.rb:31-39`), mas nenhum registra o que preencheu;
  - a marca de "passou a ser cliente por esta lista";
  - o sinal de "a pessoa nova já conversou" (para o `ficam`). Dá para calcular na hora: contato com `was_existing_contact=false` que tem conversa ou card.

## Permissões, escopo e flags

- **Agente sem função personalizada** lê e grava todo contato e empresa (`enterprise/app/policies/relationships/record_permissions.rb:10,17`). Com função: leitura exige `contact_view` e escrita exige `contact_manage` (`:12,19`).
- **Importar:**
  - só administrador no OSS (`app/policies/contact_policy.rb:10-12`);
  - na enterprise, quem tem `contact_manage` também pode (`enterprise/app/policies/enterprise/contact_policy.rb:73-75`);
  - mas a rota `trazer` libera `agent` e `contact_view` (`relacionamentos.routes.js:13-19`), então um agente abre a tela e toma 403. A tela precisa esconder o botão;
  - o importador confere de novo a permissão de quem enviou o arquivo (`importer.rb:21,113-119`).
- **Apagar** exige `contact_delete` (`enterprise/.../contact_policy.rb:69-71`, `company_policy.rb:36-38`). O lote autoriza pela classe (`bulk_actions_controller.rb:42-44`).
- **Variáveis de ambiente:** a importação de contatos depende de `CAMPAIGN_JOURNEY_ENABLED` e `CAMPAIGN_IMPORT_ENABLED` e responde 404 sem elas (`contact_imports/config.rb:6-8`, `campaign_imports/config.rb:7`).
- **Flags de conta:**
  - `companies` é premium (`features.yml:231-234`); sem ela `company_id` some do JSON e as rotas de empresa dão 403;
  - CRM: `ensure_crm_enabled`;
  - `crm_v2` muda quem entra na lista (`contact.rb:203-211`).
- **Visibilidade:** conversas, anexos e origem passam por `PermissionFilterService`, mas a lista e os grupos (por `last_activity_at`) não. Quem não vê a caixa de entrada ainda vê que a pessoa "falou há pouco".
- **Significado de `last_activity_at`:** só é atualizado quando o contato manda mensagem (`message.rb:472`). Campanha enviada não conta como "falou".
- **`relacionamentos_novo`:** em `features.yml:1344-1347`, desligada por padrão, coluna `feature_flags_ext_2`. No backend só existe nesse arquivo; nenhum controller confere a flag. Os endpoints novos não são protegidos por ela a menos que se adicione a checagem.
- **Problemas por linha:** vêm mascarados e sem nome (`show.json.jbuilder:5`). A tela mostra o valor para corrigir (`demo/trazer.js:61-97`), então há um conflito de privacidade.

## Trabalho de backend da E1, em ordem

1. Adicionar `labels` ao JSON de contato, ou uma opção `include_labels`, e deixar escolher quantos por página (25).
2. Abrir o filtro (`filter_keys.yml` e `FilterService`) para `contact_type`, `opted_out_at`, `company_id` e `last_activity_at is_not_present`, ou criar um `Relationships::Grupos` que traduza `grupo` em escopo.
3. Endpoint de contagem por grupo (pessoas e empresas) com o mesmo escopo de busca e filtro, e ampliar `Relationships::Summary` com clientes, 30–90d e empresas >90d.
4. Busca única com filtros, incluindo `company_name`, `cpf`, CNPJ e sem acento (já existe o índice `idx_contacts_nome_sem_acento_trgm`, em `schema.rb:2042`).
5. Endpoint de ids da consulta inteira, para "Marcar todas" e as ações em grupo.
6. Empresa: expor `cnpj` no JSON, adicionar `customers_count` (contador ou subconsulta) e filtros de grupo.
7. Cidades distintas para a gaveta, e funis com etapas numa chamada só.
8. Criar cards em lote a partir de contatos, no padrão do `CrmCardBatch`, com a regra de "já tem card aberto no funil" e o resultado criados/de fora.
9. Lote de etiquetar e apagar com resposta síncrona e contagem, ou um id de tarefa para consultar.
10. Origem "veio da lista X" a partir de `campaign_import_rows` das importações de contato, mais o canal da primeira conversa.
11. Trazer (sobre o #1006):
    - expor porcentagem e nome do arquivo no índice;
    - destinos novos (cidade, cliente, telefone da empresa, não guardar);
    - respostas das perguntas em `options`;
    - estado manual por linha (consertar, deixar de fora, reabrir), o que exige guardar o valor cru;
    - exemplos na prévia.
12. Desfazer importação:
    - colunas novas em `campaign_import_rows`: campos preenchidos e valores anteriores, chaves de `custom_attributes` acrescentadas, virou cliente;
    - endpoint de prévia (`tira`/`ficam`/`devolve`) e um `UndoJob` com status próprios.

## Dúvidas que só o dono decide

1. "Falou há pouco" deve contar só mensagem recebida do contato (como `last_activity_at` funciona hoje) ou também mensagem enviada e campanha?
2. Os grupos e contagens da Lista devem respeitar as caixas de entrada que cada pessoa vê, ou valem para a conta toda, como a lista de contatos hoje?
3. Na conferência de problemas, a tela pode mostrar o telefone e o e-mail sem máscara para corrigir? Hoje o #1006 grava só a versão mascarada.
4. "Desfazer" apaga de vez as pessoas novas sem conversa (com a mesma anonimização de cards do LGPD #2096) e devolve os valores antigos? Vale sem prazo, como diz `trazer/prazo.js:1-2`?
5. Quem pode "Trazer minha lista": só administrador e `contact_manage`, como hoje, ou também o agente comum, como a rota da tela sugere?
6. Os endpoints novos devem ser fechados pela flag `relacionamentos_novo` no backend, ou ficam abertos e só as telas dependem dela?

## Respostas do dono do épico às dúvidas acima (11/11/2026, a vetar pelo Rodrigo)

1. **"Falou há pouco"** conta só mensagem que a pessoa mandou, como `last_activity_at` já funciona. É o que a palavra diz: a pessoa falou. Campanha enviada não conta.
2. **Grupos e contagens** valem para a conta toda, como a lista de contatos de hoje. Não crio restrição nova por caixa de entrada. Vai no parecer de Funções da E1.
3. **Conferir problemas:** a tela mostra o telefone e o e-mail sem máscara para quem trouxe a planilha poder corrigir (é o dado que a própria pessoa enviou). O valor cru das linhas com problema fica guardado só até a lista ser concluída ou desfeita, e some depois. Alinhar com a Campanhas (dona do #1006) na E3.
4. **Desfazer** tira de vez as pessoas novas que ainda não conversaram nem receberam campanha, devolve os valores antigos das que já estavam e não tem prazo. Já está no plano e na Issue #2896.
5. **Quem pode trazer lista:** qualquer atendente (decisão assumida em 11/11, a vetar). Hoje o backend só deixa administrador ou `contact_manage`: muda a policy na E3, com parecer de Funções. Até lá a tela esconde o botão de quem tomaria 403.
6. **Flag no backend:** todo endpoint novo confere `relacionamentos_novo` e responde 404 com ela desligada.

## Consequência para o plano

A E1 (Lista e Ficha lendo a base real) cabe no que existe mais os itens 1 a 10 da lista de trabalho. O "Trazer" (itens 11 e 12) é a E3 e é a parte grande: precisa de colunas novas em `campaign_import_rows`, logo migration aditiva e PR próprio. A base certa é a importação de contatos do #1006 (`campaign_imports` com `flow: contacts`), não o `DataImport` antigo.
