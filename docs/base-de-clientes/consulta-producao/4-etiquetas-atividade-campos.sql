-- 4-etiquetas-atividade-campos.sql
-- Pesquisa #1240 (Relacionamentos e Base de clientes). Consulta de producao, versao 2, parte 4 de 5.
-- Etiquetas, atividade e campos personalizados (partes J, K e L).
-- Blocos 38 a 51 (14 no total). A numeracao dos blocos e a mesma nas 5 partes e no LEIA-ME.md.
--
-- QUEM RODA: outra sessao, por psql, nas duas instalacoes (Hub2You e Autonom.ia), com usuario de leitura, fora de deploy,
-- depois de conferir no pg_stat_activity que nao ha DDL em andamento. Uma parte por vez, em qualquer ordem.
--   psql "<conexao>" -X -v ON_ERROR_STOP=1 -f 4-etiquetas-atividade-campos.sql > saida-4-<instalacao>.txt 2>&1
-- Precisa ser psql: usa \echo, \set e a variavel :ativas. Nao roda em cliente grafico.
--
-- GARANTIAS (as mesmas nas 5 partes; detalhes e testes no LEIA-ME.md)
--   * Somente leitura: BEGIN TRANSACTION READ ONLY ... ROLLBACK, uma transacao por parte. Nenhum INSERT/UPDATE/DELETE/
--     CREATE, nem tabela temporaria.
--   * Carga: cada bloco tem no maximo 60 s (statement_timeout) e espera no maximo 2 s por trava (lock_timeout). Teto desta
--     parte: 14 x 60 s. Se um bloco passar do limite, o psql para ali (ON_ERROR_STOP) e a transacao e desfeita; o que ja
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
-- PARTE J. ETIQUETAS
-- ============================================================================================================
-- Etiqueta de contato: acts_as_taggable_on :labels (app/models/concerns/labelable.rb:5) =>
--   taggings.taggable_type = 'Contact' e context = 'labels'; o texto fica em tags.name (tabela global);
--   etiqueta "configurada" = existe em labels.title da mesma conta.

\echo '== 38. Etiquetas em contatos por conta: configuradas, usadas e contatos etiquetados (+ TOTAL) =='
WITH tg AS (
  SELECT c.account_id, t.tag_id, t.taggable_id
  FROM taggings t
  JOIN contacts c ON c.id = t.taggable_id
  JOIN :ativas a ON a.account_id = c.account_id
  WHERE t.taggable_type = 'Contact' AND t.context = 'labels'
),
uso AS (
  SELECT tg.account_id,
         count(DISTINCT tg.tag_id) AS etiquetas_usadas,
         count(*) AS taggings,
         count(DISTINCT tg.taggable_id) AS contatos_etiquetados
  FROM tg
  GROUP BY tg.account_id
),
cfg AS (
  SELECT l.account_id, count(*) AS etiquetas_configuradas
  FROM labels l
  JOIN :ativas a ON a.account_id = l.account_id
  GROUP BY l.account_id
),
tot AS (
  SELECT c.account_id, count(*) AS contatos
  FROM contacts c
  JOIN :ativas a ON a.account_id = c.account_id
  GROUP BY c.account_id
)
SELECT coalesce(a.account_id::text, 'TOTAL') AS account_id,
       sum(coalesce(cfg.etiquetas_configuradas, 0)) AS etiquetas_configuradas,
       sum(coalesce(uso.etiquetas_usadas, 0)) AS etiquetas_usadas_em_contato,
       sum(coalesce(uso.taggings, 0)) AS taggings_em_contato,
       sum(coalesce(uso.contatos_etiquetados, 0)) AS contatos_etiquetados,
       sum(coalesce(tot.contatos, 0)) AS contatos,
       round(100.0 * sum(coalesce(uso.contatos_etiquetados, 0)) / nullif(sum(coalesce(tot.contatos, 0)), 0), 1)
         AS pct_contatos_etiquetados
FROM :ativas a
LEFT JOIN cfg ON cfg.account_id = a.account_id
LEFT JOIN uso ON uso.account_id = a.account_id
LEFT JOIN tot ON tot.account_id = a.account_id
GROUP BY ROLLUP (a.account_id)
ORDER BY a.account_id IS NULL, sum(coalesce(uso.contatos_etiquetados, 0)) DESC, a.account_id;

\echo '== 39. Etiquetas: em quantas contas o mesmo titulo existe (so contagem; nenhum titulo sai) =='
-- Versao 2 (auditoria da Orquestracao): titulo de etiqueta e texto digitado e nao sai mais, nem o de varias contas.
-- Agrupa as etiquetas configuradas (labels) pelo numero de contas ativas que tem o mesmo titulo (minusculas, sem espaco
-- nas pontas): 1 conta, 2 contas, 3 a 9 contas, 10 ou mais.
-- etiquetas_configuradas = pares conta + titulo; titulos_distintos = titulos diferentes na faixa.
-- com_arroba_ou_6_digitos = titulos com '@' ou 6+ digitos (dado de pessoa usado como etiqueta).
-- contatos_etiquetados = contatos com a etiqueta (taggings de contexto labels), somados nas contas.
WITH cfg AS (
  SELECT DISTINCT l.account_id, lower(btrim(l.title)) AS titulo
  FROM labels l
  JOIN :ativas a ON a.account_id = l.account_id
  WHERE coalesce(btrim(l.title), '') <> ''
),
uso AS (
  SELECT c.account_id, lower(btrim(tg.name)) AS titulo, count(DISTINCT t.taggable_id) AS contatos
  FROM taggings t
  JOIN tags tg ON tg.id = t.tag_id
  JOIN contacts c ON c.id = t.taggable_id
  JOIN :ativas a ON a.account_id = c.account_id
  WHERE t.taggable_type = 'Contact' AND t.context = 'labels'
  GROUP BY 1, 2
),
j AS (
  SELECT cfg.account_id, cfg.titulo, coalesce(uso.contatos, 0) AS contatos
  FROM cfg
  LEFT JOIN uso ON uso.account_id = cfg.account_id AND uso.titulo = cfg.titulo
),
por_titulo AS (
  SELECT j.titulo, count(DISTINCT j.account_id) AS contas
  FROM j
  GROUP BY j.titulo
)
SELECT CASE WHEN p.contas = 1 THEN '1 conta'
            WHEN p.contas = 2 THEN '2 contas'
            WHEN p.contas < 10 THEN '3 a 9 contas'
            ELSE '10 ou mais contas' END AS faixa,
       count(DISTINCT j.titulo) AS titulos_distintos,
       count(*) AS etiquetas_configuradas,
       count(*) FILTER (WHERE j.contatos > 0) AS etiquetas_usadas_em_contato,
       sum(j.contatos) AS contatos_etiquetados,
       count(DISTINCT j.titulo) FILTER (WHERE position('@' IN j.titulo) > 0
                                           OR length(j.titulo) - length(translate(j.titulo, '0123456789', '')) >= 6)
         AS com_arroba_ou_6_digitos
FROM j
JOIN por_titulo p ON p.titulo = j.titulo
GROUP BY 1
ORDER BY min(p.contas);

\echo '== 40. Taggings de contato com tag que NAO e etiqueta configurada da conta (so contagem; + TOTAL) =='
SELECT coalesce(c.account_id::text, 'TOTAL') AS account_id,
       count(*) AS taggings_sem_etiqueta_configurada,
       count(DISTINCT t.tag_id) AS tags_distintas
FROM taggings t
JOIN tags tg ON tg.id = t.tag_id
JOIN contacts c ON c.id = t.taggable_id
JOIN :ativas a ON a.account_id = c.account_id
WHERE t.taggable_type = 'Contact' AND t.context = 'labels'
  AND NOT EXISTS (SELECT 1 FROM labels l WHERE l.account_id = c.account_id AND lower(l.title) = lower(tg.name))
GROUP BY ROLLUP (c.account_id)
ORDER BY c.account_id NULLS LAST;


-- ============================================================================================================
-- PARTE K. ATIVIDADE (base dos grupos prontos)
-- ============================================================================================================

\echo '== 41. Faixas pela ultima vez que o CONTATO escreveu (contacts.last_activity_at), por conta (+ TOTAL) =='
WITH f AS (
  SELECT ct.account_id,
         CASE
           WHEN ct.last_activity_at IS NULL THEN '6_nunca'
           WHEN ct.last_activity_at >= now() - interval '30 days'  THEN '1_ate_30d'
           WHEN ct.last_activity_at >= now() - interval '90 days'  THEN '2_31_90d'
           WHEN ct.last_activity_at >= now() - interval '180 days' THEN '3_91_180d'
           WHEN ct.last_activity_at >= now() - interval '365 days' THEN '4_181_365d'
           ELSE '5_mais_1_ano'
         END AS faixa
  FROM contacts ct
  JOIN :ativas a ON a.account_id = ct.account_id
)
SELECT coalesce(f.account_id::text, 'TOTAL') AS account_id,
       count(*) AS contatos,
       count(*) FILTER (WHERE f.faixa = '1_ate_30d')    AS ate_30d,
       count(*) FILTER (WHERE f.faixa = '2_31_90d')     AS d31_90,
       count(*) FILTER (WHERE f.faixa = '3_91_180d')    AS d91_180,
       count(*) FILTER (WHERE f.faixa = '4_181_365d')   AS d181_365,
       count(*) FILTER (WHERE f.faixa = '5_mais_1_ano') AS mais_1_ano,
       count(*) FILTER (WHERE f.faixa = '6_nunca')      AS nunca
FROM f
GROUP BY ROLLUP (f.account_id)
ORDER BY f.account_id NULLS LAST;

\echo '== 42. Faixas pela ultima movimentacao em qualquer conversa do contato (inclui mensagens nossas) e contatos sem conversa (+ TOTAL) =='
-- sem_conversa = contato sem nenhuma conversa (conversations.last_activity_at e NOT NULL, entao nao ha conversa sem data).
-- Carga (auditoria da Orquestracao): le as conversas das contas ativas uma vez e agrega por contato; a faixa precisa da
-- ultima conversa de qualquer data, entao nao cabe janela. Nao ha indice em conversations.last_activity_at
-- (db/schema.rb:1806-1825), entao uma janela tambem nao diminuiria a leitura. Teto: statement_timeout de 60 s.
WITH ult AS (
  SELECT cv.contact_id, max(cv.last_activity_at) AS ultima
  FROM conversations cv
  JOIN :ativas a ON a.account_id = cv.account_id
  WHERE cv.contact_id IS NOT NULL
  GROUP BY cv.contact_id
),
f AS (
  SELECT ct.account_id,
         CASE
           WHEN u.contact_id IS NULL THEN '6_sem_conversa'
           WHEN u.ultima >= now() - interval '30 days'  THEN '1_ate_30d'
           WHEN u.ultima >= now() - interval '90 days'  THEN '2_31_90d'
           WHEN u.ultima >= now() - interval '180 days' THEN '3_91_180d'
           WHEN u.ultima >= now() - interval '365 days' THEN '4_181_365d'
           ELSE '5_mais_1_ano'
         END AS faixa
  FROM contacts ct
  JOIN :ativas a ON a.account_id = ct.account_id
  LEFT JOIN ult u ON u.contact_id = ct.id
)
SELECT coalesce(f.account_id::text, 'TOTAL') AS account_id,
       count(*) AS contatos,
       count(*) FILTER (WHERE f.faixa = '1_ate_30d')      AS ate_30d,
       count(*) FILTER (WHERE f.faixa = '2_31_90d')       AS d31_90,
       count(*) FILTER (WHERE f.faixa = '3_91_180d')      AS d91_180,
       count(*) FILTER (WHERE f.faixa = '4_181_365d')     AS d181_365,
       count(*) FILTER (WHERE f.faixa = '5_mais_1_ano')   AS mais_1_ano,
       count(*) FILTER (WHERE f.faixa = '6_sem_conversa') AS sem_conversa,
       round(100.0 * count(*) FILTER (WHERE f.faixa = '6_sem_conversa') / nullif(count(*), 0), 1) AS pct_sem_conversa
FROM f
GROUP BY ROLLUP (f.account_id)
ORDER BY f.account_id NULLS LAST;

\echo '== 43. Conversas por contato (so quem tem conversa): p50, p90, p99, maximo e quantos tem mais de uma (+ TOTAL) =='
WITH conv AS (
  SELECT cv.account_id, cv.contact_id, count(*) AS n
  FROM conversations cv
  JOIN :ativas a ON a.account_id = cv.account_id
  WHERE cv.contact_id IS NOT NULL
  GROUP BY cv.account_id, cv.contact_id
)
SELECT coalesce(c.account_id::text, 'TOTAL') AS account_id,
       count(*) AS contatos_com_conversa,
       percentile_disc(0.5)  WITHIN GROUP (ORDER BY c.n) AS p50,
       percentile_disc(0.9)  WITHIN GROUP (ORDER BY c.n) AS p90,
       percentile_disc(0.99) WITHIN GROUP (ORDER BY c.n) AS p99,
       max(c.n) AS maximo,
       count(*) FILTER (WHERE c.n > 1) AS com_mais_de_uma,
       round(100.0 * count(*) FILTER (WHERE c.n > 1) / nullif(count(*), 0), 1) AS pct_mais_de_uma,
       count(*) FILTER (WHERE c.n >= 5) AS com_5_ou_mais
FROM conv c
GROUP BY ROLLUP (c.account_id)
ORDER BY c.account_id NULLS LAST;


-- ============================================================================================================
-- PARTE L. CAMPOS PERSONALIZADOS E ATRIBUTOS (tela Informacoes). Os blocos 47 a 51 abrem o jsonb de todos os contatos.
-- ============================================================================================================
-- "Preenchido" = valor que nao e null, "", [] nem {} (false e 0 contam como preenchidos).
-- Todo jsonb_each so abre a coluna quando ela e objeto (jsonb_typeof = 'object'); lixo na coluna nao derruba a consulta.

\echo '== 44. Campos personalizados definidos por conta e modelo (0 conversa, 1 contato, 2 empresa, 3 card) (+ TOTAL) =='
SELECT coalesce(d.account_id::text, 'TOTAL') AS account_id,
       count(*) FILTER (WHERE d.attribute_model = 0) AS conversa,
       count(*) FILTER (WHERE d.attribute_model = 1) AS contato,
       count(*) FILTER (WHERE d.attribute_model = 2) AS empresa,
       count(*) FILTER (WHERE d.attribute_model = 3) AS card,
       count(*) AS total,
       count(*) FILTER (WHERE coalesce(btrim(d.attribute_description), '') = '') AS sem_descricao,
       to_char(min(d.created_at), 'YYYY-MM') AS primeiro_mes,
       to_char(max(d.created_at), 'YYYY-MM') AS ultimo_mes
FROM custom_attribute_definitions d
JOIN :ativas a ON a.account_id = d.account_id
GROUP BY ROLLUP (d.account_id)
ORDER BY d.account_id NULLS LAST;

\echo '== 45. Campos personalizados por modelo e tipo (total geral) =='
SELECT CASE d.attribute_model WHEN 0 THEN 'conversa' WHEN 1 THEN 'contato' WHEN 2 THEN 'empresa' WHEN 3 THEN 'card'
            ELSE 'modelo_' || d.attribute_model END AS modelo,
       CASE d.attribute_display_type WHEN 0 THEN 'text' WHEN 1 THEN 'number' WHEN 2 THEN 'currency' WHEN 3 THEN 'percent'
            WHEN 4 THEN 'link' WHEN 5 THEN 'date' WHEN 6 THEN 'list' WHEN 7 THEN 'checkbox'
            ELSE 'tipo_' || d.attribute_display_type END AS tipo,
       count(*) AS campos,
       count(DISTINCT d.account_id) AS contas,
       count(*) FILTER (WHERE coalesce(btrim(d.attribute_description), '') = '') AS sem_descricao,
       count(*) FILTER (WHERE coalesce(d.regex_pattern, '') <> '') AS com_validacao
FROM custom_attribute_definitions d
JOIN :ativas a ON a.account_id = d.account_id
GROUP BY 1, 2
ORDER BY 1, campos DESC, 2;

\echo '== 46. Chaves de campo personalizado que se repetem entre contas (REGRA DO TEXTO) =='
-- Candidatas a campo padrao (CPF, data de nascimento...) em vez de campo personalizado de cada conta.
-- Versao 2 (auditoria da Orquestracao): o "Importar contatos" (#1006) cria definicao a partir do titulo da coluna
-- (app/services/contact_imports/custom_attributes.rb:47-51), entao a definicao sozinha nao basta. Vale a regra dos blocos
-- de campo: a chave so e visivel se tem VALOR em :min_contas ou mais contas que a definem (contato:
-- contacts.custom_attributes; empresa: companies.custom_attributes; card: crm_cards.custom_attributes). nome_exibido idem:
-- o nome mais comum so sai se aparece em :min_contas ou mais contas em que a chave tem valor.
-- O modelo conversa (0) fica de fora desta lista: nao e dado de relacionamento e obrigaria a abrir o jsonb de todas as
-- conversas; as definicoes de conversa estao contadas nos blocos 44 e 45.
-- Uma linha por modelo + chave visivel + tipo. contas = contas que definem; contas_com_valor = das quais a chave tem valor.
-- A linha (oculto) de cada modelo soma as chaves que nao passam.
WITH defs AS (
  SELECT d.account_id, d.attribute_model, d.attribute_display_type,
         lower(btrim(d.attribute_key)) AS chave,
         lower(btrim(coalesce(d.attribute_display_name, ''))) AS nome,
         coalesce(btrim(d.attribute_description), '') = '' AS sem_descricao
  FROM custom_attribute_definitions d
  JOIN :ativas a ON a.account_id = d.account_id
  WHERE d.attribute_model IN (1, 2, 3)
),
valores AS (
  SELECT 1 AS attribute_model, c.account_id, lower(btrim(e.key)) AS chave
  FROM contacts c
  JOIN :ativas a ON a.account_id = c.account_id
  CROSS JOIN LATERAL jsonb_each(CASE WHEN jsonb_typeof(c.custom_attributes) = 'object'
                                     THEN c.custom_attributes ELSE '{}'::jsonb END) e
  WHERE e.value NOT IN ('null'::jsonb, '""'::jsonb, '[]'::jsonb, '{}'::jsonb)
  UNION
  SELECT 2, co.account_id, lower(btrim(e.key))
  FROM companies co
  JOIN :ativas a ON a.account_id = co.account_id
  CROSS JOIN LATERAL jsonb_each(CASE WHEN jsonb_typeof(co.custom_attributes) = 'object'
                                     THEN co.custom_attributes ELSE '{}'::jsonb END) e
  WHERE e.value NOT IN ('null'::jsonb, '""'::jsonb, '[]'::jsonb, '{}'::jsonb)
  UNION
  SELECT 3, cc.account_id, lower(btrim(e.key))
  FROM crm_cards cc
  JOIN :ativas a ON a.account_id = cc.account_id
  CROSS JOIN LATERAL jsonb_each(CASE WHEN jsonb_typeof(cc.custom_attributes) = 'object'
                                     THEN cc.custom_attributes ELSE '{}'::jsonb END) e
  WHERE e.value NOT IN ('null'::jsonb, '""'::jsonb, '[]'::jsonb, '{}'::jsonb)
),
dv AS (
  SELECT x.account_id, x.attribute_model, x.attribute_display_type, x.chave, x.nome, x.sem_descricao,
         v.chave IS NOT NULL AS com_valor
  FROM defs x
  LEFT JOIN valores v ON v.attribute_model = x.attribute_model AND v.account_id = x.account_id AND v.chave = x.chave
),
vis AS (
  SELECT x.attribute_model, x.chave,
         count(DISTINCT x.account_id) FILTER (WHERE x.com_valor) >= :min_contas
         AND position('@' IN x.chave) = 0
         AND length(x.chave) - length(translate(x.chave, '0123456789', '')) < 6 AS visivel
  FROM dv x
  GROUP BY x.attribute_model, x.chave
),
nomes AS (
  SELECT DISTINCT ON (x.attribute_model, x.chave) x.attribute_model, x.chave, x.nome,
         count(DISTINCT x.account_id) FILTER (WHERE x.com_valor) AS contas_nome
  FROM dv x
  GROUP BY x.attribute_model, x.chave, x.nome
  ORDER BY x.attribute_model, x.chave, count(DISTINCT x.account_id) FILTER (WHERE x.com_valor) DESC, x.nome
)
SELECT CASE d.attribute_model WHEN 1 THEN 'contato' WHEN 2 THEN 'empresa' WHEN 3 THEN 'card'
            ELSE 'modelo_' || d.attribute_model END AS modelo,
       CASE WHEN v.visivel THEN left(d.chave, 60) ELSE '(oculto)' END AS chave,
       CASE WHEN v.visivel AND n.contas_nome >= :min_contas AND position('@' IN n.nome) = 0
                 AND length(n.nome) - length(translate(n.nome, '0123456789', '')) < 6
            THEN left(n.nome, 60) END AS nome_exibido,
       CASE WHEN v.visivel THEN
         CASE d.attribute_display_type WHEN 0 THEN 'text' WHEN 1 THEN 'number' WHEN 2 THEN 'currency' WHEN 3 THEN 'percent'
              WHEN 4 THEN 'link' WHEN 5 THEN 'date' WHEN 6 THEN 'list' WHEN 7 THEN 'checkbox'
              ELSE 'tipo_' || d.attribute_display_type END
       END AS tipo,
       count(DISTINCT d.chave) AS chaves,
       count(DISTINCT d.account_id) AS contas,
       count(DISTINCT d.account_id) FILTER (WHERE d.com_valor) AS contas_com_valor,
       count(*) AS definicoes,
       count(*) FILTER (WHERE d.sem_descricao) AS sem_descricao
FROM dv d
JOIN vis v ON v.attribute_model = d.attribute_model AND v.chave = d.chave
JOIN nomes n ON n.attribute_model = d.attribute_model AND n.chave = d.chave
GROUP BY d.attribute_model, 2, 3, 4
ORDER BY d.attribute_model, bool_and(NOT v.visivel), contas DESC, 2, 4;

\echo '== 47. Campos de contato (contacts.custom_attributes) por conta: uso, campos abandonados e chaves sem definicao (+ TOTAL) =='
-- definido = a chave existe em custom_attribute_definitions (modelo 1 = contato) da conta.
-- chave sem definicao = gravada por integracao, API ou importacao de outra plataforma (ex.: waha_*), ou campo apagado.
-- campos_definidos_sem_nenhum_valor = campo criado que nenhum contato da conta preencheu.
-- Nenhuma chave nem valor sai aqui; as chaves comuns a varias contas estao no bloco 48.
WITH defs AS (
  SELECT d.account_id, d.attribute_key AS chave
  FROM custom_attribute_definitions d
  JOIN :ativas a ON a.account_id = d.account_id
  WHERE d.attribute_model = 1
),
kv AS (
  SELECT c.account_id, c.id AS contact_id, e.key AS chave
  FROM contacts c
  JOIN :ativas a ON a.account_id = c.account_id
  CROSS JOIN LATERAL jsonb_each(CASE WHEN jsonb_typeof(c.custom_attributes) = 'object'
                                     THEN c.custom_attributes ELSE '{}'::jsonb END) e
  WHERE e.value NOT IN ('null'::jsonb, '""'::jsonb, '[]'::jsonb, '{}'::jsonb)
),
kvd AS (
  SELECT kv.account_id, kv.contact_id, kv.chave, df.chave IS NOT NULL AS definida
  FROM kv
  LEFT JOIN defs df ON df.account_id = kv.account_id AND df.chave = kv.chave
),
uso_contato AS (
  SELECT k.account_id,
         count(DISTINCT k.contact_id) AS contatos_com_algum_valor,
         count(DISTINCT k.contact_id) FILTER (WHERE k.definida) AS contatos_com_campo_definido,
         count(DISTINCT k.contact_id) FILTER (WHERE NOT k.definida) AS contatos_com_chave_sem_definicao,
         count(DISTINCT k.chave) FILTER (WHERE NOT k.definida) AS chaves_sem_definicao_com_valor
  FROM kvd k
  GROUP BY k.account_id
),
chaves_usadas AS (
  SELECT DISTINCT kv.account_id, kv.chave FROM kv
),
uso_def AS (
  SELECT df.account_id, count(*) AS campos_definidos, count(u.chave) AS campos_definidos_usados
  FROM defs df
  LEFT JOIN chaves_usadas u ON u.account_id = df.account_id AND u.chave = df.chave
  GROUP BY df.account_id
),
tot AS (
  SELECT c.account_id, count(*) AS contatos
  FROM contacts c
  JOIN :ativas a ON a.account_id = c.account_id
  GROUP BY c.account_id
),
por_conta AS (
  SELECT a.account_id,
         coalesce(t.contatos, 0) AS contatos,
         coalesce(ud.campos_definidos, 0) AS campos_definidos,
         coalesce(ud.campos_definidos_usados, 0) AS campos_definidos_usados,
         coalesce(uc.chaves_sem_definicao_com_valor, 0) AS chaves_sem_definicao_com_valor,
         coalesce(uc.contatos_com_algum_valor, 0) AS contatos_com_algum_valor,
         coalesce(uc.contatos_com_campo_definido, 0) AS contatos_com_campo_definido,
         coalesce(uc.contatos_com_chave_sem_definicao, 0) AS contatos_com_chave_sem_definicao
  FROM :ativas a
  LEFT JOIN tot t ON t.account_id = a.account_id
  LEFT JOIN uso_def ud ON ud.account_id = a.account_id
  LEFT JOIN uso_contato uc ON uc.account_id = a.account_id
  WHERE t.account_id IS NOT NULL OR ud.account_id IS NOT NULL
)
SELECT coalesce(p.account_id::text, 'TOTAL') AS account_id,
       sum(p.contatos) AS contatos,
       sum(p.campos_definidos) AS campos_definidos,
       sum(p.campos_definidos_usados) AS campos_definidos_usados,
       sum(p.campos_definidos) - sum(p.campos_definidos_usados) AS campos_definidos_sem_nenhum_valor,
       sum(p.chaves_sem_definicao_com_valor) AS chaves_sem_definicao_com_valor,
       sum(p.contatos_com_algum_valor) AS contatos_com_algum_valor,
       sum(p.contatos_com_campo_definido) AS contatos_com_campo_definido,
       round(100.0 * sum(p.contatos_com_campo_definido) / nullif(sum(p.contatos), 0), 1) AS pct_com_campo_definido,
       sum(p.contatos_com_chave_sem_definicao) AS contatos_com_chave_sem_definicao
FROM por_conta p
GROUP BY ROLLUP (p.account_id)
ORDER BY p.account_id IS NULL, sum(p.contatos) DESC, p.account_id;

\echo '== 48. Campos de contato por chave, somando as contas (REGRA DO TEXTO) =='
-- contas_que_definem = contas com a chave em custom_attribute_definitions (modelo contato).
-- pct_nas_contas_com_valor = contatos com valor / contatos das contas em que a chave tem valor (so para chave visivel).
-- Versao 2: a chave so e visivel se tem VALOR em :min_contas ou mais contas (a definicao sozinha nao conta).
WITH kv AS (
  SELECT c.account_id, lower(btrim(e.key)) AS chave, count(*) AS contatos_com_valor
  FROM contacts c
  JOIN :ativas a ON a.account_id = c.account_id
  CROSS JOIN LATERAL jsonb_each(CASE WHEN jsonb_typeof(c.custom_attributes) = 'object'
                                     THEN c.custom_attributes ELSE '{}'::jsonb END) e
  WHERE e.value NOT IN ('null'::jsonb, '""'::jsonb, '[]'::jsonb, '{}'::jsonb)
  GROUP BY 1, 2
),
defs AS (
  SELECT DISTINCT d.account_id, lower(btrim(d.attribute_key)) AS chave
  FROM custom_attribute_definitions d
  JOIN :ativas a ON a.account_id = d.account_id
  WHERE d.attribute_model = 1
),
todas AS (
  SELECT coalesce(kv.account_id, df.account_id) AS account_id,
         coalesce(kv.chave, df.chave) AS chave,
         df.chave IS NOT NULL AS definida,
         coalesce(kv.contatos_com_valor, 0) AS contatos_com_valor
  FROM kv
  FULL JOIN defs df ON df.account_id = kv.account_id AND df.chave = kv.chave
),
tot AS (
  SELECT c.account_id, count(*) AS contatos
  FROM contacts c
  JOIN :ativas a ON a.account_id = c.account_id
  GROUP BY c.account_id
),
vis AS (
  SELECT t.chave,
         count(DISTINCT t.account_id) FILTER (WHERE t.contatos_com_valor > 0) >= :min_contas
         AND position('@' IN t.chave) = 0
         AND length(t.chave) - length(translate(t.chave, '0123456789', '')) < 6 AS visivel
  FROM todas t
  GROUP BY t.chave
)
SELECT CASE WHEN v.visivel THEN left(t.chave, 60) ELSE '(oculto)' END AS chave,
       count(DISTINCT t.chave) AS chaves,
       count(DISTINCT t.account_id) FILTER (WHERE t.definida) AS contas_que_definem,
       count(DISTINCT t.account_id) FILTER (WHERE t.contatos_com_valor > 0) AS contas_com_valor,
       sum(t.contatos_com_valor) AS contatos_com_valor,
       CASE WHEN bool_and(v.visivel)
            THEN round(100.0 * sum(t.contatos_com_valor)
                       / nullif(sum(tt.contatos) FILTER (WHERE t.contatos_com_valor > 0), 0), 1) END AS pct_nas_contas_com_valor
FROM todas t
JOIN vis v ON v.chave = t.chave
LEFT JOIN tot tt ON tt.account_id = t.account_id
GROUP BY 1
ORDER BY bool_and(NOT v.visivel), contas_com_valor DESC, contatos_com_valor DESC, 1;

\echo '== 49. contacts.additional_attributes: chaves existentes, total geral (REGRA DO TEXTO; nenhum valor) =='
-- Dado de pessoa e de empresa que ja existe fora de campo personalizado (company_name, city, country, social_profiles...).
-- Versao 2 (blocos 49 e 50): a chave so e visivel se esta PREENCHIDA em :min_contas ou mais contas.
WITH kv AS (
  SELECT c.account_id, lower(btrim(e.key)) AS chave, jsonb_typeof(e.value) AS tipo_json,
         e.value NOT IN ('null'::jsonb, '""'::jsonb, '[]'::jsonb, '{}'::jsonb) AS preenchida
  FROM contacts c
  JOIN :ativas a ON a.account_id = c.account_id
  CROSS JOIN LATERAL jsonb_each(CASE WHEN jsonb_typeof(c.additional_attributes) = 'object'
                                     THEN c.additional_attributes ELSE '{}'::jsonb END) e
),
vis AS (
  SELECT k.chave,
         count(DISTINCT k.account_id) FILTER (WHERE k.preenchida) >= :min_contas
         AND position('@' IN k.chave) = 0
         AND length(k.chave) - length(translate(k.chave, '0123456789', '')) < 6 AS visivel
  FROM kv k
  GROUP BY k.chave
)
SELECT CASE WHEN v.visivel THEN left(k.chave, 60) ELSE '(oculto)' END AS chave,
       CASE WHEN v.visivel THEN k.tipo_json END AS tipo_json,
       count(DISTINCT k.chave) AS chaves,
       count(DISTINCT k.account_id) AS contas,
       count(*) AS contatos_com_chave,
       count(*) FILTER (WHERE k.preenchida) AS contatos_preenchidos
FROM kv k
JOIN vis v ON v.chave = k.chave
GROUP BY 1, 2
ORDER BY bool_and(NOT v.visivel), contatos_preenchidos DESC, 1, 2;

\echo '== 50. contacts.additional_attributes: chaves preenchidas por conta (REGRA DO TEXTO; nenhum valor) =='
WITH kv AS (
  SELECT c.account_id, lower(btrim(e.key)) AS chave,
         e.value NOT IN ('null'::jsonb, '""'::jsonb, '[]'::jsonb, '{}'::jsonb) AS preenchida
  FROM contacts c
  JOIN :ativas a ON a.account_id = c.account_id
  CROSS JOIN LATERAL jsonb_each(CASE WHEN jsonb_typeof(c.additional_attributes) = 'object'
                                     THEN c.additional_attributes ELSE '{}'::jsonb END) e
),
vis AS (
  SELECT k.chave,
         count(DISTINCT k.account_id) FILTER (WHERE k.preenchida) >= :min_contas
         AND position('@' IN k.chave) = 0
         AND length(k.chave) - length(translate(k.chave, '0123456789', '')) < 6 AS visivel
  FROM kv k
  GROUP BY k.chave
)
SELECT k.account_id,
       CASE WHEN v.visivel THEN left(k.chave, 60) ELSE '(oculto)' END AS chave,
       count(DISTINCT k.chave) FILTER (WHERE k.preenchida) AS chaves,
       count(*) FILTER (WHERE k.preenchida) AS contatos_preenchidos
FROM kv k
JOIN vis v ON v.chave = k.chave
GROUP BY 1, 2
HAVING count(*) FILTER (WHERE k.preenchida) > 0
ORDER BY 1, bool_and(NOT v.visivel), contatos_preenchidos DESC, 2;

\echo '== 51. social_profiles: quais redes aparecem preenchidas (REGRA DO TEXTO; nenhum perfil sai) =='
WITH s AS (
  SELECT c.account_id, lower(btrim(p.key)) AS rede
  FROM contacts c
  JOIN :ativas a ON a.account_id = c.account_id
  CROSS JOIN LATERAL jsonb_each(CASE WHEN jsonb_typeof(c.additional_attributes -> 'social_profiles') = 'object'
                                     THEN c.additional_attributes -> 'social_profiles' ELSE '{}'::jsonb END) p
  WHERE p.value NOT IN ('null'::jsonb, '""'::jsonb, '[]'::jsonb, '{}'::jsonb)
),
vis AS (
  SELECT s.rede,
         count(DISTINCT s.account_id) >= :min_contas
         AND position('@' IN s.rede) = 0
         AND length(s.rede) - length(translate(s.rede, '0123456789', '')) < 6 AS visivel
  FROM s
  GROUP BY s.rede
)
SELECT CASE WHEN v.visivel THEN left(s.rede, 60) ELSE '(oculto)' END AS rede,
       count(DISTINCT s.rede) AS redes,
       count(DISTINCT s.account_id) AS contas,
       count(*) AS contatos_preenchidos
FROM s
JOIN vis v ON v.rede = s.rede
GROUP BY 1
ORDER BY bool_and(NOT v.visivel), contatos_preenchidos DESC, 1;


\echo '== FIM da parte 4: todos os blocos rodaram. A transacao e desfeita a seguir (ROLLBACK). =='
ROLLBACK;
