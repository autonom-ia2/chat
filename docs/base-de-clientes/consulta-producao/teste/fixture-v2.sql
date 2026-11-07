-- Teste da versao 2: fixture-dados.sql + contatos com e-mail em 3 contas + extras da v2, e roda a parte
-- passada em -v parte=<arquivo>. Tudo numa transacao, desfeita pelo ROLLBACK da propria parte.
-- Extras da v2: contas ativas 990004 e 990005, para exercitar as regras de 3 contas (positivo e negativo).
\ir fixture-dados.sql
INSERT INTO accounts (id, name, created_at, updated_at, status) VALUES (990004, 'PIICONTA D', now(), now(), 0);
INSERT INTO companies (id, name, domain, account_id, created_at, updated_at) VALUES
 (990204, 'PIIEMPRESA Gmail', 'gmail.com', 990001, now(), now()),
 (990205, 'PIIEMPRESA Hotmail', 'hotmail.com.br', 990004, now(), now());
INSERT INTO contacts (id, account_id, name, email, created_at, updated_at) VALUES
 (990131, 990001, 'PIINOME Sete', 'pii7@hotmail.com.br', now(), now()),
 (990132, 990001, 'PIINOME Oito', 'pii8@gmail.com', now(), now()),
 (990133, 990001, 'PIINOME Nove', 'pii9@acme-pii.com.br', now(), now()),
 (990134, 990001, 'PIINOME Dez', 'pii10@acme-pii.com.br', now(), now()),
 (990135, 990001, 'PIINOME Onze', 'pii11@pii-alfa.com.br', now(), now()),
 (990136, 990001, 'PIINOME Doze', 'PIISEMARROBA', now(), now()),
 (990141, 990002, 'PIINOME B3', 'piib3@hotmail.com.br', now(), now()),
 (990142, 990002, 'PIINOME B4', 'piib4@gmail.com', now(), now()),
 (990151, 990004, 'PIINOME D1', 'piid1@hotmail.com.br', now(), now()),
 (990152, 990004, 'PIINOME D2', 'piid2@gmail.com', now(), now());
INSERT INTO companies (id, name, domain, account_id, created_at, updated_at, additional_attributes) VALUES
 (990206, 'corretora sao paulo', NULL, 990001, now(), now(), '{}'),
 (990207, 'PIIEMPRESA Prospec', NULL, 990001, now(), now(), '{"source":"autonomia_prospecting","cnpj":"11222333000181"}');
INSERT INTO contacts (id, account_id, name, additional_attributes, created_at, updated_at) VALUES
 (990137, 990001, 'PIINOME Treze', '{"company_name":"  Corretora  São   Paulo "}', now(), now());

-- (1) dominio pessoal em 3 contas: nunca pode sair (cai na contagem "(outros comuns)"); (2) erro de digitacao da lista.
INSERT INTO accounts (id, name, created_at, updated_at, status) VALUES (990005, 'PIICONTA E', now(), now(), 0);
INSERT INTO inboxes (id, channel_id, account_id, name, channel_type, created_at, updated_at) VALUES
 (990305, 5, 990004, 'PIICAIXA wa d', 'Channel::Whatsapp', now(), now());
INSERT INTO contacts (id, account_id, name, email, last_activity_at, additional_attributes, custom_attributes, created_at, updated_at) VALUES
 (990161, 990001, 'PIINOME P1', 'pii-p1@paulo-pii-silva.com.br', NULL, '{}', '{}', now(), now()),
 (990162, 990002, 'PIINOME P2', 'pii-p2@paulo-pii-silva.com.br', NULL, '{}', '{}', now(), now()),
 (990163, 990004, 'PIINOME P3', 'pii-p3@paulo-pii-silva.com.br', NULL,
  '{"city":"PIICIDADED","company_name":""}', '{"cpf":"PIIVALORD"}', now(), now()),
 (990164, 990002, 'PIINOME Typo', 'piix@gmail.com.br', NULL, '{}', '{}', now(), now()),
 (990165, 990004, 'PIINOME D5', NULL, now() - interval '5 days', '{}', '{}', now(), now()),
 (990166, 990004, 'PIINOME D6', NULL, now() - interval '20 days', '{}', '{}', now(), now());

-- (10) bloco 52: 990166 escreveu ha 3 dias, mas o campo diz 20 dias (atrasado); 990165 tem campo sem mensagem.
INSERT INTO conversations (id, account_id, inbox_id, contact_id, created_at, updated_at, last_activity_at) VALUES
 (990507, 990004, 990305, 990166, now() - interval '3 days', now(), now() - interval '3 days');
INSERT INTO messages (id, content, account_id, inbox_id, conversation_id, message_type, sender_type, sender_id, created_at, updated_at) VALUES
 (990607, 'PIICONTEUDO7 99999-1234', 990004, 990305, 990507, 0, 'Contact', 990166, now() - interval '3 days', now());

-- (4) card: apolice com valor em 3 contas (visivel); renovacao definida em 3 contas, com valor em 1 (oculta).
-- (8) origem: tipo de canal.
INSERT INTO crm_pipelines (id, account_id, name, status, counts_as_sale, created_at, updated_at) VALUES
 (990703, 990004, 'PIIFUNIL D', 0, true, now(), now());
INSERT INTO crm_pipeline_stages (id, account_id, pipeline_id, name, is_won_stage, created_at, updated_at) VALUES
 (990741, 990004, 990703, 'PIIETAPA d', false, now(), now());
INSERT INTO crm_cards (id, account_id, pipeline_id, stage_id, contact_id, conversation_id, title, status, source, custom_attributes,
                       created_at, updated_at) VALUES
 (990805, 990004, 990703, 990741, 990163, NULL, 'PIICARD5', 0, 'Channel::Whatsapp', '{"apolice":"PIIAPOLICED"}', now(), now()),
 (990806, 990001, 990701, 990712, 990101, NULL, 'PIICARD6', 0, 'contact_request', '{"renovacao":"PIIRENOV"}', now(), now());
INSERT INTO custom_attribute_definitions (id, account_id, attribute_model, attribute_key, attribute_display_name, attribute_display_type,
                                          attribute_description, created_at, updated_at) VALUES
 (990931, 990001, 3, 'renovacao', 'Renovação', 5, NULL, now(), now()),
 (990932, 990002, 3, 'renovacao', 'Renovação', 5, NULL, now(), now()),
 (990933, 990004, 3, 'renovacao', 'Renovação', 5, NULL, now(), now()),
 (990934, 990004, 3, 'apolice', 'Apólice', 0, NULL, now(), now()),
 (990935, 990004, 1, 'cpf', 'CPF', 0, NULL, now(), now()),
 (990936, 990004, 1, 'segmento', 'Segmento', 6, NULL, now(), now());

-- (7) etiqueta "cliente" em 3 contas: so contagem.
INSERT INTO labels (id, account_id, title, created_at, updated_at) VALUES
 (991005, 990004, 'cliente', now(), now());

-- (3) planilhas: cidade e nome em 3 contas (visiveis); telefone e plano em 2 (ocultos); a mesma planilha reimportada
-- com uma coluna a mais na 990004 (conta uma vez); linha de dado lida como titulo em 3 contas, com telefone -> suspeita.
INSERT INTO campaign_imports (id, account_id, user_id, status, total_rows, valid_rows, options, extra_columns, schema_resolution, created_at, updated_at) VALUES
 (991303, 990004, 612, 7, 5, 5, '{"flow":"contacts"}', '["Cidade","Plano"]',
  '{"method":"jev","header_row":1,"columns":[{"index":0,"header":"nome"},{"index":1,"header":"telefone"},{"index":2,"header":"Cidade"},{"index":3,"header":"Plano"}],"targets":{"name":{"column":0,"header":"nome"},"phone":{"column":1,"header":"telefone"}}}',
  now(), now()),
 (991304, 990004, 612, 7, 5, 5, '{"flow":"contacts"}', '["Cidade","Plano","Observacao PII"]',
  '{"method":"jev","header_row":1,"columns":[{"index":0,"header":"nome"},{"index":1,"header":"telefone"},{"index":2,"header":"Cidade"},{"index":3,"header":"Plano"},{"index":4,"header":"Observacao PII"}],"targets":{"name":{"column":0,"header":"nome"},"phone":{"column":1,"header":"telefone"}}}',
  now(), now()),
 (991305, 990005, 612, 7, 5, 5, '{"flow":"audience"}', '["cidade","plano"]',
  '{"method":"jev","header_row":1,"columns":[{"index":0,"header":"Nome"},{"index":1,"header":"Celular"},{"index":2,"header":"cidade"},{"index":3,"header":"plano"}],"targets":{"name":{"column":0,"header":"Nome"},"phone":{"column":1,"header":"Celular"}}}',
  now(), now()),
 (991306, 990002, 612, 7, 5, 5, '{"flow":"contacts"}', '["Rua PII 123"]',
  '{"method":"jev","header_row":1,"columns":[{"index":0,"header":"Maria PII Souza"},{"index":1,"header":"+55 11 98888-7777"},{"index":2,"header":"Rua PII 123"}],"targets":{"name":{"column":0,"header":"Maria PII Souza"},"phone":{"column":1,"header":"+55 11 98888-7777"}}}',
  now(), now()),
 (991307, 990004, 612, 7, 5, 5, '{"flow":"contacts"}', '["Rua PII 123"]',
  '{"method":"jev","header_row":1,"columns":[{"index":0,"header":"Maria PII Souza"},{"index":1,"header":"+55 11 98888-7777"},{"index":2,"header":"Rua PII 123"}],"targets":{"name":{"column":0,"header":"Maria PII Souza"},"phone":{"column":1,"header":"+55 11 98888-7777"}}}',
  now(), now()),
 (991308, 990005, 612, 7, 5, 5, '{"flow":"contacts"}', '["Rua PII 123"]',
  '{"method":"jev","header_row":1,"columns":[{"index":0,"header":"Maria PII Souza"},{"index":1,"header":"+55 11 98888-7777"},{"index":2,"header":"Rua PII 123"}],"targets":{"name":{"column":0,"header":"Maria PII Souza"},"phone":{"column":1,"header":"+55 11 98888-7777"}}}',
  now(), now());

-- (9) e-mail: cidade em 3 contas (visivel), bairro em 2 (oculto); a campanha 991401 tem chave com @ (suspeita).
INSERT INTO email_campaigns (id, account_id, name, created_at, updated_at) VALUES
 (991403, 990004, 'PIICAMPANHA D', now(), now()),
 (991404, 990005, 'PIICAMPANHA E', now(), now());
INSERT INTO email_campaign_recipients (id, email_campaign_id, name, email, custom_data, created_at, updated_at) VALUES
 (991423, 991403, 'PIIDEST D', 'pii-dest-d@exemplo.com', '{"cidade":"PIICIDADED","plano":"PIIPLANO"}', now(), now()),
 (991424, 991404, 'PIIDEST E', 'pii-dest-e@exemplo.com', '{"cidade":"PIICIDADEE","bairro":"PIIBAIRROE"}', now(), now());

-- Rodada 2 da auditoria: (11) campanha de e-mail com UMA chave so, nome de pessoa, em 3 contas -> nao e "boa", nao sai;
-- (12) origem de card com cara de classe de canal, fora da lista fechada -> (outro).
INSERT INTO email_campaigns (id, account_id, name, created_at, updated_at) VALUES
 (991405, 990002, 'PIICAMPANHA F', now(), now()),
 (991406, 990004, 'PIICAMPANHA G', now(), now()),
 (991407, 990005, 'PIICAMPANHA H', now(), now());
INSERT INTO email_campaign_recipients (id, email_campaign_id, name, email, custom_data, created_at, updated_at) VALUES
 (991425, 991405, 'PIIDEST F', 'pii-dest-f@exemplo.com', '{"ana pii costa":"PIIVALORF"}', now(), now()),
 (991426, 991406, 'PIIDEST G', 'pii-dest-g@exemplo.com', '{"ana pii costa":"PIIVALORG"}', now(), now()),
 (991427, 991407, 'PIIDEST H', 'pii-dest-h@exemplo.com', '{"ana pii costa":"PIIVALORH"}', now(), now());
INSERT INTO crm_cards (id, account_id, pipeline_id, stage_id, contact_id, title, status, source, custom_attributes, created_at, updated_at) VALUES
 (990807, 990004, 990703, 990741, 990163, 'PIICARD7', 0, 'Channel::PIIFulano', '{}', now(), now());

\echo '== FIXTURE V2 CARREGADA =='
\i :parte
