-- 1-pessoas-canais.sql
-- Pesquisa #1240 (Relacionamentos e Base de clientes). Consulta de producao, versao 2, parte 1 de 5.
-- Universo e flags, pessoa e telefone, contato x cliente, opt-out, entrada de contatos e canais (partes A a F).
-- Blocos 1 a 15 (15 no total). A numeracao dos blocos e a mesma nas 5 partes e no LEIA-ME.md.
--
-- QUEM RODA: outra sessao, por psql, nas duas instalacoes (Hub2You e Autonom.ia), com usuario de leitura, fora de deploy,
-- depois de conferir no pg_stat_activity que nao ha DDL em andamento. Uma parte por vez, em qualquer ordem.
--   psql "<conexao>" -X -v ON_ERROR_STOP=1 -f 1-pessoas-canais.sql > saida-1-<instalacao>.txt 2>&1
-- Precisa ser psql: usa \echo, \set e a variavel :ativas. Nao roda em cliente grafico.
--
-- GARANTIAS (as mesmas nas 5 partes; detalhes e testes no LEIA-ME.md)
--   * Somente leitura: BEGIN TRANSACTION READ ONLY ... ROLLBACK, uma transacao por parte. Nenhum INSERT/UPDATE/DELETE/
--     CREATE, nem tabela temporaria.
--   * Carga: cada bloco tem no maximo 60 s (statement_timeout) e espera no maximo 2 s por trava (lock_timeout). Teto desta
--     parte: 15 x 60 s. Se um bloco passar do limite, o psql para ali (ON_ERROR_STOP) e a transacao e desfeita; o que ja
--     saiu vale. A trava de leitura (ACCESS SHARE) dura so ate o ROLLBACK desta parte.
--   * Somente totais: nenhum SELECT devolve nome, telefone, e-mail, identifier, conteudo de mensagem, titulo/descricao/motivo
--     de card, nome de empresa, funil ou etapa, nem VALOR de campo (custom_attributes / additional_attributes / custom_data).
--     Saem: account_id, contagens, percentuais, percentis, meses (AAAA-MM), codigos do sistema (status, channel_type, fluxo e
--     metodo de importacao, opt_out_source e origem de card comparados com a lista do codigo) e textos que passam na
--     REGRA DO TEXTO. Dominio de e-mail, etiqueta e origem de card digitada nunca saem como texto: so contagem (o bloco 18
--     so imprime dominios escritos na propria consulta, nunca um lido do banco).
--   * REGRA DO TEXTO. Vale para chave de campo, nome exibido de campo, titulo de coluna de planilha e chave de JSON. O texto
--     so sai quando (1) nao tem '@', (2) tem menos de 6 digitos e (3) aparece em pelo menos :min_contas contas ativas (3,
--     definido abaixo). Nos blocos de campo (21, 28, 48, 49, 50, 51) so conta a conta em que a chave tem VALOR, nao a que
--     so tem a definicao. Titulo de planilha (blocos 32 a 35 e 37) tem ainda a condicao (4): so conta planilha "boa",
--     com pelo menos 2 titulos preenchidos e nenhum com '@' ou 6+ digitos. Fora disso o cabecalho provavelmente e uma
--     linha de dado, e NENHUM titulo dela entra na lista nem na contagem de contas (na chave de e-mail, bloco 37, vale so
--     a parte do '@' e dos digitos). Em (3) conta-se a CONTA, nao a planilha: a mesma planilha importada de novo na
--     mesma conta, com ou sem coluna a mais, nao soma. O teste e feito no texto inteiro; o texto sai em minusculas, sem
--     espaco nas pontas, cortado em 60 caracteres. O que nao passa vira '(oculto)' e entra so na contagem (nas listas de
--     titulos mais comuns, fica de fora e e contado no bloco 35). Digitos contados com translate(), sem regex.
--     Por que (3): o "Importar contatos" (#1006) cria campo de contato com o titulo da coluna como nome
--     (app/services/contact_imports/custom_attributes.rb:47-51); planilha cujo cabecalho foi lido errado pode ter criado
--     campo com nome de pessoa. Texto de uma ou duas contas nunca sai.
--
-- REFERENCIAS (worktree 1240-pesquisa-relacionamentos, igual a producao)
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
-- PARTE A. UNIVERSO E FLAGS
-- ============================================================================================================

\echo '== 1. Contas por status (0 = ativa, 1 = suspensa) =='
SELECT status, count(*) AS contas
FROM accounts
GROUP BY status
ORDER BY status;

\echo '== 2. Flags por conta ativa (t = ligada) e mes de criacao da conta =='
SELECT a.id AS account_id,
       (a.feature_flags & (1::bigint << 14)) <> 0 AS custom_attributes,
       (a.feature_flags & (1::bigint << 23)) <> 0 AS crm,
       (a.feature_flags & (1::bigint << 43)) <> 0 AS crm_integration,
       (a.feature_flags & (1::bigint << 49)) <> 0 AS crm_v2,
       (a.feature_flags & (1::bigint << 57)) <> 0 AS companies,
       (a.feature_flags_ext_1 & (1::bigint << 0))  <> 0 AS whatsapp_manual_transfer,
       (a.feature_flags_ext_1 & (1::bigint << 1))  <> 0 AS data_import,
       (a.feature_flags_ext_1 & (1::bigint << 2))  <> 0 AS api_and_webhooks,
       (a.feature_flags_ext_1 & (1::bigint << 3))  <> 0 AS whatsapp_reconfigure,
       (a.feature_flags_ext_1 & (1::bigint << 4))  <> 0 AS wa_embedded_signup_inbox,
       (a.feature_flags_ext_1 & (1::bigint << 5))  <> 0 AS delayed_automations,
       (a.feature_flags_ext_1 & (1::bigint << 6))  <> 0 AS audit_log_ip_address,
       (a.feature_flags_ext_1 & (1::bigint << 7))  <> 0 AS relationships_attributes,
       (a.feature_flags_ext_1 & (1::bigint << 8))  <> 0 AS relationships_company_media,
       (a.feature_flags_ext_1 & (1::bigint << 9))  <> 0 AS relationships_navigation,
       (a.feature_flags_ext_1 & (1::bigint << 10)) <> 0 AS instagram_assisted_onboarding,
       (a.feature_flags_ext_1 & (1::bigint << 11)) <> 0 AS meta_ads_hub,
       (a.feature_flags_ext_1 & (1::bigint << 12)) <> 0 AS email_template_import,
       (a.feature_flags_ext_1 & (1::bigint << 13)) <> 0 AS autonomia_agents_journey,
       (a.feature_flags_ext_1 & (1::bigint << 14)) <> 0 AS crm_booking_v2,
       (a.feature_flags_ext_1 & (1::bigint << 15)) <> 0 AS customer_base,
       to_char(a.created_at, 'YYYY-MM') AS conta_criada_mes
FROM accounts a
WHERE a.status = 0
ORDER BY a.id;

\echo '== 3. Flags: quantas contas ativas tem cada flag principal ligada =='
SELECT count(*) AS contas_ativas,
       count(*) FILTER (WHERE (feature_flags & (1::bigint << 14)) <> 0) AS custom_attributes,
       count(*) FILTER (WHERE (feature_flags & (1::bigint << 23)) <> 0) AS crm,
       count(*) FILTER (WHERE (feature_flags & (1::bigint << 49)) <> 0) AS crm_v2,
       count(*) FILTER (WHERE (feature_flags & (1::bigint << 57)) <> 0) AS companies,
       count(*) FILTER (WHERE (feature_flags_ext_1 & (1::bigint << 1))  <> 0) AS data_import,
       count(*) FILTER (WHERE (feature_flags_ext_1 & (1::bigint << 7))  <> 0) AS relationships_attributes,
       count(*) FILTER (WHERE (feature_flags_ext_1 & (1::bigint << 8))  <> 0) AS relationships_company_media,
       count(*) FILTER (WHERE (feature_flags_ext_1 & (1::bigint << 9))  <> 0) AS relationships_navigation,
       count(*) FILTER (WHERE (feature_flags_ext_1 & (1::bigint << 14)) <> 0) AS crm_booking_v2,
       count(*) FILTER (WHERE (feature_flags_ext_1 & (1::bigint << 15)) <> 0) AS customer_base
FROM accounts
WHERE status = 0;


-- ============================================================================================================
-- PARTE B. PESSOA: TAMANHO, IDENTIFICACAO E TELEFONE
-- ============================================================================================================

\echo '== 4. Base de contatos por conta: tamanho e por onde a pessoa e identificada (+ TOTAL) =='
-- com_telefone / com_email / com_identifier = campo nao vazio. sem_nenhum_contato = sem telefone, e-mail e identifier.
-- Formato do telefone e duplicados: bloco 6. contact_type e customer_since: bloco 7. Vinculo com empresa: bloco 16.
WITH c AS (
  SELECT ct.account_id,
         coalesce(ct.phone_number, '') <> '' AS tem_tel,
         coalesce(ct.email, '') <> '' AS tem_email,
         coalesce(ct.identifier, '') <> '' AS tem_identifier,
         ct.blocked
  FROM contacts ct
  JOIN :ativas a ON a.account_id = ct.account_id
)
SELECT coalesce(c.account_id::text, 'TOTAL') AS account_id,
       count(*) AS contatos,
       count(*) FILTER (WHERE c.tem_tel) AS com_telefone,
       count(*) FILTER (WHERE c.tem_email) AS com_email,
       count(*) FILTER (WHERE c.tem_tel AND c.tem_email) AS tel_e_email,
       count(*) FILTER (WHERE NOT c.tem_tel AND NOT c.tem_email) AS sem_tel_nem_email,
       count(*) FILTER (WHERE NOT c.tem_tel AND NOT c.tem_email AND NOT c.tem_identifier) AS sem_nenhum_contato,
       count(*) FILTER (WHERE c.tem_identifier) AS com_identifier,
       count(*) FILTER (WHERE c.blocked) AS bloqueados,
       round(100.0 * count(*) FILTER (WHERE c.tem_tel) / nullif(count(*), 0), 1) AS pct_tel,
       round(100.0 * count(*) FILTER (WHERE c.tem_email) / nullif(count(*), 0), 1) AS pct_email
FROM c
GROUP BY ROLLUP (c.account_id)
ORDER BY c.account_id IS NULL, count(*) DESC, c.account_id;

\echo '== 5. Contatos por conta ativa: percentis (conta sem contato entra como 0) =='
WITH por_conta AS (
  SELECT a.account_id, count(ct.id) AS n
  FROM :ativas a
  LEFT JOIN contacts ct ON ct.account_id = a.account_id
  GROUP BY a.account_id
)
SELECT count(*) AS contas_ativas,
       count(*) FILTER (WHERE p.n = 0) AS contas_sem_contato,
       percentile_disc(0.50) WITHIN GROUP (ORDER BY p.n) AS p50,
       percentile_disc(0.90) WITHIN GROUP (ORDER BY p.n) AS p90,
       percentile_disc(0.99) WITHIN GROUP (ORDER BY p.n) AS p99,
       max(p.n) AS maximo,
       sum(p.n) AS total
FROM por_conta p;

\echo '== 6. Telefone por conta: formato e duplicados provaveis (+ TOTAL; nenhum numero sai) =='
-- d = phone_number sem '+', espaco, '-', '(', ')' e '.' (translate, sem regex). As cinco classes somam com_telefone:
--   br_celular = 55 + DDD + 9 + 8 digitos (13 digitos, 9 na 5a posicao);
--   br_12_digitos = 55 + DDD + 8 digitos (fixo, ou celular gravado sem o nono digito);
--   br_outro = comeca com 55 e tem outro formato;  nao_br = nao comeca com 55;  formato_estranho = sobra algo que nao e digito.
-- Duplicado provavel = dois contatos da MESMA conta com o mesmo numero. "Ignorando o nono digito": br_celular perde o 9 da
-- 5a posicao e passa a casar com a versao de 12 digitos. Pares num grupo de n contatos = n*(n-1)/2.
-- O modelo exige formato internacional (app/models/contact.rb:61-63), mas importacao pode gravar sem passar pela validacao.
WITH tel AS (
  SELECT ct.account_id, translate(ct.phone_number, '+ -().', '') AS d
  FROM contacts ct
  JOIN :ativas a ON a.account_id = ct.account_id
  WHERE coalesce(ct.phone_number, '') <> ''
),
cls AS (
  SELECT t.account_id, t.d,
         CASE
           WHEN t.d = '' OR translate(t.d, '0123456789', '') <> '' THEN 'estranho'
           WHEN left(t.d, 2) <> '55' THEN 'nao_br'
           WHEN length(t.d) = 13 AND substr(t.d, 5, 1) = '9' THEN 'br_celular'
           WHEN length(t.d) = 12 THEN 'br_12'
           ELSE 'br_outro'
         END AS classe
  FROM tel t
),
chaves AS (
  SELECT k.account_id, k.d,
         CASE WHEN k.classe = 'br_celular' THEN left(k.d, 4) || substr(k.d, 6) ELSE k.d END AS chave_sem9
  FROM cls k
  WHERE k.classe <> 'estranho'
),
exato AS (
  SELECT g.account_id, sum(g.n * (g.n - 1) / 2) AS pares
  FROM (SELECT account_id, d, count(*) AS n FROM chaves GROUP BY account_id, d) g
  GROUP BY g.account_id
),
sem9 AS (
  SELECT g.account_id, sum(g.n * (g.n - 1) / 2) AS pares,
         coalesce(sum(g.n) FILTER (WHERE g.n > 1), 0) AS contatos_em_algum_par
  FROM (SELECT account_id, chave_sem9, count(*) AS n FROM chaves GROUP BY account_id, chave_sem9) g
  GROUP BY g.account_id
),
qual AS (
  SELECT k.account_id,
         count(*) AS com_telefone,
         count(*) FILTER (WHERE k.classe = 'br_celular') AS br_celular,
         count(*) FILTER (WHERE k.classe = 'br_12') AS br_12_digitos,
         count(*) FILTER (WHERE k.classe = 'br_outro') AS br_outro,
         count(*) FILTER (WHERE k.classe = 'nao_br') AS nao_br,
         count(*) FILTER (WHERE k.classe = 'estranho') AS formato_estranho
  FROM cls k
  GROUP BY k.account_id
)
SELECT coalesce(q.account_id::text, 'TOTAL') AS account_id,
       sum(q.com_telefone) AS com_telefone,
       sum(q.br_celular) AS br_celular,
       sum(q.br_12_digitos) AS br_12_digitos,
       sum(q.br_outro) AS br_outro,
       sum(q.nao_br) AS nao_br,
       sum(q.formato_estranho) AS formato_estranho,
       coalesce(sum(e.pares), 0) AS pares_numero_identico,
       coalesce(sum(s.pares), 0) AS pares_ignorando_nono_digito,
       coalesce(sum(s.pares), 0) - coalesce(sum(e.pares), 0) AS pares_so_pelo_nono_digito,
       coalesce(sum(s.contatos_em_algum_par), 0) AS contatos_em_algum_par
FROM qual q
LEFT JOIN exato e ON e.account_id = q.account_id
LEFT JOIN sem9 s ON s.account_id = q.account_id
GROUP BY ROLLUP (q.account_id)
ORDER BY q.account_id NULLS LAST;


-- ============================================================================================================
-- PARTE C. CONTATO X CLIENTE (contact_type, customer_since e card ganho)
-- ============================================================================================================

\echo '== 7. Contato x cliente por conta: contact_type, customer_since e cards (+ TOTAL) =='
-- customer = customer_com_ganho + customer_card_sem_ganho + customer_sem_card. "Ganho" = card com status won (1).
-- ganho_sem_ser_customer = contato com card ganho cujo contact_type nao e customer.
WITH cards_por_contato AS (
  SELECT c.account_id, c.contact_id, bool_or(c.status = 1) AS tem_ganho, count(*) AS n
  FROM crm_cards c
  JOIN :ativas a ON a.account_id = c.account_id
  WHERE c.contact_id IS NOT NULL
  GROUP BY c.account_id, c.contact_id
)
SELECT coalesce(ct.account_id::text, 'TOTAL') AS account_id,
       count(*) AS contatos,
       count(*) FILTER (WHERE ct.contact_type = 0) AS visitor,
       count(*) FILTER (WHERE ct.contact_type = 1) AS lead,
       count(*) FILTER (WHERE ct.contact_type = 2) AS customer,
       count(*) FILTER (WHERE ct.contact_type IS NULL OR ct.contact_type NOT IN (0, 1, 2)) AS outro_tipo,
       count(*) FILTER (WHERE ct.customer_since IS NOT NULL) AS com_customer_since,
       count(*) FILTER (WHERE ct.contact_type = 2 AND ct.customer_since IS NULL) AS customer_sem_since,
       count(*) FILTER (WHERE ct.contact_type IS DISTINCT FROM 2 AND ct.customer_since IS NOT NULL) AS since_sem_ser_customer,
       count(k.contact_id) AS com_algum_card,
       count(k.contact_id) FILTER (WHERE k.n > 1) AS com_2_ou_mais_cards,
       count(k.contact_id) FILTER (WHERE k.tem_ganho) AS com_card_ganho,
       count(*) FILTER (WHERE ct.contact_type = 2 AND k.tem_ganho) AS customer_com_ganho,
       count(*) FILTER (WHERE ct.contact_type = 2 AND k.contact_id IS NOT NULL AND NOT k.tem_ganho) AS customer_card_sem_ganho,
       count(*) FILTER (WHERE ct.contact_type = 2 AND k.contact_id IS NULL) AS customer_sem_card,
       count(*) FILTER (WHERE k.tem_ganho AND ct.contact_type IS DISTINCT FROM 2) AS ganho_sem_ser_customer
FROM contacts ct
JOIN :ativas a ON a.account_id = ct.account_id
LEFT JOIN cards_por_contato k ON k.account_id = ct.account_id AND k.contact_id = ct.id
GROUP BY ROLLUP (ct.account_id)
ORDER BY ct.account_id IS NULL, count(*) DESC, ct.account_id;

\echo '== 8. customer_since preenchido, por mes da data (todas as contas ativas) =='
SELECT to_char(date_trunc('month', ct.customer_since), 'YYYY-MM') AS mes,
       count(*) AS contatos,
       count(DISTINCT ct.account_id) AS contas
FROM contacts ct
JOIN :ativas a ON a.account_id = ct.account_id
WHERE ct.customer_since IS NOT NULL
GROUP BY 1
ORDER BY 1;


-- ============================================================================================================
-- PARTE D. OPT-OUT (recusa de contato)
-- ============================================================================================================

\echo '== 9. Opt-out por conta (+ TOTAL) =='
SELECT coalesce(ct.account_id::text, 'TOTAL') AS account_id,
       count(*) AS com_opt_out,
       count(*) FILTER (WHERE ct.opted_out_by_id IS NOT NULL) AS marcado_por_usuario,
       to_char(min(ct.opted_out_at), 'YYYY-MM') AS primeiro_mes,
       to_char(max(ct.opted_out_at), 'YYYY-MM') AS ultimo_mes
FROM contacts ct
JOIN :ativas a ON a.account_id = ct.account_id
WHERE ct.opted_out_at IS NOT NULL
GROUP BY ROLLUP (ct.account_id)
ORDER BY ct.account_id IS NULL, count(*) DESC, ct.account_id;

\echo '== 10. Opt-out por origem (codigo do sistema; valor fora da lista do codigo sai como (outro)) =='
SELECT CASE WHEN coalesce(ct.opt_out_source, '') = '' THEN '(vazio)'
            WHEN ct.opt_out_source IN ('prospecting', 'email_unsubscribe', 'manual') THEN ct.opt_out_source
            ELSE '(outro)' END AS opt_out_source,
       count(*) AS contatos,
       count(DISTINCT ct.account_id) AS contas,
       count(*) FILTER (WHERE ct.opted_out_at IS NULL) AS origem_sem_data
FROM contacts ct
JOIN :ativas a ON a.account_id = ct.account_id
WHERE ct.opted_out_at IS NOT NULL OR coalesce(ct.opt_out_source, '') <> ''
GROUP BY 1
ORDER BY 2 DESC;


-- ============================================================================================================
-- PARTE E. ENTRADA DE CONTATOS (ritmo e importacao)
-- ============================================================================================================

\echo '== 11. Contatos criados por mes, ultimos 18 meses (todas as contas ativas), e quantos ja conversaram =='
-- Mes com muito contato criado e pouca conversa = base importada.
-- Carga (auditoria da Orquestracao): a janela de 18 meses vale para os contatos; ja_conversaram e um EXISTS por contato,
-- resolvido pelo indice index_conversations_on_contact_id (db/schema.rb:1814).
SELECT to_char(date_trunc('month', ct.created_at), 'YYYY-MM') AS mes,
       count(*) AS contatos_criados,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM conversations cv WHERE cv.contact_id = ct.id)) AS ja_conversaram,
       count(DISTINCT ct.account_id) AS contas
FROM contacts ct
JOIN :ativas a ON a.account_id = ct.account_id
WHERE ct.created_at >= date_trunc('month', now()) - interval '17 months'
GROUP BY 1
ORDER BY 1;

\echo '== 12. Contatos criados por conta e mes, ultimos 12 meses, com o maior numero criado num so dia =='
-- pico_dia alto = importacao em massa naquele dia.
WITH d AS (
  SELECT ct.account_id, date_trunc('day', ct.created_at) AS dia, count(*) AS n
  FROM contacts ct
  JOIN :ativas a ON a.account_id = ct.account_id
  WHERE ct.created_at >= date_trunc('month', now()) - interval '11 months'
  GROUP BY 1, 2
)
SELECT d.account_id,
       to_char(date_trunc('month', d.dia), 'YYYY-MM') AS mes,
       sum(d.n) AS contatos,
       max(d.n) AS pico_dia,
       count(*) AS dias_com_criacao
FROM d
GROUP BY 1, 2
ORDER BY 1, 2;


-- ============================================================================================================
-- PARTE F. CANAIS
-- ============================================================================================================

\echo '== 13. Caixas de entrada por tipo de canal, por conta (+ subtotal da conta e TOTAL) =='
SELECT CASE WHEN grouping(i.account_id) = 1 THEN 'TOTAL' ELSE i.account_id::text END AS account_id,
       CASE WHEN grouping(i.channel_type) = 1 THEN '(todos)' ELSE coalesce(i.channel_type, '(vazio)') END AS channel_type,
       count(*) AS caixas
FROM inboxes i
JOIN :ativas a ON a.account_id = i.account_id
GROUP BY ROLLUP (i.account_id, i.channel_type)
ORDER BY grouping(i.account_id), i.account_id, grouping(i.channel_type), i.channel_type;

\echo '== 14. Contatos por tipo de canal, por conta: ligados a caixa (contact_inboxes) e que conversaram (conversations) =='
WITH vinc AS (
  SELECT i.account_id, i.channel_type, count(DISTINCT ci.contact_id) AS contatos_ligados
  FROM contact_inboxes ci
  JOIN inboxes i ON i.id = ci.inbox_id
  JOIN :ativas a ON a.account_id = i.account_id
  GROUP BY i.account_id, i.channel_type
),
falam AS (
  SELECT cv.account_id, i.channel_type,
         count(DISTINCT cv.contact_id) AS contatos_com_conversa,
         count(DISTINCT cv.contact_id) FILTER (WHERE cv.last_activity_at >= now() - interval '90 days') AS com_conversa_90d
  FROM conversations cv
  JOIN inboxes i ON i.id = cv.inbox_id
  JOIN :ativas a ON a.account_id = cv.account_id
  GROUP BY cv.account_id, i.channel_type
)
SELECT coalesce(v.account_id, f.account_id) AS account_id,
       coalesce(v.channel_type, f.channel_type, '(vazio)') AS channel_type,
       coalesce(v.contatos_ligados, 0) AS contatos_ligados,
       coalesce(f.contatos_com_conversa, 0) AS contatos_com_conversa,
       coalesce(f.com_conversa_90d, 0) AS com_conversa_90d
FROM vinc v
FULL JOIN falam f ON f.account_id = v.account_id AND f.channel_type IS NOT DISTINCT FROM v.channel_type
ORDER BY 1, 2;

\echo '== 15. Contatos ligados a um ou a mais de um tipo de canal, por conta (+ TOTAL) =='
WITH por_contato AS (
  SELECT i.account_id, ci.contact_id, count(DISTINCT i.channel_type) AS canais
  FROM contact_inboxes ci
  JOIN inboxes i ON i.id = ci.inbox_id
  JOIN :ativas a ON a.account_id = i.account_id
  WHERE ci.contact_id IS NOT NULL
  GROUP BY i.account_id, ci.contact_id
)
SELECT coalesce(p.account_id::text, 'TOTAL') AS account_id,
       count(*) AS contatos_com_caixa,
       count(*) FILTER (WHERE p.canais = 1) AS um_tipo_de_canal,
       count(*) FILTER (WHERE p.canais > 1) AS mais_de_um_tipo
FROM por_contato p
GROUP BY ROLLUP (p.account_id)
ORDER BY p.account_id NULLS LAST;


\echo '== FIM da parte 1: todos os blocos rodaram. A transacao e desfeita a seguir (ROLLBACK). =='
ROLLBACK;
