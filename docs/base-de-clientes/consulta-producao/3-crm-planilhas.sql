-- 3-crm-planilhas.sql
-- Pesquisa #1240 (Relacionamentos e Base de clientes). Consulta de producao, versao 2, parte 3 de 5.
-- CRM (negocio) e importacoes de planilha (partes H e I).
-- Blocos 22 a 37 (16 no total). A numeracao dos blocos e a mesma nas 5 partes e no LEIA-ME.md.
--
-- QUEM RODA: outra sessao, por psql, nas duas instalacoes (Hub2You e Autonom.ia), com usuario de leitura, fora de deploy,
-- depois de conferir no pg_stat_activity que nao ha DDL em andamento. Uma parte por vez, em qualquer ordem.
--   psql "<conexao>" -X -v ON_ERROR_STOP=1 -f 3-crm-planilhas.sql > saida-3-<instalacao>.txt 2>&1
-- Precisa ser psql: usa \echo, \set e a variavel :ativas. Nao roda em cliente grafico.
--
-- GARANTIAS (as mesmas nas 5 partes; detalhes e testes no LEIA-ME.md)
--   * Somente leitura: BEGIN TRANSACTION READ ONLY ... ROLLBACK, uma transacao por parte. Nenhum INSERT/UPDATE/DELETE/
--     CREATE, nem tabela temporaria.
--   * Carga: cada bloco tem no maximo 60 s (statement_timeout) e espera no maximo 2 s por trava (lock_timeout). Teto desta
--     parte: 16 x 60 s. Se um bloco passar do limite, o psql para ali (ON_ERROR_STOP) e a transacao e desfeita; o que ja
--     saiu vale. A trava de leitura (ACCESS SHARE) dura so ate o ROLLBACK desta parte.
--   * Somente totais: nenhum SELECT devolve nome, telefone, e-mail, identifier, conteudo de mensagem, titulo/descricao/motivo
--     de card, nome de empresa, funil ou etapa, nem VALOR de campo (custom_attributes / additional_attributes / custom_data).
--     Saem: account_id, contagens, percentuais, percentis, meses (AAAA-MM), codigos do sistema (status, channel_type, fluxo e
--     metodo de importacao, opt_out_source e origem de card comparados com a lista do codigo) e textos que passam na
--     REGRA DO TEXTO. Dominio de e-mail, etiqueta e origem de card digitada nunca saem como texto: so contagem (o bloco 18
--     so imprime dominios escritos na propria consulta, nunca um lido do banco).
--   * REGRA DO TEXTO. Vale para chave de campo, nome exibido de campo, titulo de coluna de planilha e chave de JSON. O texto
--     so sai quando (1) nao tem '@', (2) tem menos de 6 digitos e (3) aparece em pelo menos :min_contas contas ativas (3,
--     definido abaixo). Nos blocos de campo (21, 28, 46, 48, 49, 50, 51) so conta a conta em que a chave tem VALOR, nao
--     a que so tem a definicao. Titulo de planilha (blocos 32 a 35) e chave de e-mail (bloco 37) tem ainda a condicao
--     (4): so conta planilha (ou campanha) "boa", com pelo menos 2 titulos preenchidos e nenhum com '@' ou 6+ digitos.
--     Fora disso o cabecalho provavelmente e uma linha de dado, e NENHUM titulo dela entra na lista nem na contagem de
--     contas. Em (3) conta-se a CONTA, nao a planilha: a mesma planilha importada de novo na mesma conta, com ou sem
--     coluna a mais, nao soma. O teste e feito no texto inteiro; o texto sai em minusculas, sem
--     espaco nas pontas, cortado em 60 caracteres. O que nao passa vira '(oculto)' e entra so na contagem (nas listas de
--     titulos mais comuns, fica de fora e e contado no bloco 35). Digitos contados com translate(), sem regex.
--     Por que (3): o "Importar contatos" (#1006) cria campo de contato com o titulo da coluna como nome
--     (app/services/contact_imports/custom_attributes.rb:47-51); planilha cujo cabecalho foi lido errado pode ter criado
--     campo com nome de pessoa. Texto de uma ou duas contas nunca sai.
--
-- REFERENCIAS (worktree 1240-pesquisa-relacionamentos, igual a producao)
--   As linhas de db/schema.rb citadas aqui sao da worktree (a82d4517a4) e mudam a cada migration (no main 785271922d,
--   messages comeca na 3297); o que vale e o nome da tabela e do indice, que e o mesmo nos dois.
--   Tabelas e colunas conferidas em db/schema.rb: accounts 76; campaign_imports 1175; companies 1661; contact_inboxes 1678;
--   contacts 1693; conversations 1777; crm_card_conversations 2041; crm_cards 2060; crm_pipeline_inboxes 2513;
--   crm_pipeline_stages 2531; crm_pipelines 2553; custom_attribute_definitions 2741; email_campaign_imports 2882;
--   email_campaign_recipients 2896; email_campaigns 2967; inboxes 3253; labels 3304; messages 3378; taggings 3600; tags 3619.
--   Enums (inteiros):
--     accounts.status                 app/models/account.rb:157              active=0 suspended=1
--     contacts.contact_type           app/models/contact.rb:79               visitor=0 lead=1 customer=2
--     messages.message_type           app/models/message.rb:88               incoming=0 outgoing=1 activity=2 template=3
--     custom_attribute_definitions    app/models/custom_attribute_definition.rb:48-49
--       attribute_model               conversa=0 contato=1 empresa=2 card=3
--       attribute_display_type        text=0 number=1 currency=2 percent=3 link=4 date=5 list=6 checkbox=7
--     crm_cards.status                app/models/crm/card.rb:96              open=0 won=1 lost=2 archived=3 resolved=4 cancelled=5
--     crm_pipelines.status            app/models/crm/pipeline.rb:43          active=0 archived=1
--     campaign_imports.status         app/models/campaign_import.rb:84-102   validation_failed=2 completed=7
--                                     completed_with_failures=8 failed=9 needs_column_choice=15
--     email_campaign_imports.status   app/models/email_campaign_import.rb:9  queued=0 processing=1 completed=2 failed=3
--     contacts.opt_out_source         app/models/concerns/contact_opt_out.rb:19,24  prospecting, email_unsubscribe, manual
--   Datas: contacts.last_activity_at = ultima mensagem cujo remetente e o contato (message.rb:349-350) ou data trazida por
--     importacao (app/services/data_imports/importer.rb:310,364); conversations.last_activity_at = ultima mensagem de
--     qualquer tipo na conversa (message.rb:465-467; coluna NOT NULL). Mensagem de historico da Coexistencia nao atualiza
--     nenhuma das duas (message.rb:337).
--
-- FEATURE FLAGS: como sai o bit de cada flag
--   app/models/concerns/featurable.rb:15-29 agrupa as flags de config/features.yml por coluna (sem "column:" = feature_flags)
--   e da a chave indice+1 a cada uma, na ordem do arquivo. A gem flag_shih_tzu 0.3.23 (Gemfile.lock:336) grava a chave n
--   como 1 << (n - 1) (flag_shih_tzu.rb:80). Logo: bit = 1 << (indice da flag DENTRO da sua coluna, contando do zero).
--   feature_flags (63 flags):  custom_attributes 14, crm 23, crm_integration 43, crm_v2 49, companies 57.
--   feature_flags_ext_1 (16):  whatsapp_manual_transfer 0, data_import 1, api_and_webhooks 2, whatsapp_reconfigure 3,
--                              whatsapp_embedded_signup_inbox_creation 4, delayed_automations 5, audit_log_ip_address 6,
--                              relationships_attributes 7, relationships_company_media 8, relationships_navigation 9,
--                              instagram_assisted_onboarding 10, meta_ads_hub 11, email_template_import 12,
--                              autonomia_agents_journey 13, crm_booking_v2 14, customer_base 15.
--

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '60s';
SET LOCAL lock_timeout = '2s';

-- Ajustes so do psql (nao vao ao banco): parar no primeiro erro, sem paginador, com o tempo de cada bloco.
\set ON_ERROR_STOP on
\pset pager off
\timing on

-- Contas ativas e as flags usadas nos blocos de CRM. E uma variavel do psql porque transacao READ ONLY nao aceita
-- CREATE TEMP VIEW. Cada bloco usa como subconsulta: JOIN :ativas a ON a.account_id = <tabela>.account_id
\set ativas '(SELECT id AS account_id, (feature_flags & (1::bigint << 23)) <> 0 AS crm, (feature_flags & (1::bigint << 49)) <> 0 AS crm_v2, (feature_flags & (1::bigint << 57)) <> 0 AS companies, (feature_flags_ext_1 & (1::bigint << 15)) <> 0 AS customer_base FROM accounts WHERE status = 0)'

-- REGRA DO TEXTO, condicao (3): numero minimo de contas ativas em que um texto precisa aparecer para sair.
-- Versao 2: subiu de 2 para 3 (auditoria da Orquestracao). Vale para todos os blocos desta parte.
\set min_contas 3

-- ============================================================================================================
-- PARTE H. CRM (negocio)
-- ============================================================================================================

\echo '== 22. Funis e etapas por conta ativa com funil (so contagens; nome de funil e de etapa nao sai) =='
SELECT a.account_id, a.crm, a.crm_v2,
       count(DISTINCT p.id) FILTER (WHERE p.status = 0) AS funis_ativos,
       count(DISTINCT p.id) FILTER (WHERE p.status = 1) AS funis_arquivados,
       count(DISTINCT p.id) FILTER (WHERE p.counts_as_sale) AS funis_contam_venda,
       count(DISTINCT s.id) AS etapas,
       count(DISTINCT s.id) FILTER (WHERE s.is_won_stage) AS etapas_ganho,
       count(DISTINCT s.id) FILTER (WHERE s.is_lost_stage) AS etapas_perda,
       (SELECT count(*) FROM crm_pipeline_inboxes pi
         WHERE pi.account_id = a.account_id AND pi.auto_create_card) AS caixas_criam_card
FROM :ativas a
LEFT JOIN crm_pipelines p ON p.account_id = a.account_id
LEFT JOIN crm_pipeline_stages s ON s.pipeline_id = p.id
GROUP BY a.account_id, a.crm, a.crm_v2
HAVING count(DISTINCT p.id) > 0
ORDER BY a.account_id;

\echo '== 23. Funis ativos: total e etapas por funil (mediana, p90, maximo) =='
WITH por_funil AS (
  SELECT p.account_id, p.id, count(s.id) AS etapas
  FROM crm_pipelines p
  JOIN :ativas a ON a.account_id = p.account_id
  LEFT JOIN crm_pipeline_stages s ON s.pipeline_id = p.id
  WHERE p.status = 0
  GROUP BY p.account_id, p.id
)
SELECT count(DISTINCT f.account_id) AS contas_com_funil_ativo,
       count(*) AS funis_ativos,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY f.etapas) AS etapas_p50,
       percentile_cont(0.9) WITHIN GROUP (ORDER BY f.etapas) AS etapas_p90,
       max(f.etapas) AS etapas_max
FROM por_funil f;

\echo '== 24. Cards por conta e status (0 aberto, 1 ganho, 2 perdido, 3 arquivado, 4 resolvido, 5 cancelado) (+ TOTAL) =='
SELECT coalesce(c.account_id::text, 'TOTAL') AS account_id,
       count(*) AS cards,
       count(*) FILTER (WHERE c.status = 0) AS abertos,
       count(*) FILTER (WHERE c.status = 1) AS ganhos,
       count(*) FILTER (WHERE c.status = 2) AS perdidos,
       count(*) FILTER (WHERE c.status = 3) AS arquivados,
       count(*) FILTER (WHERE c.status = 4) AS resolvidos,
       count(*) FILTER (WHERE c.status = 5) AS cancelados,
       count(*) FILTER (WHERE c.contact_id IS NULL) AS sem_contato,
       count(*) FILTER (WHERE c.value_cents > 0) AS com_valor,
       count(*) FILTER (WHERE c.external_id IS NOT NULL) AS com_external_id,
       count(*) FILTER (WHERE c.custom_attributes <> '{}'::jsonb) AS com_campo_personalizado
FROM crm_cards c
JOIN :ativas a ON a.account_id = c.account_id
GROUP BY ROLLUP (c.account_id)
ORDER BY c.account_id NULLS LAST;

\echo '== 25. Cards criados por mes, ultimos 18 meses (todas as contas ativas) =='
SELECT to_char(date_trunc('month', c.created_at), 'YYYY-MM') AS mes,
       count(*) AS cards,
       count(*) FILTER (WHERE c.status = 1) AS ganhos_hoje,
       count(DISTINCT c.account_id) AS contas
FROM crm_cards c
JOIN :ativas a ON a.account_id = c.account_id
WHERE c.created_at >= date_trunc('month', now()) - interval '17 months'
GROUP BY 1
ORDER BY 1;

\echo '== 26. Origem do card (crm_cards.source): codigos do sistema; texto digitado so na contagem (outro) =='
-- Versao 2 (auditoria da Orquestracao): a API aceita texto livre em source (cards_controller.rb:463,476), e o texto nunca
-- sai. A coluna origem so mostra o que esta numa lista fechada, escrita aqui:
--   (vazio);
--   o tipo de canal, que o card recebe quando nasce da conversa (app/services/crm/cards/creator.rb:41): as 12 classes de
--     app/models/channel/*.rb, em minusculas;
--   os codigos que o codigo grava: contact_request (crm/booking_v2/contact_request.rb:3), panel, public_link, invite e ai
--     (crm/booking_v2/booker.rb:188, chamado por panel_booking.rb:5, public_booking.rb:82,140 e
--     autonomia/agents/tools/native/agendar_reuniao.rb:5) e autonomia_prospecting (autonomia/prospecting/crm_card_converter.rb:102);
--   (outro) = qualquer outro texto, so contado (valores distintos, cards e contas).
WITH s AS (
  SELECT c.account_id, lower(btrim(coalesce(c.source, ''))) AS origem
  FROM crm_cards c
  JOIN :ativas a ON a.account_id = c.account_id
)
SELECT CASE WHEN s.origem = '' THEN '(vazio)'
            WHEN s.origem IN ('channel::api', 'channel::email', 'channel::facebookpage', 'channel::instagram', 'channel::line',
                              'channel::sms', 'channel::telegram', 'channel::tiktok', 'channel::twiliosms',
                              'channel::twitterprofile', 'channel::webwidget', 'channel::whatsapp',
                              'contact_request', 'panel', 'public_link', 'invite', 'ai', 'autonomia_prospecting') THEN s.origem
            ELSE '(outro)' END AS origem,
       count(DISTINCT s.origem) AS valores,
       count(*) AS cards,
       count(DISTINCT s.account_id) AS contas
FROM s
GROUP BY 1
ORDER BY cards DESC, 1;

\echo '== 27. Cards abertos parados e sem conversa, por conta (+ TOTAL) =='
-- Sem conversa = crm_cards.conversation_id nulo E nenhum vinculo em crm_card_conversations.
-- Parado = last_activity_at (ou updated_at, quando nulo) ha mais de 30 / 90 dias.
SELECT coalesce(x.account_id::text, 'TOTAL') AS account_id,
       count(*) AS abertos,
       count(*) FILTER (WHERE x.sem_conv) AS abertos_sem_conversa,
       count(*) FILTER (WHERE x.sem_conv AND x.ult < now() - interval '30 days') AS sem_conversa_parado_30d,
       count(*) FILTER (WHERE x.sem_conv AND x.ult < now() - interval '90 days') AS sem_conversa_parado_90d,
       count(*) FILTER (WHERE x.ult < now() - interval '30 days') AS abertos_parados_30d
FROM (
  SELECT c.account_id, coalesce(c.last_activity_at, c.updated_at) AS ult,
         (c.conversation_id IS NULL AND NOT EXISTS (
            SELECT 1 FROM crm_card_conversations cc WHERE cc.account_id = c.account_id AND cc.card_id = c.id)) AS sem_conv
  FROM crm_cards c
  JOIN :ativas a ON a.account_id = c.account_id
  WHERE c.status = 0
) x
GROUP BY ROLLUP (x.account_id)
ORDER BY x.account_id NULLS LAST;

\echo '== 28. Campos de card (crm_cards.custom_attributes) por conta e chave (REGRA DO TEXTO; nenhum valor) =='
-- definidas = chaves que existem em custom_attribute_definitions (attribute_model = 3) da conta; inclui definicao nunca usada.
-- Na linha (oculto) da conta, os numeros somam todas as chaves ocultas; pct_preenchido so aparece para chave visivel.
-- Versao 2: a chave so e visivel se tem VALOR em :min_contas ou mais contas (a definicao sozinha nao conta).
WITH tot AS (
  SELECT c.account_id, count(*) AS cards
  FROM crm_cards c
  JOIN :ativas a ON a.account_id = c.account_id
  GROUP BY c.account_id
),
ch AS (
  SELECT c.account_id, lower(btrim(k.key)) AS chave, count(*) AS cards_preenchidos
  FROM crm_cards c
  JOIN :ativas a ON a.account_id = c.account_id
  CROSS JOIN LATERAL jsonb_each(CASE WHEN jsonb_typeof(c.custom_attributes) = 'object'
                                     THEN c.custom_attributes ELSE '{}'::jsonb END) k
  WHERE k.value NOT IN ('null'::jsonb, '""'::jsonb, '[]'::jsonb, '{}'::jsonb)
  GROUP BY 1, 2
),
defs AS (
  SELECT DISTINCT d.account_id, lower(btrim(d.attribute_key)) AS chave
  FROM custom_attribute_definitions d
  JOIN :ativas a ON a.account_id = d.account_id
  WHERE d.attribute_model = 3
),
todas AS (
  SELECT coalesce(ch.account_id, df.account_id) AS account_id,
         coalesce(ch.chave, df.chave) AS chave,
         df.chave IS NOT NULL AS definida,
         coalesce(ch.cards_preenchidos, 0) AS cards_preenchidos
  FROM ch
  FULL JOIN defs df ON df.account_id = ch.account_id AND df.chave = ch.chave
),
vis AS (
  SELECT t.chave,
         count(DISTINCT t.account_id) FILTER (WHERE t.cards_preenchidos > 0) >= :min_contas
         AND position('@' IN t.chave) = 0
         AND length(t.chave) - length(translate(t.chave, '0123456789', '')) < 6 AS visivel
  FROM todas t
  GROUP BY t.chave
)
SELECT t.account_id,
       CASE WHEN v.visivel THEN left(t.chave, 60) ELSE '(oculto)' END AS chave,
       count(*) AS chaves,
       count(*) FILTER (WHERE t.definida) AS definidas,
       count(*) FILTER (WHERE t.cards_preenchidos = 0) AS nunca_preenchidas,
       sum(t.cards_preenchidos) AS cards_preenchidos,
       max(tt.cards) AS cards_da_conta,
       CASE WHEN bool_and(v.visivel)
            THEN round(100.0 * sum(t.cards_preenchidos) / nullif(max(tt.cards), 0), 1) END AS pct_preenchido
FROM todas t
JOIN vis v ON v.chave = t.chave
LEFT JOIN tot tt ON tt.account_id = t.account_id
GROUP BY 1, 2
ORDER BY 1, bool_and(NOT v.visivel), cards_preenchidos DESC, 2;


-- ============================================================================================================
-- PARTE I. IMPORTACOES E PLANILHAS (F0: o vocabulario real das planilhas)
-- ============================================================================================================
-- fluxo (campaign_imports.options ->> 'flow'): audience = Publicos (#992), contacts = Importar contatos (#1006),
--   campanha_antiga = sem flow (app/models/campaign_import.rb:64,67). Valor fora da lista sai como (outro).
-- Onde ficam os titulos: schema_resolution -> 'columns'[*] ->> 'header' = todos os titulos lidos
--   (app/services/campaign_imports/spreadsheet_reader.rb:182-195; so fluxos audience e contacts);
--   schema_resolution -> 'targets' -> {alvo} ->> 'header' = titulo que virou nome/telefone/e-mail/empresa (idem :166);
--   campaign_imports.extra_columns = titulos das colunas extras (app/services/campaign_imports/audience_validator.rb:155).
--   O fluxo antigo nao grava titulo. E-mail: email_campaign_imports guarda so indices; os titulos normalizados das extras
--   ficam como CHAVES de email_campaign_recipients.custom_data (app/services/email_campaigns/recipient_importer.rb:112).
--   O campo example_masked de cada coluna nunca e lido.

\echo '== 29. Importacoes de planilha (campaign_imports) por conta e fluxo (+ subtotal da conta e TOTAL) =='
WITH ci AS (
  SELECT x.account_id, x.status, x.total_rows, x.valid_rows, x.new_contacts_count, x.existing_contacts_updated_count,
         x.companies_created_count, x.company_contacts_linked_count, x.extra_columns, x.created_at,
         CASE WHEN x.options ->> 'flow' IS NULL THEN 'campanha_antiga'
              WHEN x.options ->> 'flow' IN ('audience', 'contacts') THEN x.options ->> 'flow'
              ELSE '(outro)' END AS fluxo
  FROM campaign_imports x
  JOIN :ativas a ON a.account_id = x.account_id
)
SELECT CASE WHEN grouping(ci.account_id) = 1 THEN 'TOTAL' ELSE ci.account_id::text END AS account_id,
       CASE WHEN grouping(ci.fluxo) = 1 THEN '(todos)' ELSE ci.fluxo END AS fluxo,
       count(*) AS importacoes,
       count(*) FILTER (WHERE ci.status IN (7, 8)) AS concluidas,
       count(*) FILTER (WHERE ci.status = 15) AS esperando_escolha_coluna,
       count(*) FILTER (WHERE ci.status IN (2, 9)) AS falharam,
       sum(ci.total_rows) AS linhas_total,
       sum(ci.valid_rows) AS linhas_validas,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY ci.total_rows) AS linhas_p50,
       max(ci.total_rows) AS linhas_max,
       sum(ci.new_contacts_count) AS contatos_novos,
       sum(ci.existing_contacts_updated_count) AS contatos_atualizados,
       sum(ci.companies_created_count) AS empresas_criadas,
       sum(ci.company_contacts_linked_count) AS contatos_ligados_empresa,
       count(*) FILTER (WHERE jsonb_array_length(CASE WHEN jsonb_typeof(ci.extra_columns) = 'array'
                                                      THEN ci.extra_columns ELSE '[]'::jsonb END) > 0) AS com_colunas_extras,
       to_char(min(ci.created_at), 'YYYY-MM') AS primeira,
       to_char(max(ci.created_at), 'YYYY-MM') AS ultima
FROM ci
GROUP BY ROLLUP (ci.account_id, ci.fluxo)
ORDER BY grouping(ci.account_id), ci.account_id, grouping(ci.fluxo), ci.fluxo;

\echo '== 30. Importacoes por mes e fluxo =='
SELECT to_char(date_trunc('month', ci.created_at), 'YYYY-MM') AS mes,
       CASE WHEN ci.options ->> 'flow' IS NULL THEN 'campanha_antiga'
            WHEN ci.options ->> 'flow' IN ('audience', 'contacts') THEN ci.options ->> 'flow'
            ELSE '(outro)' END AS fluxo,
       count(*) AS importacoes,
       sum(ci.total_rows) AS linhas,
       count(DISTINCT ci.account_id) AS contas
FROM campaign_imports ci
JOIN :ativas a ON a.account_id = ci.account_id
GROUP BY 1, 2
ORDER BY 1, 2;

\echo '== 31. Como as colunas foram decididas (schema_resolution ->> method) e largura das planilhas =='
-- metodo (spreadsheet_reader.rb:5-9,196-201): jev = o Jev achou as colunas com confianca e a importacao seguiu sozinha;
-- deterministic = apelidos conhecidos so pre-preencheram e a pessoa confirmou; manual = a pessoa escolheu as colunas.
-- sem_linha_de_titulo = header_row 0 (planilha sem cabecalho; header_locator.rb:12).
SELECT CASE WHEN ci.options ->> 'flow' IS NULL THEN 'campanha_antiga'
            WHEN ci.options ->> 'flow' IN ('audience', 'contacts') THEN ci.options ->> 'flow'
            ELSE '(outro)' END AS fluxo,
       CASE WHEN ci.schema_resolution ->> 'method' IS NULL THEN '(sem)'
            WHEN ci.schema_resolution ->> 'method' IN ('jev', 'deterministic', 'manual') THEN ci.schema_resolution ->> 'method'
            ELSE '(outro)' END AS metodo,
       count(*) AS importacoes,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY coalesce(jsonb_array_length(
         CASE WHEN jsonb_typeof(ci.schema_resolution -> 'columns') = 'array' THEN ci.schema_resolution -> 'columns' END), 0))
         AS colunas_p50,
       max(coalesce(jsonb_array_length(
         CASE WHEN jsonb_typeof(ci.schema_resolution -> 'columns') = 'array' THEN ci.schema_resolution -> 'columns' END), 0))
         AS colunas_max,
       count(*) FILTER (WHERE (ci.schema_resolution ->> 'header_row') = '0') AS sem_linha_de_titulo
FROM campaign_imports ci
JOIN :ativas a ON a.account_id = ci.account_id
GROUP BY 1, 2
ORDER BY 1, 2;

\echo '== 32. Titulos de coluna das planilhas reais, top 150 (REGRA DO TEXTO) =='
-- Dicionario de sinonimos da Base de clientes com dado real: o que e pessoa, empresa e negocio.
-- Versao 2 (auditoria da Orquestracao): saiu o md5 do cabecalho, que deixava passar a mesma planilha reimportada com uma
-- coluna a mais. Agora:
--   * so entra titulo de planilha "boa": pelo menos 2 titulos preenchidos e nenhum com '@' ou 6+ digitos (no texto
--     inteiro). Cabecalho com '@'/telefone, ou com um titulo so (ex.: "joao luca campos" e duas colunas vazias, achado no
--     banco de teste), provavelmente e uma linha de dado; nenhum titulo dela entra aqui (sao contados no bloco 35);
--   * contas = contas ativas em que o titulo aparece em planilha boa. Cada conta conta uma vez, por mais que a planilha
--     tenha sido importada nela (com ou sem coluna a mais); sai so o titulo de :min_contas ou mais contas.
WITH imp AS (
  SELECT ci.id AS import_id, ci.account_id,
         CASE WHEN ci.options ->> 'flow' IS NULL THEN 'campanha_antiga'
              WHEN ci.options ->> 'flow' IN ('audience', 'contacts') THEN ci.options ->> 'flow'
              ELSE '(outro)' END AS fluxo,
         CASE WHEN jsonb_typeof(ci.schema_resolution -> 'columns') = 'array'
              THEN ci.schema_resolution -> 'columns' ELSE '[]'::jsonb END AS colunas
  FROM campaign_imports ci
  JOIN :ativas a ON a.account_id = ci.account_id
),
cab AS (
  SELECT i.import_id, i.account_id, i.fluxo,
         lower(btrim(c.col ->> 'header')) AS inteiro,
         left(lower(btrim(c.col ->> 'header')), 60) AS titulo
  FROM imp i
  CROSS JOIN LATERAL jsonb_array_elements(i.colunas) AS c(col)
  WHERE btrim(coalesce(c.col ->> 'header', '')) <> ''
),
boas AS (
  SELECT c.import_id
  FROM cab c
  GROUP BY c.import_id
  HAVING count(*) >= 2
     AND NOT bool_or(position('@' IN c.inteiro) > 0
                     OR length(c.inteiro) - length(translate(c.inteiro, '0123456789', '')) >= 6)
)
SELECT c.titulo,
       count(DISTINCT c.import_id) AS importacoes,
       count(DISTINCT c.account_id) AS contas,
       string_agg(DISTINCT c.fluxo, ',') AS fluxos
FROM cab c
WHERE EXISTS (SELECT 1 FROM boas b WHERE b.import_id = c.import_id)
GROUP BY c.titulo
HAVING count(DISTINCT c.account_id) >= :min_contas
ORDER BY importacoes DESC, contas DESC, 1
LIMIT 150;

\echo '== 33. Titulo que o leitor ligou a nome / telefone / e-mail / empresa (schema_resolution -> targets; REGRA DO TEXTO) =='
-- alvo = chave do sistema (TARGETS = name, phone, email, company; spreadsheet_reader.rb:12); outro valor sai como (outro).
-- Mesma regra do bloco 32: so planilha boa, e sai so o titulo de :min_contas ou mais contas.
WITH imp AS (
  SELECT ci.id AS import_id, ci.account_id,
         CASE WHEN jsonb_typeof(ci.schema_resolution -> 'columns') = 'array'
              THEN ci.schema_resolution -> 'columns' ELSE '[]'::jsonb END AS colunas,
         CASE WHEN jsonb_typeof(ci.schema_resolution -> 'targets') = 'object'
              THEN ci.schema_resolution -> 'targets' ELSE '{}'::jsonb END AS alvos
  FROM campaign_imports ci
  JOIN :ativas a ON a.account_id = ci.account_id
),
cab AS (
  SELECT i.import_id, lower(btrim(c.col ->> 'header')) AS inteiro
  FROM imp i
  CROSS JOIN LATERAL jsonb_array_elements(i.colunas) AS c(col)
  WHERE btrim(coalesce(c.col ->> 'header', '')) <> ''
),
boas AS (
  SELECT c.import_id
  FROM cab c
  GROUP BY c.import_id
  HAVING count(*) >= 2
     AND NOT bool_or(position('@' IN c.inteiro) > 0
                     OR length(c.inteiro) - length(translate(c.inteiro, '0123456789', '')) >= 6)
),
alvo AS (
  SELECT i.import_id, i.account_id,
         CASE WHEN t.alvo IN ('name', 'phone', 'email', 'company') THEN t.alvo ELSE '(outro)' END AS alvo,
         lower(btrim(t.entry ->> 'header')) AS inteiro,
         left(lower(btrim(t.entry ->> 'header')), 60) AS titulo
  FROM imp i
  CROSS JOIN LATERAL jsonb_each(i.alvos) AS t(alvo, entry)
  WHERE jsonb_typeof(t.entry) = 'object'
    AND btrim(coalesce(t.entry ->> 'header', '')) <> ''
)
SELECT x.alvo,
       x.titulo,
       count(DISTINCT x.import_id) AS importacoes,
       count(DISTINCT x.account_id) AS contas
FROM alvo x
WHERE EXISTS (SELECT 1 FROM boas b WHERE b.import_id = x.import_id)
  AND position('@' IN x.inteiro) = 0
  AND length(x.inteiro) - length(translate(x.inteiro, '0123456789', '')) < 6
GROUP BY 1, 2
HAVING count(DISTINCT x.account_id) >= :min_contas
ORDER BY 1, importacoes DESC, 2
LIMIT 120;

\echo '== 34. Titulos que viraram COLUNA EXTRA (campaign_imports.extra_columns), top 100 (REGRA DO TEXTO) =='
-- O que sobra fora de nome/telefone/e-mail/empresa: candidatos a campo de pessoa, de empresa ou de card.
-- Mesma regra do bloco 32, com um cuidado a mais: a planilha so e boa se nenhum titulo extra tem '@' ou 6+ digitos.
-- Coluna sem titulo aparece como column_N (spreadsheet_reader.rb:209).
WITH imp AS (
  SELECT ci.id AS import_id, ci.account_id,
         CASE WHEN jsonb_typeof(ci.schema_resolution -> 'columns') = 'array'
              THEN ci.schema_resolution -> 'columns' ELSE '[]'::jsonb END AS colunas,
         CASE WHEN jsonb_typeof(ci.extra_columns) = 'array' THEN ci.extra_columns ELSE '[]'::jsonb END AS extras
  FROM campaign_imports ci
  JOIN :ativas a ON a.account_id = ci.account_id
),
cab AS (
  SELECT i.import_id, lower(btrim(c.col ->> 'header')) AS inteiro
  FROM imp i
  CROSS JOIN LATERAL jsonb_array_elements(i.colunas) AS c(col)
  WHERE btrim(coalesce(c.col ->> 'header', '')) <> ''
),
ext AS (
  SELECT i.import_id, i.account_id, lower(btrim(x.titulo)) AS inteiro, left(lower(btrim(x.titulo)), 60) AS titulo
  FROM imp i
  CROSS JOIN LATERAL jsonb_array_elements_text(i.extras) AS x(titulo)
  WHERE btrim(x.titulo) <> ''
),
boas AS (
  SELECT c.import_id
  FROM cab c
  GROUP BY c.import_id
  HAVING count(*) >= 2
     AND NOT bool_or(position('@' IN c.inteiro) > 0
                     OR length(c.inteiro) - length(translate(c.inteiro, '0123456789', '')) >= 6)
  EXCEPT
  SELECT e.import_id
  FROM ext e
  WHERE position('@' IN e.inteiro) > 0
     OR length(e.inteiro) - length(translate(e.inteiro, '0123456789', '')) >= 6
)
SELECT e.titulo,
       count(DISTINCT e.import_id) AS importacoes,
       count(DISTINCT e.account_id) AS contas
FROM ext e
WHERE EXISTS (SELECT 1 FROM boas b WHERE b.import_id = e.import_id)
GROUP BY 1
HAVING count(DISTINCT e.account_id) >= :min_contas
ORDER BY importacoes DESC, contas DESC, 1
LIMIT 100;

\echo '== 35. Titulos de coluna por conta: quantos ha e quantos ficam ocultos pela REGRA DO TEXTO (so contagem; + TOTAL) =='
-- planilhas_suspeitas = importacoes que nao sao "boas" (bloco 32): menos de 2 titulos preenchidos ou algum titulo com '@'
-- ou 6+ digitos (cabecalho que provavelmente e linha de dado).
-- titulos_ocultos = titulos que nao saem no bloco 32, por motivo:
--   oculto_so_em_planilha_suspeita = nesta conta, o titulo so aparece em planilha suspeita;
--   oculto_de_uma_conta / oculto_de_poucas_contas = aparece em planilha boa de 1 conta / de menos de :min_contas.
-- Mede quanto do vocabulario e proprio de cada cliente sem mostrar o texto. Na linha TOTAL, contagens de titulos
-- distintos no conjunto das contas (um titulo pode cair em mais de um motivo).
WITH imp AS (
  SELECT ci.id AS import_id, ci.account_id,
         CASE WHEN jsonb_typeof(ci.schema_resolution -> 'columns') = 'array'
              THEN ci.schema_resolution -> 'columns' ELSE '[]'::jsonb END AS colunas
  FROM campaign_imports ci
  JOIN :ativas a ON a.account_id = ci.account_id
),
cab AS (
  SELECT i.import_id, i.account_id,
         lower(btrim(c.col ->> 'header')) AS inteiro,
         left(lower(btrim(c.col ->> 'header')), 60) AS titulo
  FROM imp i
  CROSS JOIN LATERAL jsonb_array_elements(i.colunas) AS c(col)
  WHERE btrim(coalesce(c.col ->> 'header', '')) <> ''
),
boas AS (
  SELECT c.import_id
  FROM cab c
  GROUP BY c.import_id
  HAVING count(*) >= 2
     AND NOT bool_or(position('@' IN c.inteiro) > 0
                     OR length(c.inteiro) - length(translate(c.inteiro, '0123456789', '')) >= 6)
),
marca AS (
  SELECT c.account_id, c.import_id, c.titulo, b.import_id IS NULL AS suspeita
  FROM cab c
  LEFT JOIN boas b ON b.import_id = c.import_id
),
por_titulo AS (
  SELECT m.titulo, count(DISTINCT m.account_id) AS contas
  FROM marca m
  WHERE NOT m.suspeita
  GROUP BY m.titulo
),
conta_titulo AS (
  SELECT m.account_id, m.titulo, bool_and(m.suspeita) AS so_em_suspeita
  FROM marca m
  GROUP BY m.account_id, m.titulo
),
marcado AS (
  SELECT m.account_id, m.import_id, m.titulo, m.suspeita, ct.so_em_suspeita,
         coalesce(p.contas, 0) AS contas,
         coalesce(p.contas, 0) >= :min_contas AS visivel
  FROM marca m
  JOIN conta_titulo ct ON ct.account_id = m.account_id AND ct.titulo = m.titulo
  LEFT JOIN por_titulo p ON p.titulo = m.titulo
)
SELECT coalesce(m.account_id::text, 'TOTAL') AS account_id,
       count(DISTINCT m.import_id) AS importacoes_com_titulo,
       count(DISTINCT m.import_id) FILTER (WHERE m.suspeita) AS planilhas_suspeitas,
       count(DISTINCT m.titulo) AS titulos_distintos,
       count(DISTINCT m.titulo) FILTER (WHERE m.visivel) AS titulos_visiveis,
       count(DISTINCT m.titulo) FILTER (WHERE NOT m.visivel) AS titulos_ocultos,
       count(DISTINCT m.titulo) FILTER (WHERE NOT m.visivel AND m.so_em_suspeita) AS oculto_so_em_planilha_suspeita,
       count(DISTINCT m.titulo) FILTER (WHERE NOT m.visivel AND NOT m.so_em_suspeita AND m.contas = 1) AS oculto_de_uma_conta,
       count(DISTINCT m.titulo) FILTER (WHERE NOT m.visivel AND NOT m.so_em_suspeita AND m.contas > 1) AS oculto_de_poucas_contas
FROM marcado m
GROUP BY ROLLUP (m.account_id)
ORDER BY m.account_id NULLS LAST;

\echo '== 36. Importacoes de e-mail (email_campaign_imports) por conta, status e metodo (+ subtotais e TOTAL) =='
-- status: 0 fila, 1 processando, 2 concluida, 3 falhou. Titulos nao ficam aqui (so indices): ver bloco 37.
WITH ei AS (
  SELECT ec.account_id, x.status, x.created_at,
         CASE WHEN x.schema_resolution ->> 'method' IS NULL THEN '(sem)'
              WHEN x.schema_resolution ->> 'method' IN ('jev', 'deterministic', 'manual') THEN x.schema_resolution ->> 'method'
              ELSE '(outro)' END AS metodo
  FROM email_campaign_imports x
  JOIN email_campaigns ec ON ec.id = x.email_campaign_id
  JOIN :ativas a ON a.account_id = ec.account_id
)
SELECT CASE WHEN grouping(ei.account_id) = 1 THEN 'TOTAL' ELSE ei.account_id::text END AS account_id,
       CASE WHEN grouping(ei.status) = 1 THEN '(todos)' ELSE ei.status::text END AS status,
       CASE WHEN grouping(ei.metodo) = 1 THEN '(todos)' ELSE ei.metodo END AS metodo,
       count(*) AS importacoes,
       to_char(min(ei.created_at), 'YYYY-MM') AS primeira,
       to_char(max(ei.created_at), 'YYYY-MM') AS ultima
FROM ei
GROUP BY ROLLUP (ei.account_id, ei.status, ei.metodo)
ORDER BY grouping(ei.account_id), ei.account_id, grouping(ei.status), ei.status, grouping(ei.metodo), ei.metodo;

\echo '== 37. Titulos normalizados das colunas extras de e-mail (chaves de custom_data, 1 destinatario por campanha), top 80 (REGRA DO TEXTO) =='
-- So a CHAVE de custom_data e lida; o valor nunca. As chaves vem das colunas extras da planilha e sao as mesmas em todo
-- destinatario importado dela (app/services/email_campaigns/recipient_importer.rb:112-113). Por isso basta 1 destinatario
-- qualquer por campanha: sem ORDER BY, o LIMIT 1 usa um indice que comeca por email_campaign_id (ex.:
-- index_email_campaign_recipients_on_email_campaign_id) e para na primeira linha. O indice (email_campaign_id, id),
-- idx_recipients_preflight_unchecked, e parcial; a versao 1 ordenava por id e lia a campanha inteira.
-- Se esse destinatario nao tem colunas extras (cadastrado a mao), a campanha nao entra.
-- Versao 2: saiu o md5. So entra campanha "boa": pelo menos 2 chaves e nenhuma com '@' ou 6+ digitos (a mesma regra da
-- planilha boa; campanha com uma coluna extra so fica de fora). Conta-se a conta, nao a campanha, e sai so a chave de
-- :min_contas ou mais contas.
WITH rec AS (
  SELECT ec.id AS campanha_id, ec.account_id, r.custom_data
  FROM email_campaigns ec
  JOIN :ativas a ON a.account_id = ec.account_id
  CROSS JOIN LATERAL (
    SELECT x.custom_data
    FROM email_campaign_recipients x
    WHERE x.email_campaign_id = ec.id
    LIMIT 1
  ) r
  WHERE jsonb_typeof(r.custom_data) = 'object' AND r.custom_data <> '{}'::jsonb
),
k AS (
  SELECT rec.campanha_id, rec.account_id,
         lower(btrim(o.chave)) AS inteiro,
         left(lower(btrim(o.chave)), 60) AS chave
  FROM rec
  CROSS JOIN LATERAL jsonb_object_keys(rec.custom_data) AS o(chave)
),
boas AS (
  SELECT k.campanha_id
  FROM k
  WHERE k.inteiro <> ''
  GROUP BY k.campanha_id
  HAVING count(*) >= 2
     AND NOT bool_or(position('@' IN k.inteiro) > 0
                     OR length(k.inteiro) - length(translate(k.inteiro, '0123456789', '')) >= 6)
)
SELECT k.chave AS titulo_normalizado,
       count(DISTINCT k.campanha_id) AS campanhas,
       count(DISTINCT k.account_id) AS contas
FROM k
WHERE EXISTS (SELECT 1 FROM boas b WHERE b.campanha_id = k.campanha_id)
  AND k.chave <> ''
GROUP BY 1
HAVING count(DISTINCT k.account_id) >= :min_contas
ORDER BY campanhas DESC, contas DESC, 1
LIMIT 80;

\echo '== FIM da parte 3: todos os blocos rodaram. A transacao e desfeita a seguir (ROLLBACK). =='
ROLLBACK;
