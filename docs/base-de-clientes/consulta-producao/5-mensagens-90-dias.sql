-- 5-mensagens-90-dias.sql
-- Pesquisa #1240 (Relacionamentos e Base de clientes). Consulta de producao, versao 2, parte 5 de 5.
-- Conferencia de contacts.last_activity_at contra as mensagens dos ultimos 90 dias (parte M).
-- Blocos 52 a 52 (1 no total). A numeracao dos blocos e a mesma nas 5 partes e no LEIA-ME.md.
--
-- QUEM RODA: outra sessao, por psql, nas duas instalacoes (Hub2You e Autonom.ia), com usuario de leitura, fora de deploy,
-- depois de conferir no pg_stat_activity que nao ha DDL em andamento. Uma parte por vez, em qualquer ordem.
--   psql "<conexao>" -X -v ON_ERROR_STOP=1 -f 5-mensagens-90-dias.sql > saida-5-<instalacao>.txt 2>&1
-- Precisa ser psql: usa \echo, \set e a variavel :ativas. Nao roda em cliente grafico.
--
-- GARANTIAS (as mesmas nas 5 partes; detalhes e testes no LEIA-ME.md)
--   * Somente leitura: BEGIN TRANSACTION READ ONLY ... ROLLBACK, uma transacao por parte. Nenhum INSERT/UPDATE/DELETE/
--     CREATE, nem tabela temporaria.
--   * Carga: cada bloco tem no maximo 60 s (statement_timeout) e espera no maximo 2 s por trava (lock_timeout). Teto desta
--     parte: 1 x 60 s. Se um bloco passar do limite, o psql para ali (ON_ERROR_STOP) e a transacao e desfeita; o que ja
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
-- PARTE M. CONFERENCIA PESADA (le a tabela messages; fica por ultimo)
-- ============================================================================================================

\echo '== 52. Conferencia dos ultimos 90 dias: ultima mensagem enviada PELO CONTATO (messages) x contacts.last_activity_at, por conta (+ TOTAL) =='
-- Mostra se contacts.last_activity_at serve para os grupos "Falou com voce ha pouco" / "Sumiu ha...".
-- Versao 2 (auditoria da Orquestracao): le so mensagens das contas ativas criadas nos ultimos 90 dias (messages.created_at),
-- o que o indice index_messages_on_account_created_type (account_id, created_at, message_type; db/schema.rb:3399) cobre.
-- A versao 1 lia todo o historico de mensagens de contato, de todas as contas.
-- Mensagem do contato = sender_type = 'Contact', a mesma condicao que atualiza o campo (message.rb:349-350).
-- Mensagem de historico da Coexistencia nao atualiza o campo (message.rb:337): pode explicar campo_vazio e campo_atrasado.
-- Colunas (tudo sobre a janela de 90 dias):
--   escreveram_90d = contatos com mensagem propria nos 90 dias; somam campo_igual + campo_vazio + campo_atrasado +
--     campo_adiantado;
--   campo_igual = last_activity_at a ate 1 dia da ultima mensagem do contato;
--   campo_vazio = escreveu, mas last_activity_at e nulo;
--   campo_atrasado = last_activity_at mais de 1 dia antes da ultima mensagem;
--   campo_adiantado = last_activity_at mais de 1 dia depois da ultima mensagem (outra fonte, ex.: importacao);
--   campo_90d_sem_mensagem = last_activity_at nos ultimos 90 dias, sem mensagem do contato na janela (data trazida por
--     importacao, app/services/data_imports/importer.rb:310,364, ou mensagem que nao conta).
WITH ult_msg AS (
  SELECT m.sender_id AS contact_id, max(m.created_at) AS ultima
  FROM messages m
  JOIN :ativas a ON a.account_id = m.account_id
  WHERE m.created_at >= now() - interval '90 days'
    AND m.sender_type = 'Contact'
  GROUP BY m.sender_id
),
f AS (
  SELECT ct.account_id, ct.last_activity_at, u.ultima
  FROM contacts ct
  JOIN :ativas a ON a.account_id = ct.account_id
  LEFT JOIN ult_msg u ON u.contact_id = ct.id
  WHERE u.contact_id IS NOT NULL OR ct.last_activity_at >= now() - interval '90 days'
)
SELECT coalesce(f.account_id::text, 'TOTAL') AS account_id,
       count(*) FILTER (WHERE f.ultima IS NOT NULL) AS escreveram_90d,
       count(*) FILTER (WHERE f.ultima IS NOT NULL
                          AND abs(extract(epoch FROM (f.last_activity_at - f.ultima))) <= 86400) AS campo_igual,
       count(*) FILTER (WHERE f.ultima IS NOT NULL AND f.last_activity_at IS NULL) AS campo_vazio,
       count(*) FILTER (WHERE f.ultima IS NOT NULL AND f.last_activity_at < f.ultima - interval '1 day') AS campo_atrasado,
       count(*) FILTER (WHERE f.ultima IS NOT NULL AND f.last_activity_at > f.ultima + interval '1 day') AS campo_adiantado,
       count(*) FILTER (WHERE f.ultima IS NULL) AS campo_90d_sem_mensagem
FROM f
GROUP BY ROLLUP (f.account_id)
ORDER BY f.account_id NULLS LAST;

\echo '== FIM da parte 5: todos os blocos rodaram. A transacao e desfeita a seguir (ROLLBACK). =='
ROLLBACK;
