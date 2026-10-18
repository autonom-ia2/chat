# Funções personalizadas — diagnóstico e proposta (17/10/2026)

**Base:** `origin/main` em `f19cb23b5a`, depois do `git fetch` de hoje. Os levantamentos foram feitos em `f2488a9e9a`. Entre os dois commits, `git diff --stat` não mostra nenhuma mudança nos arquivos de permissão (policies, models EE, `search_service.rb`, listeners, `app/services/crm`, `customRoles/` e controllers EE). Por isso as linhas citadas continuam valendo.
**Método:** só leitura de código, com 6 levantamentos, uma rodada de verificação (que confirmou ou refutou cada gap) e 3 propostas (UX, segurança e hierarquia). Nada foi executado no painel nem em produção.
**Convenção:** **Fato** = visto no código. **[HIPÓTESE]** = deduzido e ainda não reproduzido.
**Revisado pelo chat Multifunnel (17/10):** ressalvas incorporadas nas seções 3 (A3, A5), 5 e 7 (D2, D9).

---

## 1. Resumo em 10 linhas

1. A função personalizada é uma lista de chaves por pessoa: 38 no fork, 6 no Chatwoot original. Não tem escopo por caixa, funil ou time, e não existe gestor.
2. A tela de funções (8 perfis + matriz de 18 módulos) cobre as 38 chaves, mas promete coisas que o servidor não cumpre.
3. **Brecha crítica:** a busca global ignora as chaves de conversa. Quem tem função "só as minhas" busca e lê conversas e mensagens de colegas nas caixas dela.
4. **Brechas altas:** o tempo real (websocket) entrega mensagens sem olhar a função; "Contatos: nenhum" não vale na API; ação em massa no CRM só confere "ver"; o callback do Facebook cria caixa sem autorização; o CRM mostra o resumo da IA de conversas alheias.
5. Excluir uma função, ou um PATCH de agente sem `custom_role_id`, devolve a pessoa a "Agente" padrão. Isso **amplia** o acesso dela sem aviso.
6. A permissão é conferida de 4 jeitos diferentes no servidor e refeita no front. Daí vêm os botões que dão 403 e os textos que mentem (ex.: "pegar da fila" no perfil Atendente).
7. "Quem vê o quê" fica espalhado entre função, membro da caixa e acesso por funil (#1148). Nenhuma tela mostra o resultado combinado.
8. Nenhum teste obriga uma rota nova a declarar quem acessa (zero `verify_authorized`). As brechas nascem assim, e o Guia, que age como a pessoa, também as alcança.
9. **Recomendação:** primeiro fechar as brechas (Lote 0), depois criar uma fonte única de verdade no servidor (catálogo + cálculo "o que a pessoa vê"), e só então a jornada nova de "Cargos" para leigo, com mockup aprovado e desenhada junto com a #1149 e o Multifunnel.
10. A hierarquia "gestor vê o time" foi deixada fora do #1140 de propósito. Reabrir é decisão sua (seção 7).

---

## 2. Situação atual

### 2.1 Modelo
- Tabela `custom_roles`: `name`, `description`, `account_id` e `permissions text[]`. Mais `account_users.custom_role_id` (`db/migrate/20240726220747_add_custom_roles.rb:4-14`). Uma função por pessoa.
- O model existe só no EE: `enterprise/app/models/custom_role.rb`. Catálogo nas linhas 59-98. Validação de inclusão em 104-109. `has_many :account_users, dependent: :nullify` na linha 53. Nome valida só presença (linha 100).
- OSS: `role` = agent/administrator (`app/models/account_user.rb:36`). `permission_granted?` = `administrator?` (73-75).
- EE: `permissions` = chaves da função + `'custom_role'`, sem conferir se a pessoa é admin (`enterprise/app/models/enterprise/account_user.rb:2-4`). `permission_granted?` aplica `_manage ⇒ _view` (7-14).
- Flag `custom_roles` premium, desligada por padrão (`config/features.yml:147-150`).
- Os tokens de integração criam funções "gerenciadas" na mesma tabela, `crm_integration_<hex>` e `mcp_integration_<hex>` (`crm/integration_token.rb:97-101`, `mcp/integration_token.rb:97-101`), sem marcador.

### 2.2 Servidor — quatro jeitos de conferir
| Mecanismo | Onde | Semântica |
|---|---|---|
| `permission_granted?` | `enterprise/.../account_user.rb:7-14`, `api/base_controller.rb:28-35` | manage implica view |
| `include?` direto | `enterprise/.../report_policy.rb:3`, `csat_survey_response_policy.rb:3-15`, `enterprise/contact_policy.rb:21-25`, `service_schedule_policy.rb:28-29`, `call_finder.rb:38` | sem implicação |
| `CrmPermissions` | `enterprise/app/policies/crm_permissions.rb:19-30` | `crm_admin` cobre tudo; agente sem função recebe tudo menos 4 chaves; manage **não** implica view |
| Filtro de conversas | `enterprise/.../permission_filter_service.rb:18-44`; `enterprise/.../conversation_policy.rb:2-29` | lista usa `if/elsif` exclusivo; abertura soma as chaves (OU) |

Zero `verify_authorized`. Cada controller se protege por conta própria. As bases de Contacts e CRM não autorizam nada (`contacts/base_controller.rb:1-9`, `crm/base_controller.rb`).

### 2.3 Tela
- Rotas: `settings/customRoles/customRole.routes.js:9-13` (admin + flag). Menu em `Sidebar.vue:1357-1362`.
- Lista: cartões com botões só de ícone (`CustomRoleCard.vue:54-81`). Excluir abre um modal genérico (`Index.vue:183-192`).
- Passo 1, ProfilePicker: 8 perfis em 4 grupos (`permissionMatrix.js:436-507`).
- Passo 2, editor: 18 módulos, seletor de 3 posições e ajustes finos (`CustomRoleEditor.vue:277-458`, `permissionMatrix.js:36-190`). Presets em 340-432.
- Atribuir: pelo `AssignAgentsDialog` (só ao criar) ou pelo ChoiceSelect em Agentes (`EditAgent.vue:120-145`, `AddAgent.vue:83-108`). Já não há `<select>` nativo nessas telas.
- O front decide permissão em vários pontos: `useCanManage.js`, `useCrmPermissions.js`, `Sidebar.vue:186-262` e `meta.permissions` das rotas.

### 2.4 CRM e hierarquia (cruzamento com o Multifunnel)
O acesso a conversas passa por **3 camadas**, aplicadas em interseção:
1. **Caixa** (Chatwoot): `app/services/conversations/permission_filter_service.rb:21-27`. Pelo link, também time (`conversation_policy.rb:33-37`).
2. **Função**: as chaves `conversation_*` (EE).
3. **Funil** (#1148): `Crm::InboxAgentAccess` (`app/models/crm/inbox_agent_access.rb:3-22`) via `Crm::Access::ConversationScope`, que "só RESTRINGE" (`conversation_scope.rb:15`). Só admin e integração ficam livres (122-125).

Outros pontos:
- Funis visíveis: `crm/access/visible_pipelines.rb`. Cards: `crm/cards/visible_scope_query.rb:20-48` + `card_scope.rb`. Escrita no card: `card_guard.rb:26-62`.
- O CRM **não lê** as chaves de conversa da função (`crm/conversations/visibility.rb:9-43`).
- **Team** não entra em nenhum serviço de acesso do CRM, mesmo com `crm_cards.team_id` existindo (`card.rb:32`).
- Não existe gestor → subordinados: o #1140 deixou isso fora (`docs/multifunil/PLANO.md:40`). A tela #1149 "Quem vê o quê" está pausada desde 12/10 para redesenho.
- Configurar "quem vê o quê" exige `crm_admin` (`enterprise/.../inbox_agent_access_policy.rb:5-11`). O `Gravador` não impede a pessoa de mexer na própria linha (`crm/caixas/gravador.rb:248-252`).

### 2.5 Cobertura de módulos (módulo × chave × matriz × servidor × rota × menu)
| Módulo | Chave | Matriz | Servidor | Rota | Menu |
|---|---|---|---|---|---|
| Conversas | conversation_manage / unassigned / participating | sim | filtro EE + policy; **busca e websocket não** | — | — |
| Contatos | contact_view / contact_manage | sim | escrita sim; **leitura não** (`contact_policy.rb:2-44`) | sim | sim |
| Relatórios | report_manage (só leitura) | sim | `report_policy.rb:3` | sim | sim |
| Central de ajuda | knowledge_base_view / manage | sim | só leitura para todos (`article_policy.rb:12-16`) | sim | sim |
| CRM | crm_* (8) | sim | `CrmPermissions`; **em massa só index?** | sim | regra própria |
| Agentes de IA | autonomia_view / manage | sim | `autonomia/base_controller.rb:48-50`; ferramentas só SuperAdmin (`agents/tools_controller.rb:2,48-50`) | sim | sim |
| Prospecção | prospecting_* (3) | sim | `prospecting/base_controller.rb:3` | sim | sim |
| Cotação (Lia) | insurance_view / manage | sim | `insurance/base_controller.rb:3` | sim | sim |
| Campanhas + e-mail + brand kit | campaign_view / manage | sim | policies; reputação e layouts só admin | sim | parcial |
| Modelos WhatsApp | whatsapp_templates_* | sim | 3 regras diferentes (ver gap A14) | nova sim; antigas só admin | filtro de rota |
| Anúncios Meta | **nenhuma** | não | só admin, inclusive leitura | admin | admin |
| Caixas (+ Instagram, híbrido, WAHA) | inbox_view / manage | sim | `inbox_policy.rb`; **Facebook callback sem gate** | sim | sim |
| Respostas prontas | canned_response_manage | sim | `canned_response_policy.rb:19` | — | — |
| Automações / Decisores | automation_* | sim | sim | sim | filtro de rota |
| Agendamento | agendamento_* | sim | sim; perfis do agente só admin | sim | sim |
| Etiquetas / Atributos / Macros / SLA | label / attribute / macro / sla_manage | sim | sim | sim | sim |
| Importação de dados | **nenhuma** | não | só admin (`data_import_policy.rb`) | admin | — |
| Financeiro | nenhuma (decisão: só admin) | não | só admin | admin | admin |
| Custo de IA do CRM | crm_view_reports | dentro de CRM | **agente comum passa** (`ai_usage_controller.rb:25-36`) | inclui 'agent' | — |
| Guia da Plataforma | nenhuma (decisão: qualquer membro) | não | age como a pessoa (`autonomia/guide/acoes.rb:8-12`) | widget | widget |
| Relacionamentos/Empresas | contact_* + attribute_manage | indireto | conta inteira, sem funil | sim | sim |

---

## 3. Gaps confirmados, por severidade

### Crítica
**C1. A busca global ignora as chaves de conversa.**
- Prova: `search_controller.rb:1-34` sem `authorize`. `search_service.rb:26,34,108-113` filtra só por caixa e funil. Mesma coisa no EE em `enterprise/.../search_service.rb:20-24`.
- Impacto: quem tem função "só as minhas" ou nenhuma chave de conversa lê conversas e mensagens dos últimos 3 meses de qualquer colega das caixas dela. É dado de cliente final.

### Alta
**A1. O tempo real (ActionCable) entrega a todo membro da caixa.**
- Prova: `action_cable_listener.rb:44,52,60-90,136-152`. `crm/access/recipients.rb:12-14`. Nenhuma referência a `custom_role` em `app/listeners`.
- Impacto: o dado chega ao navegador mesmo quando a lista o esconde. [HIPÓTESE] O front pode descartar o evento.

**A2. `contact_view` / "sem acesso a contatos" não vale na leitura.**
- Prova: `contact_policy.rb:2-44` (todas as leituras retornam true). `enterprise/contact_policy.rb:4-26` cobre só escrita. `company_policy.rb:4-18`. `search_service.rb:171-182`.
- Impacto: a função sem Contatos lista e busca a base inteira (nome, telefone, e-mail). O token MCP também.

**A3. A ação em massa do CRM só confere `crm_view`.**
- Prova: `crm/cards/bulk_controller.rb:7`. `bulk_action.rb:127-131`. `card_guard.rb:39-44`.
- Impacto: quem só vê move, troca dono, fecha e arquiva até 100 cards por chamada.
- Confirmado pelo Multifunnel (17/10): nenhum PR dele cobre. Correção: autorizar por ação e por card dentro do `BulkAction`, reaproveitando a `CardPolicy` (mover → `move?`; dono/status/excluir → `update?`/`destroy?`). Entra no Lote 0.

**A4. O callback do Facebook cria caixa e troca token sem autorização.**
- Prova: `callbacks_controller.rb:1-24,45-57`.
- Impacto: qualquer agente cria caixa e troca credencial, quando isso deveria exigir `inbox_manage`.

**A5. O CRM ignora as chaves `conversation_*` e vaza resumo da IA, conversa de origem e toques de campanha.**
- Prova: `crm/conversations/visibility.rb:9-43`. `visible_scope_query.rb:20-28`. `payload_builder.rb:39,129-131,270-272,301-321`.
- O Copiloto **não** vaza (`conversation_copilot_controller.rb:61`).
- Precisão (conferido 17/10): o resumo da IA **tem** portão — `payload_builder.rb:128-129` só o mostra se `primary_conversation_visible?`. O furo está no portão: `Crm::Conversations::Visibility#visible?` (`visibility.rb:9-15`) olha caixa, "só atribuídas" e funil, mas não as chaves `conversation_*` da função. Uma função "só as próprias conversas" numa caixa comum vê o resumo da conversa do colega. Mesma causa da C1 (busca).

**A6. Excluir uma função amplia o acesso de quem a usava, sem aviso.**
- Prova: `custom_role.rb:53` (nullify). `custom_roles_controller.rb:20-21`. Modal genérico em `pt_BR/customRole.json:245-250`. Agente padrão: `Sidebar.vue:226-237` e `permission_filter_service.rb:11-15`.
- Fica dentro da conta e é disparado por admin.
- Tokens: **refutado**. Ficam sem função e falham fechados (`access_token_auth_helper.rb:51-57,84-87`).

**A7. PATCH de agente sem `custom_role_id` apaga a função.**
- Prova: `enterprise/.../agents_controller.rb:9-12,23,27-28`.
- Impacto: API, scripts e Guia rebaixam a pessoa para agente padrão, que tem mais acesso. As telas sempre mandam o campo.

**A8. O perfil Atendente promete "pegar da fila" e não dá essa permissão.**
- Prova: `permissionMatrix.js:341-347,258-263,441-442`. `pt_BR/customRole.json:374`.

**A9. `crm_admin` delega tokens de integração e "quem vê o quê", inclusive a própria restrição.**
- Prova: `crm_permissions.rb:17,29`. `inbox_agent_access_policy.rb:4-11`. `integration_tokens_controller.rb:19-58`. `gravador.rb:248-252`.
- Contraria a regra do CLAUDE.md ("Nunca delegar ... tokens ... segurança"), mas o código registra a escolha como decisão. Precisa da sua decisão.

**A10. Duas (ou três) fontes da verdade para "quem vê quais conversas".**
- "Todas" da função continua cortado pelo funil, sem a tela mostrar.
- Prova: `conversation_scope.rb:15,122-125`. `retrato.rb:115-135` (sem a função). Presets `ALL` em `permissionMatrix.js:348-406`.
- O dano é acesso a menos e confusão, não vazamento.

**A11. Não existe "ler sem operar" (`conversation_view`).**
- Prova: `custom_role.rb:20-22,59-98`. O preset Somente leitura não tem conversas (`permissionMatrix.js:417-431`).

**A12. Não existe gestor → time. Team não entra na lista nem no CRM.**
- Prova: nenhuma ocorrência de team em `crm/access/*`. `conversation_policy.rb:33-37` contra `permission_filter_service.rb:21-27`.
- Atenção: ser membro do time põe a pessoa no rodízio de conversas (`assignment_handler.rb:21-28`, `auto_assignment_handler.rb:42-53`). O gestor não pode virar membro só para enxergar.

**A13. Anúncios Meta sem chave, só admin até para leitura.**
- Prova: `meta_ads_connection_policy.rb:1-21`. `meta_ads_connections_controller.rb:40-42`. #1158.

### Média
- **M1. Quatro mecanismos de checagem.** Ver 2.2. No CRM, `crm_manage_cards` sem `crm_view` cria card mas não edita (`card_policy.rb:16-23`).
- **M2. Front e back divergem sobre o agente comum no CRM.** Botões de funil e IA dão 403 (`useCrmPermissions.js:36,42-43` contra `crm_permissions.rb:19,26`).
- **M3. Admin com função perde as telas de admin no front.** O servidor segue admin (`enterprise/account_user.rb:2-4`, `EditAgent.vue:181-186`). O `AssignAgentsDialog` filtra admins (29-31); a tela de Agentes não.
- **M4. Sem audit.** `custom_role_id` e as chaves da função não ficam registrados (`enterprise/audit/account_user.rb:5-11`).
- **M5. "Não atribuídas" + "participando".** A lista e os contadores aplicam só uma; a abertura soma (`permission_filter_service.rb:21-29`, `counter.rb:161-172`, `conversation_policy.rb:7-10`). A UI as oferece como independentes e o preset SDR liga as duas.
- **M6. Linear.** Cria e vincula issue em qualquer conversa da conta (`linear_controller.rb:109-111`).
- **M7. Custo de IA do CRM.** Visível e exportável para todo agente comum (`ai_usage_controller.rb:25-36`, `crm_permissions.rb:19`). Decisão travada, mas conflita com o Financeiro, que é só admin.
- **M8. Sem teste de contrato rota → chave e sem `verify_authorized`.** Endpoint novo nasce aberto. É a causa raiz de C1, A2, A4 e M6.
- **M9. Modelos WhatsApp com 3 regras.** `whatsapp_template_policy.rb:30-36`, `whatsapp_api_message_template_policy.rb:2-16`, telas antigas só admin. #726.
- **M10. Importação de dados só admin.** As outras duas importações têm chave (`data_import_policy.rb`).
- **M11. "Agente" tem dois sentidos (pessoa e IA).** O Agente padrão tem mais acesso que o perfil Atendente e o seletor não descreve as opções (`agentMgmt.json:8-11`, `EditAgent.vue:120-145`).
- **M12. Passo 2 com jargão e decisões demais para leigo.** Termos como CRM, SLA, CSAT, playground, tokens (`pt_BR/customRole.json:111-260`).
- **M13. SDR e Gestor comercial nascem com aviso "Liberar Campanhas".** Contradiz o "NÃO PODE disparar campanhas" deles (`permissionMatrix.js:106,322-328,458,468`).
- **M14. Hover da lista de agentes.** Mostra chave de tradução crua para Agendamento e Modelos, e só abre com mouse (`agents/Index.vue:244-263`).
- **M15. Atribuição só na criação.** Depois, uma pessoa por vez em Agentes (`CustomRoleEditor.vue:250-260`).
- **M16. Nomes de função podem repetir** (`custom_role.rb:100`).
- **M17. Funções dos tokens.** Aparecem na lista e no seletor de Agentes e podem ser editadas: muda o escopo do token fora da tela dele (`custom_roles_controller.rb:7`, `Index.vue:23-30`).
- **M18. Gates diferentes para ligar funil à caixa.** `crm_manage_pipelines` por uma rota e `crm_admin` por outra, com comentário enganoso (`crm.routes.js:66-71`).
- **M19. Pendências de permissão do #1140.** R16, #1447, sobras do #1148.
- **M20. A tela de funções não fala de alcance (caixa/funil) e não mostra o efeito real.**

### Baixa
- **B1. Função de outra conta aceita no PATCH.** Integridade, só admin (`agents_controller.rb:23`, `concerns/account_user.rb:5`).
- **B2. Nomes enganosos.** `report_manage` é só leitura; `conversation_*_manage` é escopo; comentário de `crm_view_reports` desatualizado (`custom_role.rb:31`).
- **B3. `knowledge_base_manage` promete "Escreve e publica" e ninguém escreve.**
- **B4. O editor mostra módulos que a conta não tem** (`CustomRoleEditor.vue:161-166`).
- **B5. CSAT.** Membro da caixa cria modelo na Meta. É decisão do #452 (`inbox_policy.rb:35-38`).
- **B6. Atribuição a qualquer usuário da conta.** Upstream (`assignment_service.rb:62-64`). Participantes ficam limitados à caixa.
- **B7. Visão salva "Equipe" vale para a conta inteira** (`saved_view.rb:52-55`).
- **B8. Relacionamentos/Empresas ignoram funil.** Segue o upstream.
- **B9. "Aprenda mais" aponta para Respostas prontas** (`Index.vue:134`).
- **B10. Função sem tela inicial cai em Perfil** (`routeHelpers.js:32-60`).
- **B11. Helper copiado em 8 policies. Menu esconde itens de dois jeitos. Instagram/híbrido/WAHA sob `inbox_manage` sem texto na matriz.**

### Refutados na verificação
- Ferramentas dos agentes sob `autonomia_manage`: hoje são só SuperAdmin.
- Guia como brecha própria: ele age com o token da pessoa, e a decisão está registrada (`guide_controller.rb:1-3`).
- Token que amplia acesso quando a função some: falha fechado.

---

## 4. Impactos

- **Clientes e contas existentes.** Os Lotes 0 e 2 **reduzem** acesso de funções restritas (busca, websocket, contatos, CRM em massa, resumo da IA no Kanban). Quem hoje depende disso sem saber vai notar. Antes de cada PR, rodar inventário em produção só por leitura (psql via SSM, com OK seu). Na conta 43, só leitura. Contar:
  - funções sem chave de contato com pessoas;
  - funções só `participating`/`unassigned`;
  - funções só `crm_view`;
  - admins com `custom_role_id`;
  - funções de outra conta;
  - nomes duplicados.
- **Segurança.** C1, A1, A2 e A5 são dado de cliente final vazando dentro da conta, para pessoas da mesma empresa sem permissão. Nada indica vazamento entre contas (o B1 é integridade, só admin). Todas as brechas também são alcançáveis pelo Guia em linguagem natural.
- **Suporte.**
  - "Por que fulano não vê X?" não tem resposta na tela (3 camadas, sem prévia).
  - Botões que dão 403 viram chamado.
  - Textos de perfil contradizem o comportamento (Atendente, "Todas", SDR).
- **Vendas.**
  - O dono precisa promover gestor de tráfego ou operador a **administrador** para cobrir trabalho real (Anúncios Meta, Importação, telas só-admin dentro de Campanhas e Agendamento). Com isso ele entrega usuários, cobrança e integrações.
  - Faltam "supervisor do time" e "auditor que só lê", pedidos comuns em venda B2B.
  - A promessa de "funções personalizadas" hoje não aguenta uma demonstração com cliente técnico.

---

## 5. Proposta recomendada

**Espinha: a proposta de segurança** (uma regra só, que se possa testar). Ela é pré-requisito das outras duas: sem ela, a tela nova promete o que o servidor não cumpre, e "Ver como" e "do time" herdariam os vazamentos.

**Enxerto da proposta de UX:** a jornada "Cargos" em 4 passos, com uma pergunta por tela, "O que a pessoa vê" e "Ver como".

**Enxerto da proposta de hierarquia:** o modelo de 4 eixos e o nível "do time" com tabela própria de gestor. Esse nível fica atrás de decisão sua.

### 5.1 Servidor (base de tudo)
1. **`CustomRole::Catalog`** **[NOVO]**, sem tabela nova. Para cada chave: módulo, nível, implicações (manage ⇒ view em todos os módulos, inclusive CRM; `crm_admin` ⇒ crm_*), se é sensível, a flag de conta e o que o "Atendente padrão" recebe. `PERMISSIONS`, `permission_granted?`, `CrmPermissions` e as 8 cópias do helper passam a usá-lo. Nenhuma chave é renomeada (#452).
2. **`effective_permissions`** já expandido no payload do usuário (`_user.json.jbuilder:34`). O front para de recalcular (`useCrmPermissions`, `useCanManage`, Sidebar). Um JSON gerado pelo catálogo alimenta a matriz, o i18n e as frases PODE/NÃO PODE, com `:check` na CI (mesmo padrão do `guia:build`).
3. **`Conversations::AccessScope`** **[NOVO]**: um cálculo só de "esta pessoa vê esta conversa?" (caixa + função + funil). Quem consome: lista, link, contadores, busca, websocket, `Crm::Conversations::Visibility` e `VisibleScopeQuery`. A camada de funil do Multifunnel continua igual (só restringe). **O `AccessScope` compõe camadas (caixa + função) e chama `Crm::Access::ConversationScope`/`CardScope`, sem reimplementar o funil** (R2–R5, decisões de 11/10 e 15/10). Duas cópias da regra de funil divergiriam.
4. **Contrato de permissão** **[NOVO]**: `config/permission_contract.yml` + spec que percorre as rotas, mais `after_action :verify_authorized` com lista de exceções que encolhe. Rota nova sem decisão quebra a CI.
5. **Ciclo de vida:**
   - funções de token marcadas e escondidas (coluna `managed` com backfill pelos joins dos tokens; a alternativa sem coluna é ver se `account_users.integration` basta — [HIPÓTESE], conferir);
   - excluir função exige destino;
   - PATCH só mexe na função se o campo vier;
   - função da mesma conta;
   - admin não recebe função;
   - nome único;
   - audit.
6. **Endpoint "visão efetiva da pessoa"** **[NOVO]**, só admin. **Calcula** a visão, não faz login como a pessoa. Mostra menu, contagens, primeiras N conversas e cards sem o texto das mensagens, e o "por que não vê X?" (qual camada barrou), de forma determinística.

### 5.2 Jornada para leigo ("Cargos e acessos")
Vocabulário (só texto, nenhuma chave muda):
- "Função personalizada" vira **Cargo**.
- "Agente" padrão vira **Atendente completo (vê tudo das caixas dele)**.
- "Administrador" vira **Dono / Administrador (vê e mexe em tudo)**.
- Níveis: **Não vê / Só olha / Pode mexer**.

Sem `<select>`: ChoiceSelect e cartões-rádio de 44 px. Só aparecem os módulos ligados na conta.

**Tela 0 — Lista**
```
Cargos e acessos                                   [ + Novo cargo ]
┌ 🎧 Atendente ─────────────┐ ┌ 📈 Vendedor ──────────────┐
│ Atende as dele e pega fila│ │ Cuida dos clientes dele   │
│ 👤👤👤 3 pessoas           │ │ 👤 1 pessoa               │
│ [Ver quem usa]   [Abrir]  │ │ [Ver quem usa]   [Abrir]  │
└───────────────────────────┘ └───────────────────────────┘
── Cargos que já vêm prontos ──
👑 Dono / Administrador · vê e mexe em tudo · 2 pessoas
🎧 Atendente completo · tudo das caixas dele · 5 pessoas
```
Os cargos de token não aparecem. Os botões têm texto.

**Passo 1/4 — Que tipo de pessoa?**
6 cartões: Atende · Vende · Só acompanha · Chefia uma equipe · Faz marketing · Montar eu. Cada um usa os presets atuais, já corrigidos. O atalho "Usar como está" leva direto ao passo 3.

**Passo 2/4 — Uma pergunta por tela**
```
●●○○  Quais conversas ela pode ver e responder?
( ) Nenhuma
(•) As dela e as que ainda não têm dono   ← recomendado
( ) Só as dela
( ) Todas das caixas dela
[ ( ) As do time dela ]   ← só se você aprovar a hierarquia (D3)
ℹ "Caixas dela" você escolhe no passo 4.
[← Voltar]                                   [Próxima →]
```
As perguntas seguintes: clientes · funil de vendas · números · campanhas · "mais alguma coisa?" (recolhido). Depois vem uma tela âmbar "Coisas que pesam": baixar planilha, IA do funil (custo), configurar funil inteiro. O link "ver todos os acessos em lista" abre a matriz atual (modo avançado).

**Passo 3/4 — Confira**
Nome, que não pode repetir. As colunas ✅ PODE / ❌ NÃO PODE são **geradas a partir das chaves**. Embaixo: 🔒 "Sempre só do dono: usuários, cargos, integrações, cobrança".

**Passo 4/4 — Quem usa e onde** (desenhar com o Multifunnel, substitui ou absorve a #1149)
```
Quem vai ter o cargo "Atendente"?   🔍 buscar pessoa
👤 Ana    hoje: Atendente completo   [Dar cargo ✓]
👑 Carla  administradores não recebem cargo
Em quais canais a Ana atende?  [✓] WhatsApp Vendas [✓] Suporte [ ] Instagram
De quais funis ela cuida?      (•) Todos ( ) Escolher ( ) Só o que for dela
[Pular por agora]                                   [Concluir]
```

> Telas 5 e 6 são **opcionais**, não fazem parte da base. Em 17/10 o Rodrigo cortou três telas do Multifunnel com "não quero mais uma página / use o que já existe". Levar como opção.

**Tela 5 — Ficha "O que a Ana vê"** (opcional)
Mostra conversas, clientes, funil e números, com o resultado já combinado. O aviso explica a interseção: "o cargo diz todas, mas no canal Suporte ela só vê o funil Pós-venda [Ajustar canal]". Botão [👁 Ver como a Ana vê].

**Tela 6 — Prévia** (opcional)
Faixa "Você está vendo como a ANA vê, nada pode ser alterado". Mostra menu, listas e contagens. "Por que ela não vê a conversa X? [colar link]" responde com a camada que barrou.

**Excluir cargo**
"3 pessoas usam. Para onde vão? [ChoiceSelect obrigatório]". Se o destino for Atendente completo, aparece "⚠ elas passam a ver TODAS as conversas dos canais delas e o funil inteiro".

**Contas existentes:** combinações que o assistente não sabe mostrar (unassigned + participating, legado só `crm_admin`) abrem no modo avançado com o selo "cargo antigo, revise". Nada é reescrito sozinho.

### 5.3 Hierarquia (só se aprovada, D3)
- Chave nova `conversation_team_manage`: só uma string a mais, sem migration.
- Tabela do fork `team_leaders` (account_id, team_id, user_id), sem coluna em `teams`, para o gestor **não** entrar no rodízio.
- Continua cortado pela caixa e pelo funil ("time não fura funil").
- No CRM, o gestor vê o card cujo dono ou atendente da conversa principal é do time. **Sem coluna `team_id` no card** (sem backfill; mantém "dono e atendente sempre veem").
- Flag nova ligada em 1/16/18.

---

## 6. Plano em fases (PRs pequenos)

**Lote 0 — brechas** (sem flag; cada PR com request spec que reproduz antes de corrigir)
| PR | O que | Severidade |
|---|---|---|
| 0.1 | Busca passa pelo filtro de função (conversas e mensagens) | crítica |
| 0.2 | CRM `Visibility`/`VisibleScopeQuery` respeitam `conversation_*` | alta |
| 0.3 | Em massa no CRM confere `update?`/`move?`/`destroy?` por card | alta |
| 0.4 | Facebook callbacks → `authorize inbox`; Linear → `authorize conversation, :show?` | alta / média |
| 0.5 | PATCH de agente: só mexe se o campo vier; função da mesma conta; admin não recebe | alta |
| 0.6 | Contatos e empresas: leitura exige `contact_view`, com a exceção do contato dentro da conversa e do card (sua decisão de 08/10). Antes, inventariar as chamadas do front a `/contacts` | alta |
| 0.7 | ActionCable filtra por função. PR próprio, com medição de carga e tester dedicado | alta |
| 0.8 | Custo de IA do CRM, conforme D5 | média |

Ordem: 0.1, 0.2, 0.3, 0.4 e 0.5 em paralelo. Depois 0.6 e 0.7.

**Lote 1 — fonte única** (sem mudar comportamento; specs de caracterização antes)
- 1.1: catálogo + `effective_permissions` + `ApplicationPolicy#granted?`.
- 1.2: policies migradas.
- 1.3: JSON gerado + `:check` + i18n completo.
- 1.4: front consome `effective_permissions`.
- 1.5: `permission_contract.yml` + spec.
- 1.6: `verify_authorized`.

**Lote 2 — ciclo de vida**
- 2.1: funções de token escondidas.
- 2.2: excluir com destino.
- 2.3: audit.
- 2.4: nome único (inventário antes).
- 2.5: conversas somam as chaves (OU) na lista e nos contadores (D4).
- 2.6: `AccessScope` + endpoint de visão efetiva.

**Lote 3 — mockup navegável** das Telas 0 a 6, no painel local do M2. Aprovação sua junto com o Multifunnel **antes de codar**.

**Lote 4 — UI** (flag nova ligada em 1/16/18)
- 4.1: lista + vocabulário.
- 4.2: passos 1 e 2.
- 4.3: passo 3 + presets corrigidos (Atendente com fila; SDR sem "Liberar").
- 4.4: passo 4 (pessoas + canais + funis).
- 4.5: ficha + ChoiceSelect com descrição.
- 4.6: Ver como.
- 4.7: excluir com destino + hover acessível.
- 4.8: `guia:build`, `porques.md` e `autonomia:guia:formatos`.

**Lote 5 — cobertura**
- `meta_ads_view` (#1158).
- Modelos WhatsApp unificados (#726).
- Importação de dados.
- Telas só-admin de e-mail e agendamento.
- `autonomia_tools_manage` (#1430), num PR que mude CLAUDE.md e AGENTS.md juntos.
- `conversation_view` (D6).

**Lote 6 — hierarquia** (se D3 = sim): `team_leaders` + `conversation_team_manage` + CRM por time.

---

## 7. Decisões que precisam de você

**D1. `crm_admin` delega tokens e "quem vê o quê" (e a própria restrição)**
Contexto: contraria a regra "não delegar segurança/tokens".
- (a) Tirar do cargo: só admin. Mais seguro; o gestor comercial perde a tela de Caixas.
- (b) Manter, mas travar a autoedição e tirar os tokens. Meio-termo, com mais código.
- (c) Manter como está. Zero trabalho, mas a brecha continua.

**Recomendo (b).**

**D2. Passo 4 único (pessoa + canais + funis) versus a #1149 por caixa**
- (a) O passo 4 absorve a #1149. Uma jornada só para o leigo.
- (b) As duas telas convivem, olhando o mesmo dado: por pessoa e por caixa. Mais flexível, mas são 2 lugares.

**Recomendo (a)** (revisado após o Multifunnel, 17/10): em 17/10 você cortou telas com "não quero mais uma página / use o que já existe". O passo 4 absorve a #1149 (pausada) e a tela por caixa fica fora.

**D3. Reabrir a hierarquia "gestor vê o time"**
Contexto: está fora do #1140 (`PLANO.md:40`).
- (a) Fica fora agora. O épico sai mais rápido; "supervisor do time" continua sem resposta.
- (b) Um nível (gestor → time) com tabela própria, no Lote 6. Responde a venda B2B e é aditivo.
- (c) Organograma com vários níveis. Grande demais.

**Recomendo (b), depois dos Lotes 0 a 2.**

**D4. Lista de conversas com "sem responsável" + "participando"**
- (a) Somar (OU) em todos os lugares. Alinha a lista ao link; o SDR passa a ver mais na lista (acesso que já tinha pelo link).
- (b) Escolha única na tela. Zero mudança no servidor.

**Recomendo (a)** e, na tela, os 4 cartões de escolha única. Uma coisa não impede a outra.

**D5. Custo de IA e relatórios do CRM para o "Atendente completo" (agente sem cargo)**
- (a) Manter (decisão travada).
- (b) Negar só o custo de IA. Exigir `crm_manage_ai`, como pede o #1157.
- (c) Negar relatórios e custo.

**Recomendo (b)**: custo é dado financeiro, e o Financeiro é só admin.

**D6. `conversation_view` ("só ler, sem operar")**
- (a) Agora, no Lote 5. Exige conferir todas as rotas de escrita de conversa.
- (b) Épico próprio depois.

**Recomendo (b)**: só é seguro depois do contrato de rotas (Lote 1).

**D7. Contatos: quais campos continuam visíveis dentro da conversa e do card sem `contact_view`** (refinamento da sua decisão de 08/10)
- (a) Nome + telefone/e-mail do próprio contato da conversa.
- (b) Ficha completa do contato da conversa.

**Recomendo (a).**

**D8. Admins que hoje têm `custom_role_id`**
- (a) Limpar o campo por script com o seu OK (escrita em produção).
- (b) Só listar e deixar o dono ajustar.

**Recomendo (b)** primeiro, para medir o tamanho.

**D9. "Só atribuídas" (por caixa) e "Só as suas" (por pessoa) num lugar só?**
Contexto: semânticas diferentes. `InboxSetting.assigned_only` vale por CAIXA, para todos, e olha atribuída/participante/dona (`visible_scope_query.rb:20-46`). `only_own` vale por PESSOA × caixa e inclui dono de card que prende a conversa (#1652).
- (a) Manter as duas, mas mostrar as duas na mesma tela, com texto claro. Zero migração.
- (b) Unificar em `only_own`: migrar `assigned_only` → `only_own` para cada membro e decidir o padrão do membro novo da caixa. Escrita em produção.
- (c) Deixar como está.

**Recomendo (a)** agora; (b) só se a confusão persistir.

**Revisão do chat Multifunnel (17/10)** — de acordo com D1 (b) e D3 (b). Ressalvas incorporadas: D2 → (a); Telas 5 e 6 opcionais; `AccessScope` compõe sem reimplementar funil; D9 nova; card do gestor pelo time do dono/atendente. Mockup navegável aprovado antes de codar; sem `<select>`; flag ligada em 1/16/18 hub2you. Pendências R16 e #1447 do #1148: conferir na Issue antes do Lote 4.

---

## 8. Fora do escopo
- Mais de um cargo por pessoa. Organograma com vários níveis.
- Escopo por caixa dentro do cargo (continua sendo ser membro da caixa + funil).
- Cotação (`insurance_*`, a Lia): só a migração mecânica no Lote 1, sem mudar semântica.
- Captain (FAQ), Empresas por funil, escrita na Central de Ajuda (`knowledge_base_manage` só ganha o rótulo "Só olha").
- Mascarar CPF/RG: não propor, os dados são do negócio.
- Usuários, cargos, integrações, cobrança, financeiro e segurança continuam só do admin.
- CSAT para membro da caixa (#452) e atribuição a qualquer usuário (upstream): só mudam com decisão nova.
- Login como outra pessoa ("Ver como" é só cálculo).

---

## 9. Colisões com PRs e Issues abertos
| Item | Toca | Ação |
|---|---|---|
| #1157 (Lote 0) | Mesmo escopo do Lote 0 | Os PRs do Lote 0 usam `Refs #1157` |
| #1158 (Lote 1 de telas) | `meta_ads_view`, telas só admin | Lote 5 |
| #1135 / PR #1136 (rascunho, docs) | Proposta de escopos "Áreas/Dados/Ações" | Alinhar; este documento substitui ou atualiza |
| #1149 (pausada) / #1322 §2 | Tela "Quem vê o quê" | Desenhar junto (D2) |
| #1140 / #1148 | Acesso por funil, pendências R16, #1447 | Fechar pendências antes do Lote 4 |
| #1430 | `autonomia_tools_manage` + regra do CLAUDE.md | Lote 5, PR de regra próprio |
| #726, #744 | Modelos em Campanhas, campo Campanha na Prospecção | Lote 5 |
| #1577 (rascunho) | `grant_policy.rb`, `Sidebar.vue`, `autonomia/agents_controller.rb` | Sequenciar pela Orquestração |
| #1749 | `conversation_assets_policy.rb` | Conferir merge-tree |
| #1641 / #1617 (menu novo) | `Sidebar.vue`, cartões de Configurações | O Lote 4 entra depois, ou em cima do menu novo |
| Migrations (`managed`, `team_leaders`, índice de nome) | Versão única | Conferir colisão de versão com PRs abertos |

Todo PR que toque rota ou menu precisa de `pnpm guia:build`. Todo PR que toque controller precisa de `autonomia:guia:formatos`.
