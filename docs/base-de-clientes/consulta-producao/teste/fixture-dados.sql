-- Teste da consulta com dados sinteticos. Tudo dentro de UMA transacao que termina no ROLLBACK da propria consulta.
-- Todo texto de pessoa leva a marca PII / pii / exemplo / numeros longos, para conferir que nada disso sai.
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO accounts (id, name, created_at, updated_at, status, feature_flags, feature_flags_ext_1) VALUES
 (990001, 'PIICONTA A', now(), now(), 0, (1::bigint << 23) | (1::bigint << 49) | (1::bigint << 57), (1::bigint << 9) | (1::bigint << 15)),
 (990002, 'PIICONTA B', now(), now(), 0, 0, 0),
 (990003, 'PIICONTA C', now(), now(), 1, 0, 0);

INSERT INTO companies (id, name, domain, description, account_id, created_at, updated_at, contacts_count, additional_attributes, custom_attributes) VALUES
 (990201, 'PIIEMPRESA Alfa', 'pii-alfa.com.br', 'PIIDESCRICAO', 990001, now() - interval '40 days', now(), 5, '{"cnpj":"12345678000199"}', '{"porte":"PIIPORTE"}'),
 (990202, 'PIIEMPRESA Gama', NULL, NULL, 990001, now(), now(), 0, '{}', '{}'),
 (990203, 'PIIEMPRESA Delta', NULL, NULL, 990002, now(), now(), 0, '{"cnpj":"98765432000155"}', '{"porte":"PIIPORTEB"}');

INSERT INTO contacts (id, account_id, name, email, phone_number, identifier, contact_type, customer_since, last_activity_at, company_id,
                      additional_attributes, custom_attributes, blocked, opted_out_at, opt_out_source, opted_out_by_id, created_at, updated_at) VALUES
 (990101, 990001, 'PIINOME Um', 'pii1@exemplo.com', '+5511912345678', 'PIIIDENT1', 2, now() - interval '200 days', now() - interval '10 days', 990201,
  '{"company_name":"PIIEMPRESA Alfa","city":"PIICIDADE","social_profiles":{"linkedin":"PIIREDE1","twitter":""}}',
  '{"cpf":"PIIVALOR1","segmento":"PIIVALOR2","waha_whatsapp_jid":"PIIJID1","5511987654321":"PIIVALOR3","joao_luca_pii":"PIIVALOR4","vazio":""}',
  false, NULL, NULL, NULL, now() - interval '20 days', now()),
 (990102, 990001, 'PIINOME Dois', NULL, '+551112345678', NULL, 1, NULL, NULL, NULL,
  '{"company_name":" piiempresa alfa "}', '{}', false, NULL, NULL, NULL, now() - interval '3 days', now()),
 (990103, 990001, 'PIINOME Tres', 'pii3@exemplo.com', '+5511912345678', NULL, 0, NULL, now() - interval '400 days', NULL,
  '{"company_name":"PIIEMPRESA Beta"}', '{}', false, now() - interval '5 days', 'manual', 612, now() - interval '400 days', now()),
 (990104, 990001, 'PIINOME Quatro', NULL, '+1 202 555 0123', NULL, 0, NULL, NULL, NULL,
  '[]', '"PIILIXO"', false, NULL, NULL, NULL, now() - interval '3 days', now()),
 (990105, 990001, 'PIINOME Cinco', NULL, NULL, NULL, 2, NULL, NULL, NULL,
  '{}', '{}', true, NULL, 'PIIORIGEM', NULL, now() - interval '3 days', now()),
 (990106, 990001, 'PIINOME Seis', NULL, 'ramal PII 12', NULL, 0, now() - interval '30 days', NULL, NULL,
  '{}', '{}', false, NULL, NULL, NULL, now() - interval '40 days', now()),
 (990111, 990002, 'PIINOME B1', 'piib1@exemplo.com', '+5521999998888', NULL, 2, now() - interval '10 days', now() - interval '40 days', 990203,
  '{"city":"PIICIDADEB","company_name":"PIIEMPRESA Delta","social_profiles":{"linkedin":"PIIREDEB"}}',
  '{"cpf":"PIIVALORB","segmento":"PIIVALORB2","waha_whatsapp_jid":"PIIJIDB"}', false, NULL, NULL, NULL, now() - interval '60 days', now()),
 (990112, 990002, 'PIINOME B2', NULL, '+552199998888', NULL, 0, NULL, NULL, NULL,
  '{}', '{}', false, NULL, NULL, NULL, now() - interval '60 days', now()),
 (990121, 990003, 'PIINOME C', 'piic@exemplo.com', '+5531988887777', NULL, 2, now(), now(), NULL,
  '{"company_name":"PIIEMPRESA C"}', '{"cpf":"PIIVALORC"}', false, NULL, NULL, NULL, now(), now());

INSERT INTO inboxes (id, channel_id, account_id, name, channel_type, created_at, updated_at) VALUES
 (990301, 1, 990001, 'PIICAIXA wa', 'Channel::Whatsapp', now(), now()),
 (990302, 2, 990001, 'PIICAIXA api', 'Channel::Api', now(), now()),
 (990303, 3, 990002, 'PIICAIXA wa b', 'Channel::Whatsapp', now(), now()),
 (990304, 4, 990003, 'PIICAIXA wa c', 'Channel::Whatsapp', now(), now());

INSERT INTO contact_inboxes (id, contact_id, inbox_id, source_id, created_at, updated_at) VALUES
 (990401, 990101, 990301, 'PIISOURCE1', now(), now()),
 (990402, 990101, 990302, 'PIISOURCE2', now(), now()),
 (990403, 990111, 990303, 'PIISOURCE3', now(), now()),
 (990404, 990103, 990301, 'PIISOURCE4', now(), now()),
 (990405, 990121, 990304, 'PIISOURCE5', now(), now());

INSERT INTO conversations (id, account_id, inbox_id, contact_id, created_at, updated_at, last_activity_at) VALUES
 (990501, 990001, 990301, 990101, now() - interval '10 days', now(), now() - interval '10 days'),
 (990502, 990001, 990302, 990101, now() - interval '100 days', now(), now() - interval '100 days'),
 (990503, 990001, 990301, 990103, now() - interval '400 days', now(), now() - interval '400 days'),
 (990504, 990002, 990303, 990111, now() - interval '40 days', now(), now() - interval '40 days'),
 (990505, 990001, 990301, 990102, now() - interval '2 days', now(), now() - interval '2 days'),
 (990506, 990003, 990304, 990121, now(), now(), now());

INSERT INTO messages (id, content, account_id, inbox_id, conversation_id, message_type, sender_type, sender_id, created_at, updated_at) VALUES
 (990601, 'PIICONTEUDO1 meu cpf 12345678900', 990001, 990301, 990501, 0, 'Contact', 990101, now() - interval '10 days', now()),
 (990602, 'PIICONTEUDO2', 990001, 990301, 990501, 1, 'User', 612, now() - interval '9 days', now()),
 (990603, 'PIICONTEUDO3', 990001, 990301, 990503, 0, 'Contact', 990103, now() - interval '400 days', now()),
 (990604, 'PIICONTEUDO4', 990002, 990303, 990504, 0, 'Contact', 990111, now() - interval '40 days', now()),
 (990605, 'PIICONTEUDO5', 990001, 990301, 990505, 0, 'Contact', 990102, now() - interval '2 days', now()),
 (990606, 'PIICONTEUDO6', 990003, 990304, 990506, 0, 'Contact', 990121, now(), now());

INSERT INTO crm_pipelines (id, account_id, name, status, counts_as_sale, created_at, updated_at) VALUES
 (990701, 990001, 'PIIFUNIL A', 0, true, now(), now()),
 (990702, 990002, 'PIIFUNIL B', 0, true, now(), now());
INSERT INTO crm_pipeline_stages (id, account_id, pipeline_id, name, is_won_stage, created_at, updated_at) VALUES
 (990711, 990001, 990701, 'PIIETAPA ganho', true, now(), now()),
 (990712, 990001, 990701, 'PIIETAPA aberta', false, now(), now()),
 (990721, 990002, 990702, 'PIIETAPA b', false, now(), now());
INSERT INTO crm_pipeline_inboxes (id, account_id, pipeline_id, inbox_id, auto_create_card, created_at, updated_at) VALUES
 (990731, 990001, 990701, 990301, true, now(), now());
INSERT INTO crm_cards (id, account_id, pipeline_id, stage_id, contact_id, conversation_id, title, description, value_cents, status, lost_reason,
                       source, external_id, custom_attributes, last_activity_at, created_at, updated_at) VALUES
 (990801, 990001, 990701, 990711, 990101, 990501, 'PIICARD1', 'PIIDESC1', 10000, 1, NULL, 'public_link', 'PIIEXT1', '{"apolice":"PIIAPOLICE"}', now(), now(), now()),
 (990802, 990001, 990701, 990712, 990101, NULL, 'PIICARD2', NULL, 0, 0, 'PIIMOTIVO', 'vendedor PIIVEND', NULL, '{}', now() - interval '100 days', now() - interval '100 days', now()),
 (990803, 990001, 990701, 990711, 990106, NULL, 'PIICARD3', NULL, 0, 1, NULL, NULL, NULL, '{}', now(), now(), now()),
 (990804, 990002, 990702, 990721, 990111, 990504, 'PIICARD4', NULL, 0, 0, NULL, 'public_link', NULL, '{"apolice":"PIIAPOLICEB"}', NULL, now(), now());

INSERT INTO custom_attribute_definitions (id, account_id, attribute_model, attribute_key, attribute_display_name, attribute_display_type,
                                          attribute_description, created_at, updated_at) VALUES
 (990901, 990001, 1, 'cpf', 'CPF', 0, NULL, now(), now()),
 (990902, 990001, 1, 'segmento', 'Segmento', 6, NULL, now(), now()),
 (990903, 990001, 1, 'joao_luca_pii', 'João Luca PII', 0, NULL, now(), now()),
 (990904, 990001, 1, 'campo_abandonado', 'Campo abandonado', 0, NULL, now(), now()),
 (990905, 990001, 3, 'apolice', 'Apólice', 0, NULL, now(), now()),
 (990906, 990001, 2, 'porte', 'Porte', 6, NULL, now(), now()),
 (990911, 990002, 1, 'cpf', 'CPF', 0, NULL, now(), now()),
 (990912, 990002, 1, 'segmento', 'Segmento do cliente', 0, NULL, now(), now()),
 (990913, 990002, 3, 'apolice', 'Apólice', 0, NULL, now(), now()),
 (990914, 990002, 2, 'porte', 'Porte', 6, NULL, now(), now()),
 (990921, 990003, 1, 'cpf', 'CPF', 0, NULL, now(), now());

INSERT INTO labels (id, account_id, title, created_at, updated_at) VALUES
 (991001, 990001, 'cliente', now(), now()),
 (991002, 990001, 'joao_pii_label', now(), now()),
 (991003, 990002, 'cliente', now(), now()),
 (991004, 990002, 'maria_pii_b', now(), now());
INSERT INTO tags (id, name) VALUES
 (991101, 'cliente'), (991102, 'joao_pii_label'), (991103, 'maria_pii_b'), (991104, 'tag_solta_pii');
INSERT INTO taggings (id, tag_id, taggable_type, taggable_id, context, created_at) VALUES
 (991201, 991101, 'Contact', 990101, 'labels', now()),
 (991202, 991102, 'Contact', 990103, 'labels', now()),
 (991203, 991104, 'Contact', 990101, 'labels', now()),
 (991204, 991101, 'Contact', 990111, 'labels', now()),
 (991205, 991103, 'Contact', 990112, 'labels', now());

INSERT INTO campaign_imports (id, account_id, user_id, status, total_rows, valid_rows, options, extra_columns, schema_resolution, created_at, updated_at) VALUES
 (991301, 990001, 612, 7, 10, 9, '{"flow":"contacts"}',
  '["pii@exemplo.com","+55 11 99999-0000","PIIHEADER Pessoa","Segmento"]',
  '{"method":"jev","header_row":1,"columns":[{"index":0,"header":"Nome","example_masked":"PIIEXEMPLO"},{"index":1,"header":"Telefone"},{"index":2,"header":"pii@exemplo.com"},{"index":3,"header":"+55 11 99999-0000"},{"index":4,"header":"PIIHEADER Pessoa"},{"index":5,"header":"Segmento"}],"targets":{"name":{"column":0,"header":"Nome"},"phone":{"column":1,"header":"Telefone"}}}',
  now(), now()),
 (991302, 990002, 612, 7, 5, 5, '{"flow":"PIIFLUXO"}',
  '["Segmento","Cidade"]',
  '{"method":"PIIMETODO","header_row":1,"columns":[{"index":0,"header":"nome"},{"index":1,"header":"telefone"},{"index":2,"header":"Segmento"},{"index":3,"header":"Cidade"}],"targets":{"name":{"column":0,"header":"nome"},"phone":{"column":1,"header":"telefone"}}}',
  now(), now());

INSERT INTO email_campaigns (id, account_id, name, created_at, updated_at) VALUES
 (991401, 990001, 'PIICAMPANHA A', now(), now()),
 (991402, 990002, 'PIICAMPANHA B', now(), now());
INSERT INTO email_campaign_imports (id, email_campaign_id, status, schema_resolution, created_at, updated_at) VALUES
 (991411, 991401, 2, '{"method":"jev"}', now(), now()),
 (991412, 991402, 3, '{"method":"PIIMETODO"}', now(), now());
INSERT INTO email_campaign_recipients (id, email_campaign_id, name, email, custom_data, created_at, updated_at) VALUES
 (991421, 991401, 'PIIDEST A', 'pii-dest-a@exemplo.com', '{"apolice_pii":"PIIVALOR","cidade":"PIICIDADE","pii@x_com":"v"}', now(), now()),
 (991422, 991402, 'PIIDEST B', 'pii-dest-b@exemplo.com', '{"cidade":"PIICIDADEB","bairro":"PIIBAIRRO"}', now(), now());

