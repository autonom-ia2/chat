# Auditoria de cobertura — Central de Ajuda Chat2You (Fase 0)

Data: 22/09/2026. Base: 165 telas navegáveis do painel HOJE (`telas-roteador.json`) x
284 assuntos do estudo de 08/09/2026 (`assuntos-estudo.json`). Repositório auditado
(só leitura): `worktrees/chat2you/502-central-fase-0`.

## Números

| | Quantidade |
|---|---|
| Telas totais no roteador de hoje | **165** |
| Telas **cobertas** por ≥1 assunto do estudo | **82** (50%) |
| Telas em **lacuna** (zero assunto) | **44** (27%) |
| Telas **fora** da Central (justificadas) | **39** (24%) |
| Funcionalidades sem tela própria mapeadas | **11** (5 cobertas, 6 não) |
| Assuntos do estudo que mudaram/ficaram desatualizados | **4** |
| Lacunas de capítulo (agrupadas) | **18**, sendo **8 P1**, **8 P2**, **2 P3** |

Dos 284 assuntos do estudo, **279 estão amarrados a pelo menos uma das 165 telas**;
os outros 5 (disponibilidade, tema claro/escuro, atalhos de teclado, encerrar sessão,
marcar offline automático) vivem no menu da foto de perfil na barra lateral — não é
rota própria, por isso aparecem em `funcionalidades_sem_tela`, não em `telas`.

## As 44 lacunas, por capítulo sugerido

**Capítulo novo — Financeiro (P1).** `autonomia_financial_subscription`,
`autonomia_financial_invoices`, `billing_settings_index`. Item de menu de primeiro
nível, só para administrador, e o capítulo 04/08 fala o tempo todo em custo de IA sem
nunca apontar para onde o cliente vê a fatura.

**Capítulo novo — Cotação de seguros (P1).** `autonomia_insurance_agent`,
`autonomia_insurance_connections`. Zero menção nos 284 assuntos. O Guia da Plataforma
(`lib/operator_guide/porques.md`, bloco `como_o_cliente_recebe_a_cotacao`) já tem
texto pronto e detalhado sobre a jornada no WhatsApp — é conteúdo para portar, não
para escrever do zero.

**Capítulo novo — Configurações da conta (P1).** `general_settings_index` (é a
primeira tela que o administrador vê ao abrir Configurações), `security_settings_index`,
`auditlogs_list` (hoje só citada de raspão em 02.20). Some também `agent_bots`
("Robôs" nativos do Chatwoot, ligados por padrão — terceiro produto chamado
"agente/robô" na plataforma, sem nenhuma desambiguação).

**Capítulo novo — Caixas de entrada: os outros canais (P1).** `settings_inbox_list`
(lista de caixas já criadas) e a criação/configuração de WhatsApp API (WAHA — o canal
mais usado desta stack), E-mail, Site, Instagram, Facebook, SMS, API, Telegram, Line,
TikTok e Voz. O capítulo 05 só ensina WhatsApp Oficial.

**Capítulo novo — Central de Ajuda / Portais (P1).** As 10 telas de `portals_*` e
`portals_categories_articles_*` (Artigos, Categorias, Localidades, Configurações do
portal do cliente final). Menu de topo inteiro, ligado por padrão, zero cobertura.

**Capítulo novo — Automação e Macros (P1).** `automation_list`, `macros_wrapper`,
`macros_new`, `macros_edit`. Hoje só existem menções de uso (time em automação, time
em macro, executar macro na conversa) — ninguém ensina a criar a regra ou a macro do
zero.

**Capítulo 06 — Tela de conversas, subcapítulos novos (P1/P2).**
`inbox_view`/`inbox_view_conversation` (primeiro item do menu — é a central de
NOTIFICAÇÕES, nome homônimo e fácil de confundir com "Caixas de Entrada" e com a
própria tela de Conversas); iniciar conversa do zero (botão Compor, sem tela própria
mas listado como fluxo de `home` no roteador); busca de comandos (Cmd/Ctrl+K).

**Capítulo 03 — Times, complemento (P2).** `assignment_policy_index` e as 6 telas de
política de atribuição/capacidade (`agent_assignment_policy_*`,
`agent_capacity_policy_*`). Só o terceiro cartão da mesma tela-hub (Handoff da IA) é
ensinado, via capítulo 08 — o capítulo 08 nunca diz que a porta de entrada é
Configurações → Atribuição de Agentes.

**Espalhados, prioridade P2.** `labels_list` (criar/editar etiqueta — usada em 4
capítulos, nunca ensinada na origem); `canned_list` (criar resposta pronta — 06.14 só
ensina a usar); `attributes_list` cobre só a aba Contato, falta a aba Conversas;
`settings_integrations_linear/notion/shopify/slack` (04.19 só cita
Dialogflow/Tradutor/Dyte); `conversation_workflow_index` (Fluxo de Conversa —
efeito visível em 06.19 sem explicar a causa); ligar o CSAT na caixa (o capítulo 11
ensina a ler o relatório, nunca a habilitar a pesquisa); `settings_data_imports` e
`settings_data_import_show` (o Guia já tem texto pronto, não puxado para o estudo);
`campaigns_whatsapp_analytics` e `calls_dashboard_index` (idem — o primeiro também já
tem texto pronto no Guia).

**Capítulo novo — Primeiros passos (P1).** `first_steps`, `onboarding_account_details`,
`onboarding_inbox_setup`. Praticamente sem cobertura, e `first_steps` mudou de papel
depois do estudo: três commits pós-08/09 (`06a03cbb51`, `acd53a12e7`, `0dc9894053`)
transformaram a tela na **porta de entrada da conta**. Achado forte:
`config/onboarding/trilha.yml` (Épico #485, fonte única dos passos da tela Primeiros
Passos) já define **9 passos com artigo de Central de Ajuda planejado para cada um**
(campo `artigo:` — `primeiros-passos-perfil`, `-chave-openai`, `-canal`,
`-primeira-resposta`, `-funil`, `-equipe`, `-agente-ia`, `-campanha`,
`-configuracoes`). Nenhum dos 9 existe no estudo de 284 assuntos — é um roteiro
pronto, sancionado pelo próprio produto, só esperando ser escrito. Um detalhe a
corrigir na trilha: o passo "campanha" aponta `rota: campaigns_index`, que não existe
no roteador atual (não há rota unificada de Campanhas, só uma por tipo de canal).

**P3.** `settings_teams_edit_finish` (etapa de confirmação ao editar agentes de um
time já existente, distinta de `settings_teams_finish` do fluxo de criar).

## Funcionalidades sem tela própria (item 2 da tarefa)

| Funcionalidade | Coberta? | Capítulo sugerido |
|---|---|---|
| Menu do perfil (status, tema, atalhos, sair, offline automático) | Sim | 01 |
| Handoff automático da IA para humano | Sim | 08/09 (já coberto) |
| Convite e ciclo de vida do agente | Sim | 02 (já coberto) |
| Guia da Plataforma (painel flutuante) | **Não** | 00 novo / abertura do 01 |
| Jornada de cotação no WhatsApp | **Não** | Capítulo novo Cotação de seguros |
| Notificações — onde ler o que já chegou | **Não** | 01, ao lado de 01.13/01.14 |
| Automações — criar regra do zero | **Não** | Capítulo novo Automação e Macros |
| Primeiros passos / onboarding | **Não** | Capítulo novo Primeiros passos |
| Busca de comandos (Cmd/Ctrl+K) | **Não** | 06, junto de 06.33 |
| Trocar/criar conta (seletor de contas) | **Não** | 01 ou capítulo novo de conta |
| Iniciar conversa do zero (Compor) | **Não** | 06 |

## Capítulos novos recomendados (item 4)

Confirma-se a necessidade de, além dos 11 capítulos atuais + "00 Mapa e vocabulário" +
"12 Configurações da conta" já previstos no esqueleto: **Financeiro**, **Cotação de
seguros**, **Caixas de entrada: os outros canais**, **Central de Ajuda (Portais)** e
**Automação e Macros**. "Prospecção" já tem conteúdo (09.26–09.29), mas hoje está
diluído dentro do capítulo 09 "Agentes de IA" — vale um capítulo próprio só de
organização, sem lacuna de conteúdo. "Guia da Plataforma" e "Primeiros passos" também
merecem capítulo/bloco de abertura dedicado.

## Assuntos que ficaram obsoletos ou mudaram desde 08/09 (item 3)

1. **`02.16-permissoes-uma-a-uma`** — a referência de permissões de função
   personalizada ficou incompleta: a matriz ganhou categorias novas (Prospecção,
   Cotação, Autonomia, Campanhas, Conexões) depois do estudo.
   Prova: commits `fc1c912db7` e `920263697f`, ambos pós-08/09.
2. **`07.3-ordenar-a-lista`** — o padrão de ordenação de Contatos mudou de "atividade
   mais antiga primeiro" para "mais recente primeiro" (correção de timeout em contas
   grandes). O título e o local continuam corretos; o texto, se descrever o padrão
   antigo, precisa de ajuste. Prova: commit `3d7ca0ec0b` (#15827), 15/09/2026.
3. **`08.4-vincular-inbox-ao-funil`** — a mecânica de vínculo caixa↔funil mudou:
   configurar o inbox passou a bastar para o card nascer, e dois salvamentos
   simultâneos deixaram de derrubar o vínculo. Provas: commits `ee5d02af3d` e
   `21235ec0e9`, ambos pós-08/09.
4. **`04.7-salvar-e-validacao`** — pode estar desatualizado: um bug corrigido depois
   do estudo fazia a chave do CRM Kanban IA salvar sem de fato ligar a IA. Prova:
   commit `8618f93d7d`, pós-08/09.

**Achado à parte, fora dos 284 ids:** o apuramento de 08/09
(`docs/central-de-ajuda/estudo/2026-09-08-apuracao.json`) já listava como lacuna a
tela "Notificações (lista completa em tela cheia)", rota `notifications_index`. Essa
rota **não existe mais no código** — foi removida pelo commit `590e17dfb7` ("chore:
remove the legacy notifications page"), datado de **13/08/2026, antes mesmo do
estudo**. Ou seja, o próprio apuramento de 08/09 já citou uma tela fantasma; a central
de notificações real de hoje é só `inbox_view`, que já está listada como lacuna acima.

## Telas que não devem entrar na Central (39, item 5)

- **Captain (17 telas)** `captain_*` — recurso nativo do Chatwoot desligado por
  padrão (`captain_integration=false` em `config/features.yml`); o próprio Guia da
  Plataforma já marca essas rotas como "recurso que esta instalação não usa"
  (`porques.md:1646`). O Chat2You tem sistema próprio de Agentes de IA (capítulo 09).
- **Telas de sistema (2)** `account_suspended`, `no_accounts` — estados de erro, não
  são caminho de produto.
- **Redirecionamentos puros, sem componente (6)** `labels_wrapper`, `settings_home`,
  `campaigns_one_off_index`, `campaigns_ongoing_index`, `autonomia_prospecting_settings`,
  `autonomia_insurance` — sempre encaminham para outra rota já coberta ou já marcada
  como lacuna.
- **Rotas-casca de agrupamento, sem path/componente próprio (5)** `profile_settings`,
  `agent_reports`, `inbox_reports`, `label_reports`, `team_reports` — o conteúdo real
  está nas telas filhas (`_index`/`_show`/`_mfa`).
- **Variantes técnicas de rota, mesma tela e mesmo componente (9)**
  `contacts_edit_label`, `contacts_edit_segment` (mesma tela de `contacts_edit`),
  `conversation_through_inbox`, `conversation_through_mentions`,
  `conversation_through_participating`, `conversation_through_unattended`,
  `conversations_through_folders`, `conversations_through_label`,
  `conversations_through_team` (mesma tela de `inbox_conversation`, só muda a lista de
  onde a conversa foi aberta) — documentá-las à parte duplicaria conteúdo sem agregar
  nada ao leitor.

## Correção a fazer no Guia da Plataforma (achado colateral)

`lib/operator_guide/porques.md` lista `macros_wrapper` em `_fora_do_guia` como "casca
de roteamento, não é tela". Isso está **desatualizado**: no código atual
(`app/javascript/dashboard/routes/dashboard/settings/macros/macros.routes.js:17-30`)
essa rota renderiza `Macros/Index.vue` diretamente — é a tela real da lista de Macros,
no mesmo padrão de `labels_list`/`attributes_list`. Recomendo remover essa linha do
Guia e tratar `macros_wrapper` como tela normal (hoje listada aqui como lacuna, por
falta de conteúdo sobre criar/editar macro).

## O que precisa de decisão humana

1. **Confirmar os 5 capítulos novos propostos** (Financeiro, Cotação de seguros,
   Caixas de entrada — outros canais, Central de Ajuda/Portais, Automação e Macros) e
   a numeração final deles frente ao "00 Mapa e vocabulário" e "12 Configurações da
   conta" já prontos no esqueleto.
2. **Confirmar se Captain está de fato desligado em produção** — o apuramento de
   08/09 já registrava isso como "a verificar"; esta auditoria confirma
   `captain_integration=false` no `config/features.yml` do repositório, mas não
   confirma o valor real da feature flag em produção (fora do escopo de leitura de
   código).
3. **Priorizar os 4 itens que já têm conteúdo pronto no Guia da Plataforma** e só
   precisam ser portados para o estudo/Central: Cotação de seguros
   (`autonomia_insurance_agent`), importação de dados (`settings_data_imports`,
   `settings_data_import_show`) e resultado de campanha de WhatsApp
   (`campaigns_whatsapp_analytics`) — ganho rápido, sem apuração nova.
4. **Decidir se `onboarding_inbox_setup` entra na Central** apesar de estar marcada
   como "fora do painel" no Guia — são produtos diferentes (ajuda contextual x
   material de leitura) e o entendimento desta auditoria é que a Central deveria
   cobrir a jornada de primeiro acesso mesmo assim.

## Arquivos

- Dados completos: `docs/central-de-ajuda/cobertura.json`
- Entradas usadas: `telas-roteador.json` (165), `assuntos-estudo.json` (284),
  `docs/central-de-ajuda/estudo/2026-09-08-apuracao.json` (apuramento original),
  `lib/operator_guide/porques.md`, `config/onboarding/trilha.yml`
