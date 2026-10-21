-- 2-empresas.sql
-- Pesquisa #1240 (Relacionamentos e Base de clientes). Consulta de producao, versao 2, parte 2 de 5.
-- Empresas: vinculo, backfill por nome e por dominio do e-mail, tabela companies (parte G).
-- Blocos 16 a 21 (6 no total). A numeracao dos blocos e a mesma nas 5 partes e no LEIA-ME.md.
--
-- QUEM RODA: outra sessao, por psql, nas duas instalacoes (Hub2You e Autonom.ia), com usuario de leitura, fora de deploy,
-- depois de conferir no pg_stat_activity que nao ha DDL em andamento. Uma parte por vez, em qualquer ordem.
--   psql "<conexao>" -X -v ON_ERROR_STOP=1 -f 2-empresas.sql > saida-2-<instalacao>.txt 2>&1
-- Precisa ser psql: usa \echo, \set e a variavel :ativas. Nao roda em cliente grafico.
--
-- GARANTIAS (as mesmas nas 5 partes; detalhes e testes no LEIA-ME.md)
--   * Somente leitura: BEGIN TRANSACTION READ ONLY ... ROLLBACK, uma transacao por parte. Nenhum INSERT/UPDATE/DELETE/
--     CREATE, nem tabela temporaria.
--   * Carga: cada bloco tem no maximo 60 s (statement_timeout) e espera no maximo 2 s por trava (lock_timeout). Teto desta
--     parte: 6 x 60 s. Se um bloco passar do limite, o psql para ali (ON_ERROR_STOP) e a transacao e desfeita; o que ja
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

-- Dominio de e-mail (blocos 17 e 18): dominio usado por contatos de pelo menos 3 contas ativas e fora da lista da gem
-- conta como "comum" (provavel e-mail gratuito que o backfill trataria como empresa). Nenhum dominio lido do banco sai.
\set min_contas_dominio 3

-- Lista de e-mail gratuito que o Chatwoot usa para NAO criar empresa (backfill e associacao automatica de Empresas):
-- os 161 hosts de data/providers.json da gem email-provider-info 0.0.1 (Gemfile.lock:284), lidos por
-- EmailProviderInfo.call em enterprise/app/services/companies/business_email_detector_service.rb:15.
-- Copiada sem mudar nada, so para simular o backfill nos blocos 17 e 18.
-- (a linha \set email_gratis_gem vem logo abaixo destas duas listas)

-- E-mail gratuito que a lista da gem NAO tem (blocos 17 e 18). Escritas aqui, conferidas uma a uma contra a lista da gem:
--   email_gratis_fora_da_gem = provedores publicos de e-mail (Brasil e alguns de fora);
--   email_digitado_errado    = erros de digitacao comuns de provedor (gmail.com.br, hotmail.con, bol.com, uol.com...).
-- Sao os unicos dominios que a consulta imprime (bloco 18), e saem daqui, nao do banco.
\set email_gratis_fora_da_gem '{hotmail.com.br,outlook.com.br,live.com,live.com.br,msn.com,terra.com.br,ig.com.br,superig.com.br,globo.com,globomail.com,r7.com,zipmail.com.br,oi.com.br,pop.com.br,ibest.com.br,click21.com.br,aol.com.br,proton.me,mail.com,gmx.net,ymail.com,rocketmail.com,hotmail.es,hotmail.fr,outlook.es,outlook.pt,sapo.pt}'
\set email_digitado_errado '{gmail.com.br,gmail.con,gmail.co,gmial.com,gamil.com,gmai.com,hotmail.con,hotmail.co,hotmal.com,hotmial.com,hotamil.com,outlok.com,outlook.con,bol.com,uol.com}'
\set email_gratis_gem '{123mail.org,150mail.com,150ml.com,16mail.com,2-mail.com,4email.net,50mail.com,airpost.net,allmail.net,aol.com,bestmail.us,bk.ru,bol.com.br,cluemail.com,elitemail.org,emailcorner.net,emailengine.net,emailengine.org,emailgroups.net,emailplus.org,emailuser.net,eml.cc,f-m.fm,fast-email.com,fast-mail.org,fastem.com,fastemail.us,fastemailer.com,fastest.cc,fastimap.com,fastmail.cn,fastmail.co.uk,fastmail.com,fastmail.com.au,fastmail.de,fastmail.es,fastmail.fm,fastmail.fr,fastmail.im,fastmail.in,fastmail.jp,fastmail.mx,fastmail.net,fastmail.nl,fastmail.org,fastmail.se,fastmail.to,fastmail.tw,fastmail.uk,fastmail.us,fastmailbox.net,fastmessaging.com,fea.st,fmail.co.uk,fmailbox.com,fmgirl.com,fmguy.com,ftml.net,gmail.com,gmx.com,gmx.us,googlemail.com,h-mail.us,hailmail.net,hey.com,hotmail.com,icloud.com,imap-mail.com,imap.cc,imapmail.org,inbox.ru,inoutbox.com,internet-e-mail.com,internet-mail.org,internetemails.net,internetmailing.net,jetemail.net,justemail.net,keemail.me,letterboxes.org,list.ru,mac.com,mail-central.com,mail-page.com,mail.ru,mailandftp.com,mailas.com,mailbolt.com,mailc.net,mailcan.com,mailforce.net,mailftp.com,mailhaven.com,mailingaddress.org,mailite.com,mailmight.com,mailnew.com,mailsent.net,mailservice.ms,mailup.net,mailworks.org,me.com,ml1.net,mm.st,myfastmail.com,mymacmail.com,nospammail.net,outlook.com,ownmail.net,petml.com,pm.me,postinbox.com,postpro.net,proinbox.com,promessage.com,protonmail.ch,protonmail.com,realemail.net,reallyfast.biz,reallyfast.info,rushpost.com,sent.as,sent.at,sent.com,speedpost.net,speedymail.org,ssl-mail.com,swift-mail.com,the-fastest.net,the-quickest.com,theinternetemail.com,tuta.io,tutamail.com,tutanota.com,tutanota.de,uol.com.br,veryfast.biz,veryspeedy.net,warpmail.net,xsmail.com,yahoo.ca,yahoo.co.id,yahoo.co.in,yahoo.co.jp,yahoo.co.uk,yahoo.com,yahoo.com.ar,yahoo.com.au,yahoo.com.br,yahoo.com.mx,yahoo.com.sg,yahoo.de,yahoo.es,yahoo.fr,yahoo.in,yahoo.it,yandex.com,yepmail.net,your-mail.com,zoho.com,zohomail.com}'

-- ============================================================================================================
-- PARTE G. EMPRESAS (o recurso e novo e nao teve backfill: aqui se mede o que ja existe e o que daria para trazer)
-- ============================================================================================================

\echo '== 16. Pessoa -> empresa por conta: vinculo com Empresas e potencial de backfill pelo company_name (+ TOTAL) =='
-- com_company_id = contato ligado a uma empresa (contacts.company_id).
-- com_company_name = contato com o texto additional_attributes ->> 'company_name' (campo antigo do Chatwoot, escrito a mao,
--   por importacao ou copiado da empresa ligada). Nenhum nome sai: so contagens.
-- Nome comparado como a importacao compara (CampaignImports::CompanyResolver.normalize_name,
-- app/services/campaign_imports/company_resolver.rb:15-17): NFKD sem acento, minusculas, espacos juntados.
-- Aqui: normalize(NFKD), translate tira U+0300..U+036F, lower, e string_to_array/array_remove junta os espacos (sem regex).
-- nomes_distintos = nomes normalizados distintos na conta.
-- nomes_ja_cadastrados = nomes distintos que ja batem com o nome normalizado de uma empresa da mesma conta.
-- ligaveis_sem_criar_empresa = contatos SEM company_id cujo company_name ja bate com uma empresa cadastrada.
-- empresas_a_criar = nomes distintos sem empresa cadastrada que tem ao menos um contato sem vinculo.
WITH marcas AS (
  SELECT string_agg(chr(c), '') AS m FROM generate_series(768, 879) AS g(c)
),
cn AS (
  SELECT c.account_id, c.company_id,
         nullif(array_to_string(array_remove(string_to_array(translate(lower(translate(normalize(
           CASE WHEN jsonb_typeof(c.additional_attributes) = 'object' THEN c.additional_attributes ->> 'company_name' END, NFKD),
           mk.m, '')), chr(9) || chr(10) || chr(11) || chr(12) || chr(13), '     '), ' '), ''), ' '), '') AS nome_norm
  FROM contacts c
  JOIN :ativas a ON a.account_id = c.account_id
  CROSS JOIN marcas mk
),
emp AS (
  SELECT DISTINCT co.account_id,
         array_to_string(array_remove(string_to_array(translate(lower(translate(normalize(co.name, NFKD), mk.m, '')),
           chr(9) || chr(10) || chr(11) || chr(12) || chr(13), '     '), ' '), ''), ' ') AS nome_norm
  FROM companies co
  JOIN :ativas a ON a.account_id = co.account_id
  CROSS JOIN marcas mk
),
por_nome AS (
  SELECT x.account_id, x.nome_norm, count(*) AS contatos, count(*) FILTER (WHERE x.company_id IS NULL) AS sem_vinculo
  FROM cn x
  WHERE x.nome_norm IS NOT NULL
  GROUP BY x.account_id, x.nome_norm
),
nomes AS (
  SELECT p.account_id,
         count(*) AS nomes_distintos,
         count(*) FILTER (WHERE p.contatos >= 2) AS nomes_com_2_ou_mais_contatos,
         max(p.contatos) AS max_contatos_mesmo_nome,
         count(*) FILTER (WHERE e.nome_norm IS NOT NULL) AS nomes_ja_cadastrados,
         coalesce(sum(p.sem_vinculo) FILTER (WHERE e.nome_norm IS NOT NULL), 0) AS ligaveis_sem_criar_empresa,
         count(*) FILTER (WHERE e.nome_norm IS NULL AND p.sem_vinculo > 0) AS empresas_a_criar
  FROM por_nome p
  LEFT JOIN emp e ON e.account_id = p.account_id AND e.nome_norm = p.nome_norm
  GROUP BY p.account_id
),
pessoas AS (
  SELECT x.account_id,
         count(*) AS contatos,
         count(*) FILTER (WHERE x.company_id IS NOT NULL) AS com_company_id,
         count(*) FILTER (WHERE x.nome_norm IS NOT NULL) AS com_company_name,
         count(*) FILTER (WHERE x.nome_norm IS NOT NULL AND x.company_id IS NULL) AS com_company_name_sem_vinculo
  FROM cn x
  GROUP BY x.account_id
)
SELECT coalesce(p.account_id::text, 'TOTAL') AS account_id,
       sum(p.contatos) AS contatos,
       sum(p.com_company_id) AS com_company_id,
       round(100.0 * sum(p.com_company_id) / nullif(sum(p.contatos), 0), 1) AS pct_com_company_id,
       sum(p.com_company_name) AS com_company_name,
       round(100.0 * sum(p.com_company_name) / nullif(sum(p.contatos), 0), 1) AS pct_com_company_name,
       sum(p.com_company_name_sem_vinculo) AS com_company_name_sem_vinculo,
       coalesce(sum(n.nomes_distintos), 0) AS nomes_distintos,
       coalesce(sum(n.nomes_com_2_ou_mais_contatos), 0) AS nomes_com_2_ou_mais_contatos,
       max(n.max_contatos_mesmo_nome) AS max_contatos_mesmo_nome,
       coalesce(sum(n.nomes_ja_cadastrados), 0) AS nomes_ja_cadastrados,
       coalesce(sum(n.ligaveis_sem_criar_empresa), 0) AS ligaveis_sem_criar_empresa,
       coalesce(sum(n.empresas_a_criar), 0) AS empresas_a_criar
FROM pessoas p
LEFT JOIN nomes n ON n.account_id = p.account_id
GROUP BY ROLLUP (p.account_id)
ORDER BY p.account_id IS NULL, sum(p.com_company_name) DESC, p.account_id;

\echo '== 17. E-mail dos contatos: o que o backfill de Empresas por dominio faria, por conta (+ TOTAL; nenhum e-mail ou dominio sai) =='
-- O codigo ja tem esse backfill: rake companies:backfill (enterprise/lib/tasks/companies.rake:3-11) ->
-- Migration::CompanyAccountBatchJob (enterprise/app/jobs/migration/company_account_batch_job.rb). Para contato com
-- e-mail e sem company_id, pula e-mail gratuito ou descartavel (Companies::BusinessEmailDetectorService) e acha ou cria
-- a empresa pelo dominio do e-mail, em TODAS as contas. A mesma regra ja roda sozinha quando um contato de conta com a
-- flag companies ganha o primeiro e-mail (enterprise/app/models/enterprise/concerns/contact.rb:9-33).
-- dominio = texto depois do ultimo '@' do e-mail, em minusculas (como EmailProviderInfo.call). So conta e-mail com '@'.
-- Classes do contato SEM empresa, nesta ordem (somam com_email_sem_empresa):
--   gratis_lista = dominio na lista da gem: o backfill pula;
--   gratis_fora_da_gem = dominio das listas email_gratis_fora_da_gem ou email_digitado_errado (topo do arquivo): e-mail
--     gratuito que o backfill transformaria em empresa (por dominio: bloco 18);
--   dominio_comum = outro dominio usado em :min_contas_dominio ou mais contas: provavel e-mail gratuito que nenhuma das
--     listas tem; o backfill tambem o transformaria em empresa, ou o ligaria a uma "empresa" desse dominio que ja exista;
--   dominio_ja_cadastrado = uma empresa da conta ja tem esse dominio (e ele nao e comum): o backfill so liga;
--   dominio_proprio = o resto: provavel e-mail corporativo; o backfill cria a empresa.
-- dominios_comuns_distintos / dominios_proprios_distintos = dominios distintos de cada classe na conta (no proprio, e o
-- numero de empresas que o backfill criaria). empresas_ja_criadas_com_dominio_gratis_ou_comum = empresas que ja existem
-- com dominio de uma das tres listas ou comum (provavel efeito da associacao automatica). A checagem de descartavel/invalido
-- (valid_email2) nao e simulada.
WITH em AS (
  SELECT c.account_id, c.company_id, lower(btrim(reverse(split_part(reverse(c.email), '@', 1)))) AS dominio
  FROM contacts c
  JOIN :ativas a ON a.account_id = c.account_id
  WHERE position('@' IN coalesce(c.email, '')) > 0
),
dom AS (
  SELECT e.dominio, count(DISTINCT e.account_id) AS contas
  FROM em e
  GROUP BY e.dominio
),
emp AS (
  SELECT DISTINCT co.account_id, lower(btrim(co.domain)) AS dominio
  FROM companies co
  JOIN :ativas a ON a.account_id = co.account_id
  WHERE coalesce(btrim(co.domain), '') <> ''
),
cls AS (
  SELECT e.account_id, e.dominio,
         CASE
           WHEN e.company_id IS NOT NULL THEN 'com_empresa'
           WHEN e.dominio = ANY (:'email_gratis_gem'::text[]) THEN 'gratis_lista'
           WHEN e.dominio = ANY (:'email_gratis_fora_da_gem'::text[])
             OR e.dominio = ANY (:'email_digitado_errado'::text[]) THEN 'gratis_fora'
           WHEN d.contas >= :min_contas_dominio THEN 'comum'
           WHEN p.dominio IS NOT NULL THEN 'ja_cadastrado'
           ELSE 'proprio'
         END AS classe
  FROM em e
  JOIN dom d ON d.dominio = e.dominio
  LEFT JOIN emp p ON p.account_id = e.account_id AND p.dominio = e.dominio
),
por_conta AS (
  SELECT k.account_id,
         count(*) AS com_email,
         count(*) FILTER (WHERE k.classe <> 'com_empresa') AS com_email_sem_empresa,
         count(*) FILTER (WHERE k.classe = 'gratis_lista') AS gratis_lista,
         count(*) FILTER (WHERE k.classe = 'gratis_fora') AS gratis_fora_da_gem,
         count(*) FILTER (WHERE k.classe = 'ja_cadastrado') AS dominio_ja_cadastrado,
         count(*) FILTER (WHERE k.classe = 'comum') AS dominio_comum,
         count(*) FILTER (WHERE k.classe = 'proprio') AS dominio_proprio,
         count(DISTINCT k.dominio) FILTER (WHERE k.classe = 'comum') AS dominios_comuns_distintos,
         count(DISTINCT k.dominio) FILTER (WHERE k.classe = 'proprio') AS dominios_proprios_distintos
  FROM cls k
  GROUP BY k.account_id
),
proprios AS (
  SELECT g.account_id, count(*) AS dominios_proprios_com_2_ou_mais
  FROM (SELECT k.account_id, k.dominio FROM cls k WHERE k.classe = 'proprio'
        GROUP BY k.account_id, k.dominio HAVING count(*) >= 2) g
  GROUP BY g.account_id
),
lixo AS (
  SELECT co.account_id, count(*) AS empresas
  FROM companies co
  JOIN :ativas a ON a.account_id = co.account_id
  LEFT JOIN dom d ON d.dominio = lower(btrim(co.domain))
  WHERE coalesce(btrim(co.domain), '') <> ''
    AND (lower(btrim(co.domain)) = ANY (:'email_gratis_gem'::text[])
         OR lower(btrim(co.domain)) = ANY (:'email_gratis_fora_da_gem'::text[])
         OR lower(btrim(co.domain)) = ANY (:'email_digitado_errado'::text[])
         OR d.contas >= :min_contas_dominio)
  GROUP BY co.account_id
)
SELECT coalesce(a.account_id::text, 'TOTAL') AS account_id,
       coalesce(sum(p.com_email), 0) AS com_email,
       coalesce(sum(p.com_email_sem_empresa), 0) AS com_email_sem_empresa,
       coalesce(sum(p.gratis_lista), 0) AS gratis_lista,
       coalesce(sum(p.gratis_fora_da_gem), 0) AS gratis_fora_da_gem,
       coalesce(sum(p.dominio_ja_cadastrado), 0) AS dominio_ja_cadastrado,
       coalesce(sum(p.dominio_comum), 0) AS dominio_comum,
       coalesce(sum(p.dominio_proprio), 0) AS dominio_proprio,
       coalesce(sum(p.dominios_comuns_distintos), 0) AS dominios_comuns_distintos,
       coalesce(sum(p.dominios_proprios_distintos), 0) AS dominios_proprios_distintos,
       coalesce(sum(r.dominios_proprios_com_2_ou_mais), 0) AS dominios_proprios_com_2_ou_mais,
       coalesce(sum(l.empresas), 0) AS empresas_ja_criadas_com_dominio_gratis_ou_comum
FROM :ativas a
LEFT JOIN por_conta p ON p.account_id = a.account_id
LEFT JOIN proprios r ON r.account_id = a.account_id
LEFT JOIN lixo l ON l.account_id = a.account_id
WHERE p.account_id IS NOT NULL OR l.account_id IS NOT NULL
GROUP BY ROLLUP (a.account_id)
ORDER BY a.account_id IS NULL, coalesce(sum(p.com_email), 0) DESC, a.account_id;

\echo '== 18. E-mail gratuito que a lista do backfill NAO tem: contatos e empresas por dominio das listas do topo (nenhum dominio lido do banco sai) =='
-- Versao 2 (auditoria da Orquestracao): saiu a lista de dominios lidos do banco. Um dominio pessoal
-- (nome-sobrenome.com.br) sairia se a pessoa fosse contato em varias contas.
-- Uma linha por dominio das listas email_gratis_fora_da_gem (tipo provedor) e email_digitado_errado (tipo digitacao),
-- escritas no topo do arquivo: o texto da coluna dominio sai da lista, nunca do banco. Dominio que nenhum contato usa sai
-- com zero. na_lista_da_gem confere que a gem nao tem o dominio (tem de dar f em todas).
-- Linhas de resumo (so contagem, nenhum dominio):
--   (outros comuns) = dominios usados em :min_contas_dominio ou mais contas, fora da gem e fora das duas listas. Se for
--     alto, as listas nao cobrem todo e-mail gratuito real;
--   (lista da gem) = dominios que o backfill ja pula, para comparar o tamanho.
-- empresas / contas_com_empresa = empresas que ja existem com o dominio (provavel efeito da associacao automatica).
WITH lista AS (
  SELECT 'provedor' AS tipo, x.dominio, 1 AS ordem FROM unnest(:'email_gratis_fora_da_gem'::text[]) AS x(dominio)
  UNION ALL
  SELECT 'digitacao', x.dominio, 2 FROM unnest(:'email_digitado_errado'::text[]) AS x(dominio)
),
rotulos AS (
  SELECT l.tipo, l.dominio AS rotulo, l.ordem FROM lista l
  UNION ALL SELECT 'resumo', '(outros comuns)', 3
  UNION ALL SELECT 'resumo', '(lista da gem)', 4
),
em AS (
  SELECT c.account_id, c.company_id, lower(btrim(reverse(split_part(reverse(c.email), '@', 1)))) AS dominio
  FROM contacts c
  JOIN :ativas a ON a.account_id = c.account_id
  WHERE position('@' IN coalesce(c.email, '')) > 0
),
dom AS (
  SELECT e.dominio, count(DISTINCT e.account_id) AS contas
  FROM em e
  GROUP BY e.dominio
),
contatos_cls AS (
  SELECT CASE WHEN l.dominio IS NOT NULL THEN l.dominio
              WHEN e.dominio = ANY (:'email_gratis_gem'::text[]) THEN '(lista da gem)'
              WHEN d.contas >= :min_contas_dominio THEN '(outros comuns)'
         END AS rotulo,
         e.account_id, e.company_id, e.dominio
  FROM em e
  JOIN dom d ON d.dominio = e.dominio
  LEFT JOIN lista l ON l.dominio = e.dominio
),
empresas_cls AS (
  SELECT CASE WHEN l.dominio IS NOT NULL THEN l.dominio
              WHEN x.dominio = ANY (:'email_gratis_gem'::text[]) THEN '(lista da gem)'
              WHEN d.contas >= :min_contas_dominio THEN '(outros comuns)'
         END AS rotulo,
         x.account_id
  FROM (SELECT co.account_id, lower(btrim(co.domain)) AS dominio
        FROM companies co
        JOIN :ativas a ON a.account_id = co.account_id
        WHERE coalesce(btrim(co.domain), '') <> '') x
  LEFT JOIN dom d ON d.dominio = x.dominio
  LEFT JOIN lista l ON l.dominio = x.dominio
),
c AS (
  SELECT k.rotulo, count(DISTINCT k.dominio) AS dominios, count(DISTINCT k.account_id) AS contas, count(*) AS contatos,
         count(*) FILTER (WHERE k.company_id IS NULL) AS contatos_sem_empresa
  FROM contatos_cls k
  WHERE k.rotulo IS NOT NULL
  GROUP BY k.rotulo
),
p AS (
  SELECT k.rotulo, count(*) AS empresas, count(DISTINCT k.account_id) AS contas_com_empresa
  FROM empresas_cls k
  WHERE k.rotulo IS NOT NULL
  GROUP BY k.rotulo
)
SELECT r.tipo,
       r.rotulo AS dominio,
       CASE WHEN r.ordem <= 2 THEN r.rotulo = ANY (:'email_gratis_gem'::text[]) END AS na_lista_da_gem,
       coalesce(c.dominios, 0) AS dominios_distintos,
       coalesce(c.contas, 0) AS contas,
       coalesce(c.contatos, 0) AS contatos,
       coalesce(c.contatos_sem_empresa, 0) AS contatos_sem_empresa,
       coalesce(p.empresas, 0) AS empresas,
       coalesce(p.contas_com_empresa, 0) AS contas_com_empresa
FROM rotulos r
LEFT JOIN c ON c.rotulo = r.rotulo
LEFT JOIN p ON p.rotulo = r.rotulo
ORDER BY r.ordem, coalesce(c.contatos, 0) DESC, r.rotulo;

\echo '== 19. Empresas (tabela companies) por conta: preenchimento, vinculo real e contador (+ TOTAL) =='
-- com_contato_ligado / contatos_ligados = vinculo real (contacts.company_id), nao o contador.
-- contador_divergente = empresas cujo contacts_count (counter_cache, enterprise/app/models/enterprise/concerns/contact.rb:6)
--   nao bate com o numero real de contatos ligados: sinal de escrita que pulou o callback (o backfill por e-mail usa
--   update_column, enterprise/app/jobs/migration/company_account_batch_job.rb:20).
-- de_prospeccao = criada pela Prospeccao (additional_attributes ->> 'source' = 'autonomia_prospecting',
--   app/services/autonomia/prospecting/company_upserter.rb:17,149).
-- so_nome_e_dominio = so nome e dominio, sem descricao nem atributos: o formato da empresa criada pela associacao
--   automatica por e-mail ou pelo backfill (enterprise/app/services/contacts/company_association_service.rb:33-35).
WITH vin AS (
  SELECT c.company_id, count(*) AS n
  FROM contacts c
  JOIN :ativas a ON a.account_id = c.account_id
  WHERE c.company_id IS NOT NULL
  GROUP BY c.company_id
),
emp AS (
  SELECT co.account_id, co.contacts_count, coalesce(v.n, 0) AS ligados, co.created_at,
         nullif(btrim(co.domain), '') IS NOT NULL AS tem_dominio,
         nullif(btrim(co.description), '') IS NOT NULL AS tem_descricao,
         (jsonb_typeof(co.additional_attributes) = 'object'
          AND nullif(btrim(co.additional_attributes ->> 'cnpj'), '') IS NOT NULL) AS tem_cnpj,
         (jsonb_typeof(co.custom_attributes) = 'object' AND co.custom_attributes <> '{}'::jsonb) AS tem_custom,
         (jsonb_typeof(co.additional_attributes) = 'object' AND co.additional_attributes <> '{}'::jsonb) AS tem_additional,
         (jsonb_typeof(co.additional_attributes) = 'object'
          AND co.additional_attributes ->> 'source' = 'autonomia_prospecting') AS de_prospeccao,
         (nullif(btrim(co.domain), '') IS NOT NULL AND nullif(btrim(co.description), '') IS NULL
          AND coalesce(co.additional_attributes, '{}'::jsonb) IN ('{}'::jsonb, 'null'::jsonb)
          AND coalesce(co.custom_attributes, '{}'::jsonb) IN ('{}'::jsonb, 'null'::jsonb)) AS so_nome_e_dominio
  FROM companies co
  JOIN :ativas a ON a.account_id = co.account_id
  LEFT JOIN vin v ON v.company_id = co.id
)
SELECT coalesce(e.account_id::text, 'TOTAL') AS account_id,
       count(*) AS empresas,
       count(*) FILTER (WHERE e.tem_dominio) AS com_dominio,
       count(*) FILTER (WHERE e.tem_cnpj) AS com_cnpj,
       count(*) FILTER (WHERE e.tem_descricao) AS com_descricao,
       count(*) FILTER (WHERE e.tem_custom) AS com_custom_attributes,
       count(*) FILTER (WHERE e.tem_additional) AS com_additional_attributes,
       count(*) FILTER (WHERE e.ligados > 0) AS com_contato_ligado,
       count(*) FILTER (WHERE e.ligados = 0) AS sem_contato,
       sum(e.ligados) AS contatos_ligados,
       percentile_disc(0.5) WITHIN GROUP (ORDER BY e.ligados) AS contatos_por_empresa_p50,
       max(e.ligados) AS contatos_por_empresa_max,
       count(*) FILTER (WHERE e.contacts_count <> e.ligados) AS contador_divergente,
       count(*) FILTER (WHERE e.de_prospeccao) AS de_prospeccao,
       count(*) FILTER (WHERE e.so_nome_e_dominio) AS so_nome_e_dominio,
       to_char(min(e.created_at), 'YYYY-MM') AS primeira_criada,
       to_char(max(e.created_at), 'YYYY-MM') AS ultima_criada
FROM emp e
GROUP BY ROLLUP (e.account_id)
ORDER BY e.account_id IS NULL, count(*) DESC, e.account_id;

\echo '== 20. Empresas criadas por mes (+ TOTAL) =='
SELECT coalesce(to_char(date_trunc('month', co.created_at), 'YYYY-MM'), 'TOTAL') AS mes,
       count(*) AS empresas_criadas,
       count(DISTINCT co.account_id) AS contas
FROM companies co
JOIN :ativas a ON a.account_id = co.account_id
GROUP BY ROLLUP (date_trunc('month', co.created_at))
ORDER BY date_trunc('month', co.created_at) NULLS LAST;

\echo '== 21. Empresas: chaves preenchidas em additional_attributes e custom_attributes (REGRA DO TEXTO; nenhum valor) =='
-- empresas_com_valor = empresas com a chave preenchida; na linha (oculto), soma de todas as chaves ocultas da coluna.
WITH k AS (
  SELECT 'additional_attributes' AS coluna, co.account_id, lower(btrim(e.key)) AS chave
  FROM companies co
  JOIN :ativas a ON a.account_id = co.account_id
  CROSS JOIN LATERAL jsonb_each(CASE WHEN jsonb_typeof(co.additional_attributes) = 'object'
                                     THEN co.additional_attributes ELSE '{}'::jsonb END) e
  WHERE e.value NOT IN ('null'::jsonb, '""'::jsonb, '[]'::jsonb, '{}'::jsonb)
  UNION ALL
  SELECT 'custom_attributes', co.account_id, lower(btrim(e.key))
  FROM companies co
  JOIN :ativas a ON a.account_id = co.account_id
  CROSS JOIN LATERAL jsonb_each(CASE WHEN jsonb_typeof(co.custom_attributes) = 'object'
                                     THEN co.custom_attributes ELSE '{}'::jsonb END) e
  WHERE e.value NOT IN ('null'::jsonb, '""'::jsonb, '[]'::jsonb, '{}'::jsonb)
),
vis AS (
  SELECT k.coluna, k.chave,
         count(DISTINCT k.account_id) >= :min_contas
         AND position('@' IN k.chave) = 0
         AND length(k.chave) - length(translate(k.chave, '0123456789', '')) < 6 AS visivel
  FROM k
  GROUP BY k.coluna, k.chave
)
SELECT k.coluna,
       CASE WHEN v.visivel THEN left(k.chave, 60) ELSE '(oculto)' END AS chave,
       count(DISTINCT k.chave) AS chaves,
       count(DISTINCT k.account_id) AS contas,
       count(*) AS empresas_com_valor
FROM k
JOIN vis v ON v.coluna = k.coluna AND v.chave = k.chave
GROUP BY 1, 2
ORDER BY 1, bool_and(NOT v.visivel), empresas_com_valor DESC, 2;


\echo '== FIM da parte 2: todos os blocos rodaram. A transacao e desfeita a seguir (ROLLBACK). =='
ROLLBACK;
