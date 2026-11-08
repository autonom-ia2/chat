-- #2202, PR 0: a bolinha de não lida parada em conversa já respondida.
--
-- NÃO RODADO EM PRODUÇÃO NEM EM BANCO COM DADO REAL. Rascunho para o Rodrigo aprovar. Produção só por psql
-- (SSM + docker exec), nunca rails runner. Rode a PARTE 1 (só leitura) primeiro; a PARTE 2 só com OK explícito,
-- depois do deploy do PR 0 (antes dele, a próxima resposta pelo celular voltaria a deixar bolinha parada).
--
-- A regra é a do código (app/services/conversa_canal/vista_ao_responder.rb e app/services/messages/nao_e_resposta.rb):
-- SÓ RESPOSTA DE PESSOA pelo painel ou pela API com token de pessoa apaga a bolinha (decisões do Rodrigo, #2202), também
-- no passado. O robô e o eco do celular não apagam: nenhum canal diz se o eco foi uma pessoa ou resposta automática.
-- O "visto" vai até a última resposta de pessoa que conta, no começo do segundo dela menos 1 µs (a tela compara em
-- segundos inteiros), e nunca para trás.
--
-- Conta: mensagem que sai (message_type = 1), pública (private = false), que não falhou (COALESCE(status, 0) <> 3), de
-- pessoa: remetente User que é membro humano da conta (account_users.integration = false: o token do MCP/CRM entra
-- como User sintético com integration = true) e que não é eco. O modelo do WhatsApp mandado por pessoa conta;
-- campanha e message_type template (3) não. Robô (AgentBot, Captain::Assistant), pesquisa de
-- satisfação e toda saída sem remetente ficam de fora por aí. O eco sai pela chave external_echo: no WAHA comum o eco
-- chega com remetente User (o dono do token do conector), então só o sender_type não basta.
-- Não conta (Messages::NaoEResposta): campanha (campaign_id, whatsapp_api_campaign_id), envio automático em nome de
-- alguém (automation_rule_id, crm_follow_up_id, crm_booking_invite_id, crm_booking_notice), cópia encaminhada
-- (forwarded), modelo reenviado (reenvio_do_modelo) e importação do histórico (history_import).
--
-- Falha: aqui toda mensagem falhada (status 3) fica de fora, porque no passado a falha já é sabida. No código, só a
-- que já nasce falha fica de fora: a falha do envio chega depois, no SendReplyJob, e a pessoa leu para responder.
--
-- As marcas são lidas POR CHAVE, com a mesma regra do código (present? do Ruby: a chave existe e não é null, false
-- nem vazia), e não por LIKE no texto: LIKE '%forwarded%' pegava a palavra em qualquer lugar do JSON (o texto de um
-- e-mail guardado em content_attributes, por exemplo), e LIKE '%"forwarded":true%' não acha nada no JSON duplo, onde
-- as aspas vêm escapadas. Em produção messages.content_attributes é JSON dentro de string (JSON duplo), e ->> direto
-- devolve NULL; `(coluna #>> '{}')::jsonb` lê os dois formatos (é o que o Enterprise já faz no scope
-- captain_response_triggering). Atributo ilegível como JSON faz a mensagem sair da conta (lado seguro).
-- REQUER Postgres 16 ou mais novo (pg_input_is_valid). Em versão mais antiga a consulta falha na hora, com erro de
-- função inexistente: não roda errado em silêncio.
--
-- Uma conversa entra quando: (a) tem resposta de pessoa que conta depois do "visto" atual; e (b) tem mensagem do cliente
-- entre o "visto" atual e o novo (é a bolinha parada). Mensagem do cliente depois da última resposta de pessoa continua
-- não lida, de propósito.
--
-- CUSTO DO LATERAL (medido num banco de rascunho local, com dados SINTÉTICOS, não em produção: 50 mil conversas,
-- 1 milhão de mensagens, Postgres 16, os índices de produção de messages): ver o fim deste arquivo. O LATERAL roda uma
-- vez por conversa e usa index_messages_on_conversation_account_type_created (conversation_id, account_id,
-- message_type, created_at); os filtros só leem as linhas de saída depois do "visto". Antes de rodar em produção,
-- rode o EXPLAIN (sem ANALYZE) da PARTE 0 e confira que o plano usa esse índice; se aparecer Seq Scan em messages,
-- pare e rode por conta (acrescente AND c.account_id = <id> no WHERE de alvo).

-- =====================================================================================================
-- PARTE 0 — PLANO, SEM EXECUTAR (EXPLAIN sem ANALYZE não lê os dados)
-- =====================================================================================================
-- EXPLAIN <cole aqui o WITH alvo ... SELECT COUNT(*) FROM alvo da PARTE 1>;

-- =====================================================================================================
-- PARTE 1 — SÓ LEITURA: quantas seriam corrigidas
-- =====================================================================================================
BEGIN READ ONLY;
SET LOCAL statement_timeout = '120s';

WITH alvo AS (
  SELECT c.id, c.account_id, c.status, c.agent_last_seen_at, r.novo_visto
  FROM conversations c
  CROSS JOIN LATERAL (
    SELECT date_trunc('second', MAX(m.created_at)) - interval '1 microsecond' AS novo_visto
    FROM messages m
    -- Pessoa da conta: membro humano (integration = false). O token do MCP/CRM entra como User sintético com
    -- integration = true (Mcp::IntegrationToken#create_managed_user) e fica de fora, como no código.
    JOIN account_users au
      ON au.user_id = m.sender_id AND au.account_id = m.account_id AND au.integration = false
    -- Os atributos como jsonb, nos dois formatos gravados: objeto JSON ou JSON dentro de string (JSON duplo, como em
    -- produção). `#>> '{}'` devolve o texto do objeto ou o de dentro da string; ilegível vira NULL e a linha sai.
    CROSS JOIN LATERAL (
      SELECT CASE WHEN pg_input_is_valid(m.content_attributes #>> '{}', 'jsonb')
                  THEN (m.content_attributes #>> '{}')::jsonb END AS ca,
             CASE WHEN pg_input_is_valid(m.additional_attributes #>> '{}', 'jsonb')
                  THEN (m.additional_attributes #>> '{}')::jsonb END AS aa
    ) x
    WHERE m.conversation_id = c.id
      AND m.account_id = c.account_id
      AND m.message_type = 1
      AND m.private = false
      AND COALESCE(m.status, 0) <> 3
      AND (m.content_attributes IS NULL OR x.ca IS NOT NULL)
      AND (m.additional_attributes IS NULL OR x.aa IS NOT NULL)
      -- De pessoa: remetente User. "Presente" (abaixo) = como o present? do Ruby: nem ausente, nem null, nem false, nem vazio.
      AND m.sender_type = 'User'
      AND (c.agent_last_seen_at IS NULL OR m.created_at > c.agent_last_seen_at)
      -- O eco do celular, Messages::NaoEResposta e a importação do histórico: nenhuma destas chaves presente.
      AND COALESCE(x.ca ->> 'external_echo', '') IN ('', 'false', '{}', '[]')
      AND COALESCE(x.aa ->> 'campaign_id', '') IN ('', 'false', '{}', '[]')
      AND COALESCE(x.aa ->> 'whatsapp_api_campaign_id', '') IN ('', 'false', '{}', '[]')
      AND COALESCE(x.ca ->> 'automation_rule_id', '') IN ('', 'false', '{}', '[]')
      AND COALESCE(x.ca ->> 'crm_follow_up_id', '') IN ('', 'false', '{}', '[]')
      AND COALESCE(x.ca ->> 'crm_booking_invite_id', '') IN ('', 'false', '{}', '[]')
      AND COALESCE(x.ca ->> 'crm_booking_notice', '') IN ('', 'false', '{}', '[]')
      AND COALESCE(x.ca ->> 'forwarded', '') IN ('', 'false', '{}', '[]')
      AND COALESCE(x.ca ->> 'reenvio_do_modelo', '') IN ('', 'false', '{}', '[]')
      AND COALESCE(x.ca ->> 'history_import', '') IN ('', 'false', '{}', '[]')
  ) r
  WHERE r.novo_visto IS NOT NULL
    AND (c.agent_last_seen_at IS NULL OR c.agent_last_seen_at < r.novo_visto)
    AND EXISTS (
      SELECT 1
      FROM messages i
      WHERE i.conversation_id = c.id
        AND i.account_id = c.account_id
        AND i.message_type = 0
        AND (c.agent_last_seen_at IS NULL OR i.created_at > c.agent_last_seen_at)
        AND i.created_at <= r.novo_visto
    )
)
SELECT
  COUNT(*)                                     AS seriam_corrigidas,
  COUNT(*) FILTER (WHERE a.status = 0)         AS abertas,
  COUNT(*) FILTER (WHERE a.status = 2)         AS pendentes,
  COUNT(*) FILTER (WHERE a.status = 3)         AS adiadas,
  COUNT(*) FILTER (WHERE a.status = 1)         AS resolvidas,
  -- Sem bolinha depois da correção: nenhuma mensagem do cliente depois do novo "visto".
  COUNT(*) FILTER (WHERE NOT EXISTS (
    SELECT 1 FROM messages i
    WHERE i.conversation_id = a.id AND i.account_id = a.account_id AND i.message_type = 0
      AND i.created_at > a.novo_visto
  ))                                           AS ficariam_sem_bolinha,
  COUNT(*) FILTER (WHERE a.agent_last_seen_at IS NULL) AS nunca_abertas_no_painel
FROM alvo a;

-- Para comparar com a medição da Issue (abertas com bolinha hoje, mesma regra de não lida do Chatwoot):
SELECT COUNT(*) AS abertas_com_bolinha_hoje
FROM conversations c
WHERE c.status = 0
  AND EXISTS (
    SELECT 1 FROM messages i
    WHERE i.conversation_id = c.id AND i.account_id = c.account_id AND i.message_type = 0
      AND (c.agent_last_seen_at IS NULL OR i.created_at > c.agent_last_seen_at)
  );

ROLLBACK;

-- =====================================================================================================
-- PARTE 2 — RASCUNHO DE ESCRITA. NÃO RODAR SEM OK DO RODRIGO.
-- =====================================================================================================
-- Antes: conferir o número da PARTE 1 e avisar a Orquestração (escrita em produção). Dois passos: o backup (PASSO 1)
-- e a escrita em lotes com COMMIT curto, lock_timeout de 5 s e conferência por RAISE (PASSO 2).
-- Backup: a tabela backup_2202_agent_last_seen guarda id, o "visto" antigo e o novo de cada conversa tocada.
-- Rollback (comando exato, segundos):
--   UPDATE conversations c SET agent_last_seen_at = b.agent_last_seen_at
--   FROM backup_2202_agent_last_seen b WHERE c.id = b.id AND c.agent_last_seen_at = b.novo_visto;
--   (só volta a linha que ninguém leu de novo depois do backfill)
-- Quando apagar o backup: 7 dias depois do backfill, se ninguém reclamou de bolinha sumida, com OK do Rodrigo
--   (DROP TABLE backup_2202_agent_last_seen;). Depois de uma semana as conversas já foram lidas de novo e o rollback
--   não volta quase nada.
-- Depois: a contagem de não lidas da barra lateral (Redis, flag conversation_unread_counts) se refaz sozinha em até
-- 24 h (READY_TTL); a lista já mostra certo no próximo carregamento, porque o unread_count sai do banco.
-- O UPDATE não mexe em updated_at nem dispara callback (sem webhook, automação ou evento ao vivo).
--
-- PASSO 1: o backup (só lê messages e conversations; não trava conversa para escrita).
-- SET statement_timeout = '300s';
-- CREATE TABLE backup_2202_agent_last_seen AS
-- WITH alvo AS (
--   SELECT c.id, c.account_id, c.agent_last_seen_at, r.novo_visto
--   FROM conversations c
--   CROSS JOIN LATERAL (
--     SELECT date_trunc('second', MAX(m.created_at)) - interval '1 microsecond' AS novo_visto
--     FROM messages m
--     -- Pessoa da conta: membro humano (integration = false). O token do MCP/CRM entra como User sintético com
--     -- integration = true (Mcp::IntegrationToken#create_managed_user) e fica de fora, como no código.
--     JOIN account_users au
--       ON au.user_id = m.sender_id AND au.account_id = m.account_id AND au.integration = false
--     -- Os atributos como jsonb, nos dois formatos gravados: objeto JSON ou JSON dentro de string (JSON duplo, como em
--     -- produção). `#>> '{}'` devolve o texto do objeto ou o de dentro da string; ilegível vira NULL e a linha sai.
--     CROSS JOIN LATERAL (
--       SELECT CASE WHEN pg_input_is_valid(m.content_attributes #>> '{}', 'jsonb')
--                   THEN (m.content_attributes #>> '{}')::jsonb END AS ca,
--              CASE WHEN pg_input_is_valid(m.additional_attributes #>> '{}', 'jsonb')
--                   THEN (m.additional_attributes #>> '{}')::jsonb END AS aa
--     ) x
--     WHERE m.conversation_id = c.id
--       AND m.account_id = c.account_id
--       AND m.message_type = 1
--       AND m.private = false
--       AND COALESCE(m.status, 0) <> 3
--       AND (m.content_attributes IS NULL OR x.ca IS NOT NULL)
--       AND (m.additional_attributes IS NULL OR x.aa IS NOT NULL)
--       -- De pessoa: remetente User. "Presente" (abaixo) = como o present? do Ruby: nem ausente, nem null, nem false, nem vazio.
--       AND m.sender_type = 'User'
--       AND (c.agent_last_seen_at IS NULL OR m.created_at > c.agent_last_seen_at)
--       -- O eco do celular, Messages::NaoEResposta e a importação do histórico: nenhuma destas chaves presente.
--       AND COALESCE(x.ca ->> 'external_echo', '') IN ('', 'false', '{}', '[]')
--       AND COALESCE(x.aa ->> 'campaign_id', '') IN ('', 'false', '{}', '[]')
--       AND COALESCE(x.aa ->> 'whatsapp_api_campaign_id', '') IN ('', 'false', '{}', '[]')
--       AND COALESCE(x.ca ->> 'automation_rule_id', '') IN ('', 'false', '{}', '[]')
--       AND COALESCE(x.ca ->> 'crm_follow_up_id', '') IN ('', 'false', '{}', '[]')
--       AND COALESCE(x.ca ->> 'crm_booking_invite_id', '') IN ('', 'false', '{}', '[]')
--       AND COALESCE(x.ca ->> 'crm_booking_notice', '') IN ('', 'false', '{}', '[]')
--       AND COALESCE(x.ca ->> 'forwarded', '') IN ('', 'false', '{}', '[]')
--       AND COALESCE(x.ca ->> 'reenvio_do_modelo', '') IN ('', 'false', '{}', '[]')
--       AND COALESCE(x.ca ->> 'history_import', '') IN ('', 'false', '{}', '[]')
--   ) r
--   WHERE r.novo_visto IS NOT NULL
--     AND (c.agent_last_seen_at IS NULL OR c.agent_last_seen_at < r.novo_visto)
--     AND EXISTS (
--       SELECT 1
--       FROM messages i
--       WHERE i.conversation_id = c.id
--         AND i.account_id = c.account_id
--         AND i.message_type = 0
--         AND (c.agent_last_seen_at IS NULL OR i.created_at > c.agent_last_seen_at)
--         AND i.created_at <= r.novo_visto
--     )
-- )
-- SELECT id, account_id, agent_last_seen_at, novo_visto, now() AS copiado_em FROM alvo;
--
-- -- Um id por conversa (o índice único também recusa backup com conversa repetida).
-- CREATE UNIQUE INDEX backup_2202_agent_last_seen_id ON backup_2202_agent_last_seen (id);
-- RESET statement_timeout;
--
-- -- Conferir: tem de bater com seriam_corrigidas da PARTE 1 (pode ser um pouco maior: respostas novas no meio).
-- SELECT COUNT(*) FROM backup_2202_agent_last_seen;
--
-- -- PASSO 2: a escrita, em lotes de 1.000 conversas, com COMMIT curto por lote. Rode o DO FORA de BEGIN (o COMMIT
-- -- dentro do DO só vale no nível de cima). Cada lote trava só as suas conversas, espera no máximo 5 s por uma trava
-- -- (lock_timeout) e confere o número de linhas: o que travou para escrever tem de ser o que o UPDATE gravou; se
-- -- divergir, o RAISE desfaz o lote e para (os lotes anteriores ficam, e o rollback acima os desfaz). Nenhuma trava
-- -- fica aberta enquanto alguém confere à mão: a conferência é o RAISE, e o resultado sai no NOTICE de cada lote.
-- -- Se parar por lock_timeout, rode o DO de novo; os lotes já gravados contam 0.
-- DO $$
-- DECLARE
--   lote record;
--   esperado integer;
--   gravado integer;
--   total integer := 0;
-- BEGIN
--   FOR lote IN
--     SELECT MIN(id) AS de, MAX(id) AS ate
--     FROM (SELECT id, (ROW_NUMBER() OVER (ORDER BY id) - 1) / 1000 AS n FROM backup_2202_agent_last_seen) s
--     GROUP BY n ORDER BY n
--   LOOP
--     PERFORM set_config('lock_timeout', '5s', true);
--     PERFORM set_config('statement_timeout', '60s', true);
--     -- Um comando só: trava as conversas do lote e grava só as travadas; a contagem compara as duas.
--     WITH travadas AS (
--       SELECT c.id
--       FROM conversations c
--       JOIN backup_2202_agent_last_seen b ON b.id = c.id
--       WHERE b.id BETWEEN lote.de AND lote.ate
--         AND (c.agent_last_seen_at IS NULL OR c.agent_last_seen_at < b.novo_visto)
--       FOR NO KEY UPDATE OF c
--     ), gravadas AS (
--       UPDATE conversations c
--       SET agent_last_seen_at = b.novo_visto
--       FROM backup_2202_agent_last_seen b
--       WHERE c.id = b.id
--         AND c.id IN (SELECT id FROM travadas)
--         AND (c.agent_last_seen_at IS NULL OR c.agent_last_seen_at < b.novo_visto)
--       RETURNING c.id
--     )
--     SELECT (SELECT COUNT(*) FROM travadas), (SELECT COUNT(*) FROM gravadas) INTO esperado, gravado;
--
--     IF gravado <> esperado THEN
--       RAISE EXCEPTION 'backfill 2202: lote % a % gravou % linhas, esperava %', lote.de, lote.ate, gravado, esperado;
--     END IF;
--     total := total + gravado;
--     RAISE NOTICE 'backfill 2202: lote % a %: % linhas (total %)', lote.de, lote.ate, gravado, total;
--     COMMIT;
--   END LOOP;
-- END
-- $$;

-- =====================================================================================================
-- MEDIDA DO LATERAL (rascunho local, dados sintéticos; preenchido abaixo)
-- =====================================================================================================
-- Banco de rascunho criado e apagado no Postgres 16 local (127.0.0.1:55432), só com as colunas usadas aqui e os
-- índices de produção de messages; 50 mil conversas, 1 milhão de mensagens geradas (nenhum dado real).
-- EXPLAIN (ANALYZE, BUFFERS) do WITH alvo ... FROM alvo a da PARTE 1:
--   Seq Scan on conversations (50.000 linhas, 2 ms)
--   -> LATERAL: Index Scan Backward using index_messages_on_conversation_account_type_created, 50.000 laços,
--      0,002 ms cada (o MAX vira Limit 1 de trás para frente, parando na primeira saída que passa nos filtros)
--   -> EXISTS: Index Only Scan no mesmo índice, 10.000 laços
--   Buffers: shared hit=643.059 read=705 · Planning 1,9 ms · Execution 146 ms.
-- Medida de novo depois da leitura por chave (jsonb) e do filtro de pessoa, mesmos dados sintéticos: o mesmo plano
-- (Index Scan Backward no índice acima, 50.000 laços de 0,003 ms; EXISTS em Index Only Scan) · Planning 0,9 ms ·
-- Execution 177 ms. A leitura do JSON custa por mensagem de saída depois do "visto", não por conversa.
-- Nos dados sintéticos a leitura por chave foi conferida em 9 casos (objeto e JSON duplo, encaminhada nos dois
-- formatos, eco sem remetente, eco com remetente User como no WAHA comum, robô, status NULL, a palavra "forwarded"
-- dentro de um e-mail, campanha): entraram só os 3 esperados (resposta comum, status NULL, e-mail com a palavra).
-- Depois do JOIN em account_users e dos lotes, de novo num banco descartável (apagado no fim): os mesmos 9 casos mais
-- um 10º, resposta de um User de integração (account_users.integration = true), e 2.500 conversas comuns. A PARTE 1
-- contou 2.503; o PASSO 1 copiou 2.503; o DO do PASSO 2 gravou 3 lotes (1.000, 1.000, 503), total 2.503, em 0,7 s.
-- Gravadas entre os casos: só os 3 esperados; o de integração ficou com a bolinha. Prova do RAISE: com um gatilho que
-- descarta a escrita de uma conversa do 2º lote, o DO parou com "lote ... gravou 999 linhas, esperava 1000"; o 1º lote
-- ficou gravado (1.000) e o 2º foi desfeito inteiro. Com o UPDATE só sobre as travadas (um comando só), de novo: os
-- mesmos 2.503 e 1,6,7; rodar o DO outra vez grava 0 em cada lote; com uma conversa do 2º lote presa por outra
-- transação, o DO parou com "canceling statement due to lock timeout" depois de gravar o 1º lote, e rodar de novo
-- gravou 0 + 1.000 + 503; o RAISE da contagem continuou parando o lote com a escrita descartada.
-- Ordem de grandeza: linear no número de conversas (um laço por conversa). Em produção (ordem de 10^4 a 10^5
-- conversas por stack) deve ficar em segundos, não minutos; o pior caso é conversa com muitas saídas que NÃO contam
-- depois do "visto" (o Limit 1 lê todas elas antes de achar uma que conta). Por isso o statement_timeout da PARTE 1.
