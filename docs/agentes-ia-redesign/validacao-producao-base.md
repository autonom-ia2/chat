# Validação em produção — ponto de partida

Este arquivo **não é requisito**. É o rascunho de onde cada PR parte para escrever o seu plano de validação em
`design/<PR>.md`, com o código do PR aberto, o volume do dia lido por psql e o workflow de deploy vigente (PRD §11.7/§11.8,
causa raiz C13 em `docs/audit/2026-10-05-agentes-prd-r2-causa-raiz.md`).

Regras para usar:
- cada Q e T copiada para um plano de PR leva por escrito as respostas 6(a–d) do §10.3 do PRD;
- as **pendências obrigatórias** no fim deste arquivo (achados das revisões que tocam a validação) são resolvidas pelo
  plano do PR cujo escopo elas tocam, antes do merge; o plano cita o ID da pendência.

---

## Q (consultas) — antiga §11.7 Validação em produção (após cada deploy que muda comportamento)

Só leitura: SSM `AWS-RunShellScript` → `docker exec chatwoot-web psql "$DATABASE_URL"` com `BEGIN TRANSACTION READ ONLY`.
**Nunca** `rails runner`/`rails console`. Nenhuma consulta devolve nome, telefone ou mensagem de cliente — só ids e
contagens. Ler `docs/processo-de-release.md` antes. Q1–Q17 rodam nas **duas** stacks (hub2you e autonomia).

**Foto de antes:** saída de Q1, Q7, Q10, Q12a, Q13, Q15 e o horário dela, tirada **logo antes do merge do lote** e salva
**fora** da instância (anexo do PR ou `docs/audit/<data>-agentes-<pr>-foto.md`). A **janela** de cada comparação começa no
horário da foto, não no deploy. **A evidência vem só do banco** (`created_at`/`updated_at` depois da foto, registro do
`Enterprise::AuditLog`), nunca do log do container: no blue-green, a instância antiga é terminada e leva o log com ela.

**Volume real (05/10, psql só leitura):** a Clara tem 3 conversas em 7 dias, e a Lia, 29 em 30 dias. Comparação estatística
de taxa por janela curta não tem volume. Comportamento ao vivo (passagem, alvo, primeira mensagem, "Nunca") é provado no
tester (§11.8), com afirmação dura. A §11.7 só confere invariantes e mudanças de estado.

| Q | Pergunta | Esperado | Tipo |
|---|---|---|---|
| Q1 | Retrato por id: conta, status, enabled, atuação, modo (sem agentes de sistema) | Igual à foto, ou cada diferença explicada (regra abaixo) | Estado |
| Q2 | Vínculo agente↔caixa entre contas diferentes | **0** | Invariante |
| Q3 | Agente externo ativo sem canal (ids) | Ids novos explicados | Estado |
| Q4 | Por agente ativo, desde o deploy: mensagens de entrada em caixa dele × eventos `replied` | Agente com ≥ 1 entrada elegível e 0 `replied` em 30 min = desvio | Invariante |
| Q5 | Conversas em caixa de agente pausado com `status = pending` **ou** (`status = open` e `assignee_agent_bot_id` = espelho do vínculo) | **0** | Invariante |
| Q6 | Espelho ativo de agente pausado | **0** | Invariante |
| Q7 | Ids de rascunhos com instrução (foto × agora) | Cada id sumido ou ativado, explicado | Estado |
| Q8 | Conversa do construtor presa (`processing` > `STALE_PROCESSING_AFTER`) | **0** | Invariante |
| Q9 | Materiais com falha desde o deploy × média diária de 30 dias | Lista ao Rodrigo se acima | Estado |
| Q10 | Agente de Cotação: status, enabled, agent_type, name, `md5(config->'agente_de_cotacao')`, `md5(greeting)`, `md5(fallback_message)`, `response_window`, `tone` e nome do AgentBot espelho | Igual à foto, ou explicado | Estado |
| Q11 | Espelho dos agentes ativos (`agent_bot_inboxes`) | Todos `active` (foto de 05/10: hub2you 3 agentes/3 espelhos — contas 16 e 27; autonomia 1/1 — conta 2) | Invariante |
| Q12 | **Q12a** (pode ir para o repo): por agente fora de sistema e cotação, chaves de `config` fora da lista do BE-19, fora das chaves do BE-31 e fora das gravadas pelo Construtor/model (`with_knowledge`, `topic_map`, `knowledge_*`, `guardrails`, `voice`, `builder_active_thread_id`, `agente_de_cotacao`, `system_key`, `guide_*` e toda chave nova deste projeto). **Q12b** (fora do repo, no local do runbook, acesso restrito — pode ter telefone): os valores das chaves que serão limpas | Antes do B1: Q12a + lista ao Rodrigo; limpeza só com 🟢 e Q12b salva. Depois: igual à foto pós-limpeza; chave do BE-31 só com registro no `AuditLog` | Estado |
| Q13 | Agentes ativos por `config->>'handoff_strategy'` (inclusive nulo) | Antes do B4b: lista ao Rodrigo dos ativos com `always_ask`/`never`, que decide por agente; depois: igual, ou explicado | Estado |
| Q14 | Agentes com `tone` em `friendly/professional/neutral/playful` (fora cotação e sistema) | Foto antes do UPDATE D10; depois: zero | Estado |
| Q15 | Agentes ativos (fora de cotação e sistema) com `greeting` ou `fallback_message` preenchidos | Antes do B4b: lista ao Rodrigo (o texto do modelo muda para eles); depois: igual, ou explicado | Estado |
| Q16 | Por agente, proporção de passagem com a fórmula do Analytics (passagens ÷ (`replied` + passagens), conversas distintas) desde o deploy × últimos 30 dias | **Informativa:** lista ao Rodrigo depois de B4b/B5, com os agentes de estratégia aprovada na Q13 marcados; não aborta (volume baixo) | Informativa |
| Q17 | Passagens feitas pela IA desde o deploy (evento `handed_off` com o alvo registrado pelo roteador, BE-06) cujo alvo não está em `inbox.assignable_agents` (membros da caixa + administradores, `inbox.rb:185-187`) ou, com "Um time", não é membro do time | Depois do B5: **0**. Reatribuição feita depois por uma pessoa não conta (olha o alvo do evento, não o responsável atual) | Invariante |

**Diferença explicada** (consultas de Estado): id novo com `created_at` depois da foto; id mudado com `updated_at` depois da
foto; id sumido que estava em E1 e casava com o critério da limpeza vigente na foto (no B1, o critério antigo, que também
apaga rascunho com instrução; depois do BE-14, o novo); chave do BE-31 com registro no `AuditLog`. Id sumido fora disso
(exclusão pela tela não deixa linha) entra na lista como "sumiu — exclusão?".

**Quem decide:**
- **Invariante violado** (Q2, Q4, Q5, Q6, Q8, Q11, Q17) ou **cenário do tester falhou** → **aborta e volta** sozinho, pela
  volta do §14.
- **Estado com diferença não explicada** (Q1, Q3, Q7, Q9, Q10, Q12, Q13, Q15) → lista por id ao Rodrigo, que decide antes
  do "ok, SHA". Sem decisão, não há "ok", e o próximo lote não sobe (regra 4 do processo de release). O cliente muda
  estado de propósito, então diferença de estado nunca dispara volta automática.

## T (cenários) — antiga §11.8 Tester em produção (`chat2you-agentes-refactor-tester`)

Regras:
- Listar os testes antes de rodar, cada um com o motivo. Afirmação dura; tempo-limite é **falha**.
- Valores (status, tempos) lidos do código e citados. Cada cenário registra HTTP, latência, ids, eventos antes/depois e
  captura.
- Campos que não existem (`prompt_chars`, `persona_artifacts`) são registrados como "não disponível", nunca inventados.
- Cada deploy roda **só** os T com "Vale a partir de" ≤ o PR do deploy. Os demais não rodam e não contam.
- **Teste:** `POST test` é assíncrono (202 + `poll_url`, `defer_interactive_ai.rb:10`). Consultar `GET ai_requests/:id` a
  cada 2 s até o **TTL do pedido, 30 min** (`interactive_request.rb:3`): é o teto real, porque o pedido expira ali. Um
  turno pode fazer várias idas ao modelo: rodada + fechamento quando há ferramenta (`responses_client.rb:72-100`), cada
  uma com até 3 × 180 s (`MAX_RETRIES = 2`, `REQUEST_TIMEOUT = 180`), e a Lia faz até 6 rodadas
  (`quote_agent/builder.rb:152-157`). A latência é registrada.
- **Mensagem real** (T18, T25, T26, T27): esperar até `debounce_seconds` do P1 + 30 min.
- **Ausência** (T17 e a parte "não chega" da T25): observar por `debounce_seconds` + 5 min, com início e fim registrados,
  antes de afirmar que nada aconteceu.

**Pré-requisitos (cada escrita com 🟢 do Rodrigo, criada para o teste e apagada no fim; sem eles, os cenários que
dependem ficam BLOQUEADOS — nunca "passou"):**
- **P0** (leitura, sem 🟢): psql só leitura confirma que a Clara e o agente ativo da conta 2 (stack autonomia) não têm
  ferramenta ligada com método ≠ GET. Sem isso, T07, T08 e T29 ficam BLOQUEADOS (D27).
- **P1** agente de teste "Teste Tester" na conta 16, percorrido nesta ordem (cada passo com 🟢):
  - **P1a** rascunho sem instrução (T14) → instrução gerada pelo Construtor → T14b (sem teste);
  - **P1b** teste por quem edita (T09) → T13a (ligar na caixa P2) → T13, T15, T16, T17, T18;
  - **P1c** "Para quem vai" = time **T** (com o usuário de teste membro de P2) → T25 → volta a "Quem estiver livre";
  - **P1d** Primeira mensagem com o marcador "Xilofante" e "Quando não souber" com o marcador "Pirulândia" → T26;
    "Quando passa" = "Nunca" → T27 → volta ao padrão;
  - T21 → T19 (exclusão).
- **P2** caixa de teste na conta 16, sem agente, com o usuário de teste como membro, e um meio definido de mandar
  mensagem de entrada (celular do Rodrigo ou ferramenta nomeada) — T17, T18, T21, T25–T27.
- **P3** usuário só-ver e função personalizada "só ver agentes" (`autonomia_view`, sem `conversation_*`) na conta 16, com a
  feature `custom_roles` ligada — T06, T15, T23.
- **P4** conta de teste B com token — T02, T03, T20, T30.
- **P5** rascunho criado pelo T22 e apagado logo depois dele.
- **Ordem final:** P1 e P5 apagados **antes** da T24.

| # | Vale a partir de | Tipo | Alvo | Cenário | Pega | Afirmação |
|---|---|---|---|---|---|---|
| T01 | B1 (campos novos: B2) | leitura | conta 16 | `GET agents` (admin) | Lista quebrada | 200; Clara e Lia; sem `instruction` em guiado nem `scaffold`; a partir do B2 também `state`, `stats`, `channels` |
| T02 | B1 | leitura | conta B (P4) | `GET agents` com token da conta B | Vazamento | Nenhum id da conta 16 |
| T03 | B1 | leitura | Clara via conta B | `GET agents/{clara}` com token B | Isolamento por id | 404 |
| T04 | B1 | leitura | Clara | `analytics?range=7d` e `30d` | Como está indo | 200; `timeline` com 7/30 itens; taxas entre 0 e 1 |
| T05 | B1 | leitura | Clara | `analytics/conversations?metric=foo` | Validação | 422 |
| T06 | B1 | leitura | Clara, usuário P3 | `analytics/conversations?metric=handled` e `GET faq_suggestions` | Vazamento entre caixas (BE-25) | lista vazia; `faq_suggestions` 401 |
| T07 | B1 | leitura (exige P0) | Clara | `POST test` "O que vocês fazem?" | Teste responde | 202 + `poll_url`; resultado com `reply` não vazio; `confidence` 0–1; zero evento novo |
| T08 | B1 | leitura (exige P0) | Clara | `POST test` pedindo preço | Formato da passagem | `handoff.should` booleano; `reason` ∈ `ALLOWED_REASONS` ou nulo (valor registrado, não exigido) |
| T09 | B2 | escrita 🟢 | P1b | `POST test` no rascunho por quem edita | Teste válido | 202 + `poll_url`; resultado com `reply`; agente continua `draft`; estado E4 |
| T10 | B1 (`skipped_tools`: B4b) | leitura | Lia | `POST test` "quero cotar meu carro" | Lia intacta, nada cotado | termina antes do TTL; `reply` não vazio; sem `code: escolhas_incompletas`; zero `ToolRun` novo; a partir do B4b, `skipped_tools` com `not_in_test` se a cotação seria chamada |
| T11 | — | — | spec | Instrução da Lia protegida | Instrução mantida | **Só spec R** (`instrucao_mantida`); nenhum PATCH na Lia em produção |
| T12 | B2 | leitura | conta 16 | `GET agents/{clara}/channels` | Seletor | `eligible_inboxes` sem caixa ocupada; `occupied_inboxes` com quem ocupa; `has_schedule` em cada caixa |
| T13a | B3 | escrita 🟢 | P1b | `publish` com `inbox_id` = P2 | Ligar atômico (BE-03) | status HTTP lido do controller; `active` + `enabled`; 1 vínculo e espelho ativo em P2 (Q11); estado E5; Q1 sem outro agente alterado |
| T13 | B3 | escrita 🟢 | P1 ligado + caixa da Clara | `POST channels` do P1 na caixa da Clara | 1 agente por canal | 422 `inbox_already_connected` com frase pt-BR (ordem das guardas em `inbox_connector.rb:34-37`); Clara intacta (Q11) |
| T14 | B3 | escrita 🟢 | P1a | `publish` | BE-04 | 422 `missing_instruction`; continua rascunho |
| T14b | B3 | escrita 🟢 | P1 com instrução, sem teste | `publish` | O2 (D15) | 422 `missing_test`; continua rascunho em E3 |
| T15 | B1 | escrita 🟢 | P1, usuário P3 | `PATCH agents/{P1}`; o `DELETE` só roda se o PATCH devolver 401 | Escrita bloqueada | 401 nos dois; P1 igual |
| T16 | B1 | escrita 🟢 | P1, admin da conta (não SuperAdmin) | `GET agents/{P1}/tools`; `PATCH config.native_tool_slugs` | Ferramentas / BE-19 | `tools` 401; PATCH 422 `config_key_not_allowed`; `config` relido igual |
| T17 | B3 | escrita 🟢 | P1 ligado em P2 | pausar e mandar mensagem do meio P2 | Pausa devolve conversa | Q5 = 0; conversa nova sem bot; nenhum `replied` na janela de ausência |
| T18 | B3 | escrita 🟢 | idem | religar pelo interruptor (sem novo teste, D24) e mandar mensagem | Volta a atender | 200; `replied` +1 dentro do limite de mensagem real |
| T25 | B5 | escrita 🟢 | P1c em P2 | mensagem "quero falar com uma pessoa" | Nota privada e alvo (BE-24, BE-06) | 1 nota privada na conversa; o meio P2 recebe só a resposta do agente (a nota não chega, na janela de ausência); evento `handed_off` com alvo = time T; `conversation.team` = T; responsável membro de T; Q17 = 0 |
| T26 | B4b | escrita 🟢 | P1d em P2 | conversa nova | Primeira mensagem (BE-30) | a primeira mensagem enviada pelo agente em P2 contém "Xilofante" |
| T27 | B4b | escrita 🟢 | P1d com "Nunca" em P2 | (1) pergunta fora do que ele sabe; (2) "quero falar com uma pessoa" | "Nunca" e exceção (BE-12, §6.3 item 5) | (1) a resposta contém "Pirulândia" e nenhum `handed_off` na janela de ausência; (2) `handed_off` +1 |
| T19 | B3 | escrita 🟢 | P1 | excluir | Limpeza | 204 (`agents_controller.rb`, `head :no_content`); Q6 = 0; conversa com a equipe |
| T20 | B1 | leitura | conta B (P4) | copiloto com conversa de outra conta | Isolamento | 404 ou `available:false` |
| T21 | B2 | escrita 🟢 | conversa de P2 | `POST agents/message_reports` numa mensagem do P1 | Resposta errada | 200 (`message_reports_controller.rb`, render padrão); `wrong_replies` +1; motivo e descrição na gaveta (BE-28) |
| T22 | B3 | escrita 🟢 | P5 | Construtor `sdr` até o nome | Tipo e nome | nasce `sdr`; após a resposta do nome, `name` = nome dado; sai de `processing` dentro de `STALE_PROCESSING_AFTER` (BE-15) |
| T23 | F1 | leitura | conta 16, usuário P3 | UI 1440/400, claro/escuro, telas principais, com `agents-prod.config.ts` (nenhum clique em botão de escrita) | Visual | `scrollWidth ≤ viewport`; alvos ≥ 44 px |
| T29 | B1 | leitura (exige P0) | agente ativo da conta 2, stack autonomia | `POST test` com pergunta do negócio da conta | Stack autonomia | como T07; zero evento novo |
| T30 | B2 | escrita 🟢 | conta B (P4) | Super Admin liga e desliga "Tela nova de Agentes" | Flag e volta das telas (BE-00, §14) | `autonomia_agents_redesign_enabled` muda só na conta B; conta 16 igual; com a flag desligada, a rota resolve o componente antigo |
| T31 | B6b | leitura | Lia | `GET agents/{lia}` | Agente de Cotação exposto (BE-17) | `quote_choices` = `config.agente_de_cotacao` da foto; `quote_branches` presente; sem `instruction` |
| T24 | todos | leitura | duas stacks | Q1–Q17 depois de apagar P1 e P5 | Efeito colateral | invariantes = 0 / ok; diferenças de estado só as explicadas pelo próprio tester |

**Pacote por deploy** (o que roda depois de cada um; vale também para a linha do §10.1):
- **B1:** T01–T08, T10, T15, T16, T20, T29, T24, mais Q2, Q4–Q6, Q11 e Q12.
- **B2:** acrescenta T09, T12, T21, T30.
- **B3:** acrescenta T13a, T13, T14, T14b, T17, T18, T19, T22.
- **B4b:** T07–T10, T26, T27, T29, mais Q4, Q13, Q15 e Q16.
- **B5:** T25, T17, T18, mais Q16 e Q17.
- **B6b:** T10, T31, mais Q10.
- **F1+:** T23.

---

## Pendências obrigatórias (rodada 6)

### R6-09 [media] (tecnica) §11.8 T25 (PRD.md:1181) × BE-06 (PRD.md:462) × CA-AJU-07 (PRD.md:996)
**Problema:** A T25 tem uma afirmação dura, "responsável membro de T", que o BE-06 não promete e que o código não entrega na caixa do agente. Pelo BE-06, com alvo time o efeito é só `update!(team:)`. Nas caixas com espelho a conversa já nasce `open`, então o `bot_handoff!` não muda o status e a distribuição automática não roda: a conversa fica sem responsável, como hoje. Uma implementação correta do BE-06 reprova a T25. Pela regra de §11.7, cenário do tester que falha aborta e volta o B5 sozinho, ou seja, a volta dispara em falso.
**Evidência:** conversation.rb:354-363 (`set_active_bot_conversation`: caixa com bot webhook não força `pending`, a conversa nasce open); conversation.rb:192-197 (`bot_handoff!` chama `open!`, sem transição quando já está open); auto_assignment_handler.rb:15-18 (a distribuição legada só roda com `status_changed? && open?`) e :56-64; agent.rb:135 em origin/main ('bot_handoff!, conversa fica unassigned'); PRD.md:462 (BE-06: `team` → `update!(team:)`); PRD.md:1117 (cenário do tester que falha → aborta e volta).
**Correção:** Na T25, afirmar só o que o BE-06 garante: `conversation.team` = T, evento `handed_off` com alvo T, Q17 = 0. Ou então decidir no BE-06 que alvo time também atribui uma pessoa do time (e como, já que a conversa não muda de status), com caso em §7.2 e pré-requisito em P1c/P2 (distribuição automática ligada, `team.allow_auto_assign`).

### R6-10 [media] (tecnica) §11.7 Q4 (PRD.md:1096) e regra de aborto (PRD.md:1117)
**Problema:** A Q4 é Invariante (aborta e volta sozinha): uma entrada elegível com 0 `replied` em 30 min conta como desvio. Mas "entrada elegível" não está definida, e o código produz 0 `replied` em caminhos legítimos: porta de horário ou público (evento `skipped_*`), sinal de silêncio da instrução, humano que assumiu durante a chamada, e mensagens seguintes de uma conversa já passada para a equipe, em que o bot não está mais no comando. Um deploy fora do horário de um agente com `response_window` dispara a volta automática sem defeito. A Q4 também conta 'desde o deploy', enquanto o §11.7 manda a janela começar no horário da foto. Isso fere o passo 6(d) do §10.3.
**Evidência:** operate/responder.rb (origin/main) :55 (`silencio_por_inelegibilidade`), :60 (`skip_for_humans(blocked)`, só grava `skipped_*`), :70 (`silence_with_async`, motivo `sinal`/`vazio`/`nao_elegivel`, :347), :178 (`bot_still_in_command?`); agent_event.rb:52 (HANDOFF_TYPES inclui `skipped_audience`/`skipped_schedule`); PRD.md:1096 e :1117.
**Correção:** Definir "entrada elegível" pelo próprio código: conversa com o espelho no comando, agente operando e porta de engajamento aberta. Contar como atendida qualquer saída registrada (`replied`, `handed_off`, `skipped_*`, silêncio registrado), não só `replied`. Começar a janela no horário da foto. Se não der para tirar o falso positivo com segurança, rebaixar a Q4 para Estado (vai para decisão).

### R6-14 [baixa] (tecnica) §11.7 Q16 (PRD.md:1108)
**Problema:** A Q16 diz usar "a fórmula do Analytics (passagens ÷ (`replied` + passagens), conversas distintas)". O Analytics conta eventos, não conversas distintas, e soma às passagens os `skipped_audience`/`skipped_schedule`. A comparação informativa enviada ao Rodrigo depois do B4b/B5 vai divergir do número que a tela Como está indo mostra para o mesmo agente.
**Evidência:** analytics.rb:80-104 (`counts_by_type` por evento; `handoff_count` soma HANDOFF_TYPES; `handoff_rate` = handoffs / (replies + handoffs) sobre contagem de eventos); agent_event.rb:52 (HANDOFF_TYPES = handed_off, skipped_audience, skipped_schedule); PRD.md:1108.
**Correção:** Escolher um dos dois e escrever: fórmula idêntica à do Analytics (eventos, com `skipped_*`), coerente com a tela; ou taxa por conversa distinta, declarada como diferente da tela.

### R6-15 [alta] (seguranca) §14 Volta, parágrafo 'Limpeza de rascunhos (BE-14, no B1)' (PRD.md:1268-1271) × §11.7 'Quem decide' (PRD.md:1117-1118)
**Problema:** A proteção que o §14 escreve contra a perda de rascunhos ao voltar o B1 não funciona. A ideia é subir AUTONOMIA_DRAFT_REAP_HOURS antes da volta, mas a volta padrão religa a instância anterior, e essa instância continua lendo o .env gravado no primeiro boot dela. A mudança no parâmetro do SSM só chega a instâncias novas. A instância que volta roda o job antigo com 48 h e apaga, com materiais e entradas de conhecimento, rascunho guiado com instrução, resposta ou material. É justamente o que a tela nova prometeu guardar, e a perda não tem volta. Além disso, o §11.7 manda o invariante 'abortar e voltar sozinho', enquanto o §14 exige antes uma mudança de ENV com 🟢. Fica sem definição quem faz o passo, e quando, num aborto automático do B1.
**Evidência:** deploy-hub2you-blue-green.yml:260 e 277-283: o `.env` é escrito por `aws ssm get-parameter` dentro do user-data da instância nova. O job `rollback` (linha 1085 em diante) só faz `ec2 start-instances` (1155) e `systemctl restart` do web e do worker (1180, 1194), sem reler o .env. deploy-autonomia-blue-green.yml faz igual (rollback a partir da 1077: só start-instances e restart). reap_stale_drafts_job.rb:45-51 (critério antigo sem olhar instrução, resposta ou material), :64 (ENV lido em tempo de execução, mas do .env da instância), :37 (`destroy!`). config/schedule.yml:195-199 (`0 */6 * * *`). PRD.md:1270 ('subir AUTONOMIA_DRAFT_REAP_HOURS… (🟢, mudança de ENV com backup antes)'); PRD.md:1117 ('aborta e volta sozinho, pela volta do §14').
**Correção:** Reescrever a volta do B1 sobre o mecanismo real. Antes do `start-instances`, a volta precisa tirar a limpeza de cena na instância que vai religar. Opções: editar por SSM o `/opt/chatwoot/.env` dela logo depois do boot e antes do `restart chatwoot-worker`; desligar o cron `autonomia_reap_stale_drafts_job` pelo sidekiq-cron no Redis compartilhado; ou não usar o rollback de um degrau para o B1 e voltar por lote novo com revert que mantém o BE-14. Escrever esse passo como pré-aprovado para o aborto automático (sem 🟢 novo), com o comando exato. Acrescentar caso de aceite: volta do B1 com rascunho E2–E4 parado há mais de 48 h não apaga nada (conferir por psql antes e depois do primeiro ciclo do cron).

### R6-16 [alta] (seguranca) §11.7 Q4 (PRD.md:1096) × 'Quem decide' (PRD.md:1117) × 'A evidência vem só do banco' (PRD.md:1084-1085) × pacote B1/B4b (PRD.md:1195, 1198)
**Problema:** A Q4 é invariante: dispara a volta automática quando um agente tem pelo menos 1 'entrada elegível' e 0 `replied` em 30 min. O atendimento, porém, deixa de responder em vários casos legítimos sem gravar `replied`. Primeiro, fora do horário ou do público, a porta de engajamento passa a conversa direto para a equipe e grava `skipped_*`. Segundo, a instrução pode emitir o sinal de silêncio (despedida, robô, anti-loop). Terceiro, um humano pode ter assumido a conversa. 'Entrada elegível' não está definida. O silêncio legítimo só vai para o log do container, que o próprio §11.7 proíbe usar como evidência, então no banco ele não se distingue de uma falha de IA. Com o volume real (Clara: 3 conversas em 7 dias), basta um 'obrigado, tchau' ou uma mensagem fora do horário depois de um deploy noturno para voltar o B1. Isso desfaz o BE-19 e o BE-25 (falhas de segurança abertas hoje) e ainda dispara a perda de rascunhos do achado anterior.
**Evidência:** responder.rb:55 (`silencio_por_inelegibilidade`), :59-60 (porta → `skip_for_humans`, que grava `skipped_*` e não `replied`, :161-174), :69-70 e :347-353 (silêncio por `sinal`, `ia_falhou` ou `vazio`), :373-375 (`registrar_silencio` só faz `Rails.logger.info`, sem linha no banco). agent_event.rb:49-52 (`skipped_audience`/`skipped_schedule` são outros tipos de evento). PRD.md:1084-1085 (evidência nunca do log do container); PRD.md:1087 (volume baixo); PRD.md:1096 e 1117.
**Correção:** Definir 'entrada elegível' em comportamento: só mensagem de cliente em conversa com o espelho no comando, dentro do horário e do público, e sem evento `skipped_*` ou `handed_off` no mesmo episódio. Se o silêncio legítimo não se distingue da falha no banco, a Q4 deixa de ser invariante e passa a 'Estado: lista ao Rodrigo'. A prova de 'continua respondendo' fica com o tester (T07/T18/T29), que tem afirmação dura. Responder o passo 6(d) do §10.3 por escrito para a Q4.

### R6-17 [media] (seguranca) §11.7 Q8 (PRD.md:1100) × 'Quem decide' (PRD.md:1117) × BE-15 no B1 (PRD.md:471, 653) × pacote B1 (PRD.md:1195)
**Problema:** A Q8 é invariante sem janela de tempo: conta toda conversa do Construtor em `processing` há mais que STALE_PROCESSING_AFTER, e qualquer valor acima de 0 dispara a volta automática. Só que uma thread presa não sai sozinha de `processing`. Ela só é retomada quando a pessoa reenvia, então toda thread abandonada no meio de uma geração que morreu continua no banco e conta para sempre. A Q8 pode dar mais que 0 já na primeira execução, sem defeito nenhum do deploy, e voltar um lote correto. Quando o worker antigo para no blue-green, um SubmitJob em andamento também pode deixar thread presa. O PRD não traz o volume real dessa contagem, que o passo 6(a) do §10.3 exige. Por fim, o BE-15 (que muda a própria constante) sobe no B1, mas a Q8 não está no pacote do B1; ela só roda pela T24.
**Evidência:** build_thread.rb:123-127 (o comentário admite que a thread fica `processing` quando o job 'morreu/perdeu-se sem mark_failed!'; `STALE_PROCESSING_AFTER = 5.minutes`), :136-137 (`build_stale?` só calcula, não corrige), :152-157 (`begin_build!` só reassume quando chega um turno novo). Nenhum job zera threads presas (grep de `STALE_PROCESSING_AFTER` em app/: só build_thread.rb e build_threads_controller.rb:30). PRD.md:1100, 1117, 1195.
**Correção:** Limitar a Q8 a threads que entraram em `processing` depois do horário da foto (`updated_at` maior que a foto e menor que agora menos STALE_PROCESSING_AFTER). As antigas viram Estado informativo. Ler por psql o volume atual nas duas stacks e registrar. Pôr a Q8 no pacote do B1 (BE-15).

### R6-19 [media] (seguranca) §11.8 T25 (PRD.md:1181) × pré-requisitos P1c/P2 (PRD.md:1147, 1151-1152) × BE-06 'team → update!(team:)' (PRD.md:462)
**Problema:** A T25 afirma, com afirmação dura, 'responsável membro de T'. Com o alvo time, o BE-06 só grava o time na conversa. Quem escolhe a pessoa é a atribuição automática do Chatwoot, que exige três condições que nenhum pré-requisito fixa: a caixa P2 com atribuição automática ligada, o time T com `allow_auto_assign`, e o usuário de teste online. Sem elas, a conversa fica sem responsável, e a T25 falha sem defeito ou vira 'BLOQUEADO' de improviso. Além disso, o time é gravado antes do `bot_handoff!`, enquanto `ai_assignee` ainda está presente, e `ensure_assignee_is_from_team` sai cedo nesse estado. A pessoa só é escolhida depois, no `open!`, e nem a Q17 nem o evento registram quem foi. A promessa 'não atribui gente de fora do time' fica comprovada só pela T25, que depende de configuração não declarada.
**Evidência:** assignment_handler.rb:12-18 (`return if ai_assignee_type.present?`), :24-29 (`find_assignee_from_team` exige `team.allow_auto_assign`); auto_assignment_handler.rb:15-21 e 41-65 (só com `inbox.enable_auto_assignment?`; com time, `team_member_ids_with_capacity` volta [] sem `allow_auto_assign`); agent_assignment_service.rb:7-9 (`allowed_online_agent_ids`: só quem está online); conversation.rb:192-197 (`bot_handoff!` zera `ai_assignee` e chama `open!`). PRD.md:1147, 1151-1152, 1181.
**Correção:** Acrescentar ao P2/P1c, com 🟢: caixa P2 com atribuição automática ligada, time T com 'atribuir automaticamente' e o usuário de teste online durante a T25. Registrar esses três valores como pré-condição conferida por psql, e sem eles a T25 fica BLOQUEADA. Ou mudar a afirmação para o que o BE-06 garante (`conversation.team` = T e, se houver responsável, ele é membro de T). Neste caso, acrescentar em §7.2 BE-06 o caso 'time sem atribuição automática → fica sem responsável, sem atribuir gente de fora'.

### R6-20 [media] (seguranca) §14 'lote de um PR só' (PRD.md:1260-1264) × §10.1 B1/B4b/B5/B6b (PRD.md:653, 657-660) × docs/processo-de-release.md (fila de merge)
**Problema:** Toda a volta de um degrau para o caminho ao vivo depende de B1, B4b, B5 e B6b subirem num lote de um PR só. Pelo processo de release vigente, porém, a `main` só recebe código pela fila de merge, e a fila junta até 2 PRs por rodada num único push e num único deploy. O PRD não diz como garantir que a fila não junte o PR do lote ao de outra sessão. Se juntar, o `action=rollback` do aborto automático desfaz também o PR da outra sessão, e o tester e as Q passam a medir dois PRs ao mesmo tempo.
**Evidência:** docs/processo-de-release.md:72-84 ('A main só recebe código pela fila… Ela junta até 2 PRs por rodada, testa o código combinado uma vez e faz um único push na main, que gera um único deploy'), :58-60 (o rollback desfaz o lote inteiro). PRD.md:1261-1263 ('todo PR que muda o caminho ao vivo… sobe num lote de um PR só: o rollback desfaz só ele').
**Correção:** Escrever no §14 e no §10.1 como o PR entra sozinho: coordenar com a sessão Automação para que a fila esteja vazia (sem outro PR enfileirado) do `gh pr merge` até o deploy, e conferir depois do merge, pelo `git log` da `main`, que o push tem só esse PR. Se veio junto, a volta é por revert e lote novo, com a espera explícita. Acrescentar essa conferência à lista do 'ok, SHA'.

### R6-21 [media] (seguranca) §11.8 regra 'Vale a partir de' (PRD.md:1130) × 'Pacote por deploy' (PRD.md:1194-1201) × §10.1 dependências (PRD.md:657-660)
**Problema:** As duas regras novas da rodada 5 se contradizem. A regra diz que cada deploy roda todos os T com 'Vale a partir de' até o PR do deploy, o que é cumulativo. Já o pacote do B4b, do B5 e do B6b lista só alguns T e deixa de fora a T24, que vale para 'todos' e é a que roda Q1–Q17 (efeito colateral, Q2 isolamento, Q5/Q6/Q11). Também ficam de fora T01–T06, T15, T16 e T20. Justamente nos deploys que mudam o caminho ao vivo, a conferência de isolamento e de efeito colateral não está prevista. 'Até o PR' também supõe uma ordem linear que o §10.1 não impõe: B4b, B5 e B6b dependem só do B1. Se o B5 subir antes do B3, a T25 precisa do P1 ligado em P2 pelo `publish`, que é a T13a do B3, e o pacote do B5 não monta o P1 (P1a/P1b/T13a). A T25 fica BLOQUEADA ou vira improviso.
**Evidência:** PRD.md:1130 ('Cada deploy roda só os T com Vale a partir de ≤ o PR do deploy'); PRD.md:1192 (T24 'todos'); PRD.md:1198-1200 (B4b, B5 e B6b sem T24 e sem T01–T06/T15/T16/T20); PRD.md:1199 (B5: T25, T17, T18 sem T13a nem os passos P1a/P1b); PRD.md:1145-1147 (P1c depende de P1b → T13a); PRD.md:658 (B5 depende só de B1); PRD.md:1173 (T13a vale a partir do B3).
**Correção:** Escolher uma regra só. Ou o pacote é cumulativo e sempre inclui a T24 (com Q2, Q5, Q6 e Q11), ou a regra 'Vale a partir de' sai e o pacote é a lista completa de cada deploy. Fixar no §10.1 a ordem B3 antes de B5 (ou dar à T25 um caminho próprio para ligar o P1 que não dependa do B3) e listar no pacote do B5 os passos do P1 que a T25 exige.

### R6-22 [alta] (testes) §11.8 Pacote por deploy (PRD.md:1194-1201) × §11.7 cabeçalho e foto (PRD.md:1076, 1080, 1082-1083) × Ordem final (PRD.md:1157) × T24 (PRD.md:1192)
**Problema:** Os pacotes do B4b, do B5 e do B6b não acumulam o que vem antes: cada um é uma lista própria, enquanto o B2 e o B3 usam "acrescenta". Por isso, depois dos deploys que mudam o atendimento ao vivo, ficam de fora: (1) a T24, que confere os efeitos colaterais; (2) os invariantes Q2, Q5, Q6 e Q11, que pela §11.7 abortam o deploy sozinhos; (3) a comparação de Q1 e Q7 com a foto, que é tirada justamente para isso. A Q8 não aparece em nenhum pacote, nem no B1, que leva o BE-15 (a janela do Construtor que a Q8 mede). Os pacotes também não trazem a montagem do P1 (T14, T14b, T09, T13a) nem a exclusão (T19), mas o B4b roda T09, T26 e T27 e o B5 roda T17, T18 e T25, que dependem de P1 ligado em P2. E a regra "P1 apagado antes da T24" não tem T24 para cumprir nesses deploys. Isso contradiz o "Q1–Q17 rodam nas duas stacks" da §11.7.
**Evidência:** PRD.md:1198 (B4b: só T07–T10, T26, T27, T29 + Q4, Q13, Q15, Q16); PRD.md:1199 (B5: T25, T17, T18 + Q16, Q17); PRD.md:1200 (B6b: T10, T31 + Q10); PRD.md:1195 (B1 sem Q8, com BE-15 no B1 em PRD.md:654); PRD.md:1080 ("Q1–Q17 rodam nas duas stacks"); PRD.md:1117 (Q2, Q5, Q6, Q8, Q11 abortam); PRD.md:1145-1149 (T26/T27 dependem de P1 ligado em P2 por T13a); PRD.md:1157 e 1192.
**Correção:** Definir um núcleo fixo que roda depois de todo deploy que muda comportamento: Q1–Q17 nas duas stacks (invariantes e comparação com a foto), montagem do P1 (T14 → T14b → T09 → T13a) e exclusão (T19), e a T24 no fim. Os pacotes por PR passam a dizer só o que soma a esse núcleo. Pôr a Q8 no B1, no B3 e em todo deploy que toca o Construtor.

### R6-23 [alta] (testes) §11.8 P2 (PRD.md:1151) × T17, T18, T25, T26, T27 (PRD.md:1179-1183) × regra de aborto (PRD.md:1117)
**Problema:** O P2 define a caixa e o meio de mandar mensagem, mas não diz qual contato usar nem em que estado a conversa precisa estar antes de cada cenário. Numa caixa WhatsApp (WAHA), o mesmo contato reaproveita sempre a última conversa, mesmo resolvida. O agente só responde em conversa sem responsável, e as caixas nascem com atribuição automática ligada. Consequências: (1) a T25 afirma que o responsável é membro do time T; daí em diante, nenhuma mensagem desse contato em P2 é respondida, e T26 e T27, que vêm depois na ordem do P1, falham com o código certo; (2) a "conversa nova" da T17 e da T26 não existe com o mesmo telefone; (3) na T17, a conversa aberta com o agente pausado pode ser atribuída ao usuário de teste, que é membro de P2, e aí a T18 (religar → `replied` +1) falha. Cenário do tester que falha aborta e volta o deploy sozinho: o B4b voltaria sem defeito.
**Evidência:** app/services/waha/inbox_provisioner.rb:86-90 (`lock_to_single_conversation: true`); app/services/whatsapp/incoming_message_base_service.rb:173-182 (com o lock, `conversations.last`); app/services/autonomia/agents/operate.rb:14-17 (`return if conversation.assignee_id.present?`); app/jobs/autonomia/agents/operate/reply_job.rb:38-39; db/schema.rb:2808 (`enable_auto_assignment` default true); PRD.md:1147-1148 (P1c → T25 → P1d → T26, T27); PRD.md:1181 (T25: "responsável membro de T").
**Correção:** No P2: um contato de teste por cenário que precisa de conversa nova (T17, T18, T25, T26, T27), ou um passo de reinício com 🟢 entre os cenários (resolver e tirar o responsável). Desligar a atribuição automática da caixa P2 durante o teste. Como pré-condição dura de cada cenário de mensagem real, conferir que a conversa está sem responsável (`assignee_id` nulo) antes de mandar.

### R6-24 [media] (testes) §11.7 Q4 (PRD.md:1096) × regra de aborto (PRD.md:1117) × evidência só do banco (PRD.md:1084-1086)
**Problema:** A Q4 é um invariante que aborta sozinho, mas "entrada elegível" não está definida em nenhum lugar do PRD. Pelo banco não dá para separar os casos legítimos de zero `replied`: (1) mensagem do cliente numa conversa que já foi passada e tem responsável, o que é rotina na Clara e na Lia; (2) silêncios por sinal, resposta vazia ou não elegível, que só deixam linha no log, e o PRD proíbe usar o log como evidência; (3) a Lia, que pode levar bem mais de 30 min num turno (até 6 rodadas, cada uma esperando um especialista de até 6 × 180 s), enquanto o próprio tester espera até `debounce_seconds` + 30 min por uma resposta. Do jeito escrito, a Q4 dispara volta automática por uso normal. A Q4 também fala em "desde o deploy", e a §11.7 manda a janela começar no horário da foto.
**Evidência:** PRD.md:1096 (único uso de "elegível"); app/services/autonomia/agents/operate.rb:15 (conversa com responsável não é elegível); app/services/autonomia/agents/operate/responder.rb:347-375 (silêncio só em `Rails.logger`); app/services/autonomia/insurance/quote_agent/builder.rb:152-157 (`RODADAS_DA_LIA = 6`, `max_segundos: 6 * espera`); app/services/autonomia/agents/specialists/runner.rb:43-45; PRD.md:1136 (debounce + 30 min); PRD.md:1084.
**Correção:** Definir "entrada elegível" só com o que o banco guarda: mensagem de entrada em conversa sem responsável, sem evento `handed_off`/`skipped_*` anterior no mesmo episódio, criada depois da foto. Dar um prazo por tipo de agente (a Lia à parte, pelo orçamento de `rodadas_do_turno`). Ou passar a Q4 para "Estado" (lista ao Rodrigo) até existir evidência no banco de silêncio legítimo.

### R6-25 [media] (testes) §11.7 Q5 e Q8 (PRD.md:1097, 1100) × regra de aborto (PRD.md:1117) × passo 6(d) do §10.3
**Problema:** A Q5 e a Q8 abortam sozinhas, mas contam estado sem janela nem comparação com a foto, e os dois disparam com uso legítimo. A Q5 conta conversa `pending` na caixa de um agente pausado, e qualquer atendente pode marcar uma conversa como pendente pelo menu Resolver. A Q8 conta toda conversa do Construtor em `processing` além de `STALE_PROCESSING_AFTER`. Nenhum job devolve uma conversa presa a outro status (só um novo `begin_build!` a retoma). Então uma conversa que ficou presa no passado e foi abandonada, ou uma derrubada pelo próprio blue-green que mata o worker, fica contando para sempre e aborta todo deploy seguinte. É justamente o caso que o passo 6(d) manda responder ("o que dispara em falso com uso legítimo").
**Evidência:** app/javascript/dashboard/components/buttons/ResolveAction.vue:244-253 (`MARK_PENDING` → `toggleStatus(PENDING)`); app/models/autonomia/agents/build_thread.rb:127-161 (`STALE_PROCESSING_AFTER = 5.minutes`; só `begin_build!` retoma a conversa presa; não existe varredura); PRD.md:1097, 1100, 1117; PRD.md:729-731 (passo 6).
**Correção:** Q5: contar só conversas cujo `updated_at` é posterior à pausa e com o espelho como `assignee_agent_bot_id`, ou comparar com a foto. Q8: contar só conversas com `updated_at` depois da foto, ou pôr a Q8 na foto e abortar só por conversa presa nova. Responder por escrito o item 6(d) das duas.

### R6-26 [media] (testes) §11.8 T21 (PRD.md:1186) × pacote B2 (PRD.md:1196) × sequência do P1 (PRD.md:1145-1149)
**Problema:** A T21 vale a partir do B2 e está no pacote do B2. Ela precisa de uma mensagem do P1 numa conversa de P2, ou seja, do P1 ligado e respondendo. Na sequência do P1, porém, o P1 só é ligado em P2 pela T13a (`publish`, BE-03, B3), e a primeira resposta só sai na T18 (B3). No deploy do B2, a T21 só roda por um caminho que o pré-requisito não descreve (ligar pela API antiga) ou fica BLOQUEADA. A sequência do P1 também põe T15 e T16 (B1) depois da T13a (B3), e no B1 e no B2 não se sabe se esses passos rodam ou são pulados.
**Evidência:** PRD.md:1146 ("P1b … → T13a (ligar na caixa P2) → T13, T15, T16, T17, T18"); PRD.md:1173 (T13a vale a partir do B3); PRD.md:1186 (T21 vale a partir do B2, "numa mensagem do P1"); PRD.md:1196 (B2 acrescenta T21); app/services/autonomia/agents/operate/inbox_connector.rb:35 (ligar exige o agente ativo).
**Correção:** Mudar a T21 para "vale a partir do B3", ou descrever no P1 o caminho de ligar em P2 antes do B3 (PATCH de status pela API atual + `POST channels`, cada um com 🟢). Dizer, para cada deploy, quais passos da sequência do P1 rodam e quais são pulados.

### R6-27 [media] (testes) §10.1 B2, B4, B6a (PRD.md:655-659) × §10.2 passo 8 (PRD.md:697) × Pacote por deploy (PRD.md:1194-1201)
**Problema:** Há deploys que mudam a produção e não têm nenhum cenário. O B4 (BE-02, endpoint novo que copia material entre agentes com 404 entre contas; BE-23, que muda a API de versões e a passagem de guiado para manual) e o B6a (BE-13, criação de caixa WhatsApp em produção) não aparecem no pacote por deploy, embora o §10.2 exija tester nos PRs que mudam comportamento em produção. O B2 leva o BE-16, que renomeia ao vivo o AgentBot espelho da Clara e da Lia, mas o pacote do B2 não confere o nome do espelho. A Q10, que inclui esse nome, só roda no B6b.
**Evidência:** PRD.md:472 (BE-16: `after_update` sincroniza nome e avatar do espelho); PRD.md:458 (BE-02 `sources/copy`, 404 entre contas); PRD.md:469 (BE-13); PRD.md:479 (BE-23); PRD.md:1194-1201 (sem linha para B4 e B6a; Q10 só no B6b); PRD.md:1102 (a Q10 inclui o "nome do AgentBot espelho").
**Correção:** B2: incluir a Q10 e a Q11 com o nome dos espelhos comparado à foto. B4: um T de leitura `sources/reusable` e um `sources/copy` com token da conta B (P4) → 404, e `GET instruction_versions` da Clara sem texto em versão guiada (NR-10). B6a: um T de leitura do passo do número com telefone inválido → 422 `invalid_phone`, sem criar caixa, ou registrar por que o BE-13 não tem cenário em produção.
