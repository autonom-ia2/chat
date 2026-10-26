-- #2202, PR 0: a bolinha de não lida parada em conversa já respondida.
--
-- NÃO RODADO EM PRODUÇÃO NEM EM BANCO COM DADO REAL. Rascunho para o Rodrigo aprovar. Produção só por psql
-- (SSM + docker exec), nunca rails runner. Rode a PARTE 1 (só leitura) primeiro; a PARTE 2 só com OK explícito,
-- depois do deploy do PR 0 (antes dele, a próxima resposta pelo celular voltaria a deixar bolinha parada).
--
-- A regra é a do código (app/services/conversa_canal/vista_ao_responder.rb e app/services/messages/nao_e_resposta.rb):
-- SÓ RESPOSTA DE PESSOA apaga a bolinha (decisão do Rodrigo, #2202), também no passado. Duas observações:
-- - o "visto" vai até a última resposta de pessoa que conta, no começo do segundo dela menos 1 µs (a tela compara em
--   segundos inteiros), e nunca para trás;
-- - a hora do envio do eco (external_created_at) só existe nos ecos gravados depois do PR 0: no passado vale a hora
--   em que a mensagem chegou aqui (marca menos: é o lado seguro).
--
-- Conta: mensagem que sai (message_type = 1), pública (private = false), que não falhou (status <> 3), de pessoa:
-- remetente User (painel, API com token de pessoa) ou eco do celular (external_echo). Robô (AgentBot,
-- Captain::Assistant), pesquisa de satisfação e toda saída sem remetente que não é eco ficam de fora por aí.
-- Não conta (Messages::NaoEResposta): campanha (campaign_id, whatsapp_api_campaign_id), envio automático em nome de
-- alguém (automation_rule_id, crm_follow_up_id, crm_booking_invite_id, crm_booking_notice), cópia encaminhada
-- (forwarded), modelo reenviado (reenvio_do_modelo) e importação do histórico (history_import).
--
-- Por que COALESCE(...::text, '') NOT LIKE e não ->> / ?: em produção messages.content_attributes é JSON dentro de
-- string (JSON duplo), e ->> devolve NULL. O COALESCE é para coluna NULL: NULL NOT LIKE dá NULL, e a mensagem sairia
-- da conta calada. LIKE '%campaign_id%' também pega whatsapp_api_campaign_id (as duas ficam de fora, de propósito).
-- Uma chave gravada com valor null também sai: errar para menos (não marcar) é o lado seguro.
--
-- Uma conversa entra quando: (a) tem resposta de pessoa que conta depois do "visto" atual; e (b) tem mensagem do cliente
-- entre o "visto" atual e o novo (é a bolinha parada). Mensagem do cliente depois da última resposta de pessoa continua
-- não lida, de propósito.
--
-- CUSTO DO LATERAL (medido num banco de rascunho local, com dados SINTÉTICOS, não em produção: 50 mil conversas,
-- 1 milhão de mensagens, Postgres 16, os índices de produção de messages): ver o fim deste arquivo. O LATERAL roda uma
-- vez por conversa e usa index_messages_on_conversation_account_type_created (conversation_id, account_id,
-- message_type, created_at); o filtro de LIKE só lê as linhas de saída depois do "visto". Antes de rodar em produção,
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
    WHERE m.conversation_id = c.id
      AND m.account_id = c.account_id
      AND m.message_type = 1
      AND m.private = false
      AND m.status <> 3
      AND (m.sender_type = 'User' OR COALESCE(m.content_attributes::text, '') LIKE '%external_echo%')
      AND (c.agent_last_seen_at IS NULL OR m.created_at > c.agent_last_seen_at)
      AND COALESCE(m.additional_attributes::text, '') NOT LIKE '%campaign_id%'
      AND COALESCE(m.content_attributes::text, '') NOT LIKE '%automation_rule_id%'
      AND COALESCE(m.content_attributes::text, '') NOT LIKE '%crm_follow_up_id%'
      AND COALESCE(m.content_attributes::text, '') NOT LIKE '%crm_booking_invite_id%'
      AND COALESCE(m.content_attributes::text, '') NOT LIKE '%crm_booking_notice%'
      AND COALESCE(m.content_attributes::text, '') NOT LIKE '%history_import%'
      AND COALESCE(m.content_attributes::text, '') NOT LIKE '%forwarded%'
      AND COALESCE(m.content_attributes::text, '') NOT LIKE '%reenvio_do_modelo%'
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
-- Antes: conferir o número da PARTE 1 e avisar a Orquestração (escrita em produção).
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
-- BEGIN;
-- SET LOCAL statement_timeout = '300s';
--
-- CREATE TABLE backup_2202_agent_last_seen AS
-- WITH alvo AS (
--   SELECT c.id, c.account_id, c.agent_last_seen_at, r.novo_visto
--   FROM conversations c
--   CROSS JOIN LATERAL (
--     SELECT date_trunc('second', MAX(m.created_at)) - interval '1 microsecond' AS novo_visto
--     FROM messages m
--     WHERE m.conversation_id = c.id
--       AND m.account_id = c.account_id
--       AND m.message_type = 1
--       AND m.private = false
--       AND m.status <> 3
--       AND (m.sender_type = 'User' OR COALESCE(m.content_attributes::text, '') LIKE '%external_echo%')
--       AND (c.agent_last_seen_at IS NULL OR m.created_at > c.agent_last_seen_at)
--       AND COALESCE(m.additional_attributes::text, '') NOT LIKE '%campaign_id%'
--       AND COALESCE(m.content_attributes::text, '') NOT LIKE '%automation_rule_id%'
--       AND COALESCE(m.content_attributes::text, '') NOT LIKE '%crm_follow_up_id%'
--       AND COALESCE(m.content_attributes::text, '') NOT LIKE '%crm_booking_invite_id%'
--       AND COALESCE(m.content_attributes::text, '') NOT LIKE '%crm_booking_notice%'
--       AND COALESCE(m.content_attributes::text, '') NOT LIKE '%history_import%'
--       AND COALESCE(m.content_attributes::text, '') NOT LIKE '%forwarded%'
--       AND COALESCE(m.content_attributes::text, '') NOT LIKE '%reenvio_do_modelo%'
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
-- -- Conferir: tem de bater com seriam_corrigidas da PARTE 1 (pode ser um pouco maior: respostas novas no meio).
-- SELECT COUNT(*) FROM backup_2202_agent_last_seen;
--
-- UPDATE conversations c
-- SET agent_last_seen_at = b.novo_visto
-- FROM backup_2202_agent_last_seen b
-- WHERE c.id = b.id
--   AND (c.agent_last_seen_at IS NULL OR c.agent_last_seen_at < b.novo_visto);
--
-- -- Conferir o número de linhas do UPDATE contra o COUNT acima; diferente -> ROLLBACK.
-- COMMIT;  -- ou ROLLBACK

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
-- A medida foi feita antes do filtro de pessoa (sender_type = User ou eco), que é só mais uma condição sobre as
-- mesmas linhas lidas pelo índice: o plano e a ordem de grandeza não mudam.
-- Ordem de grandeza: linear no número de conversas (um laço por conversa). Em produção (ordem de 10^4 a 10^5
-- conversas por stack) deve ficar em segundos, não minutos; o pior caso é conversa com muitas saídas que NÃO contam
-- depois do "visto" (o Limit 1 lê todas elas antes de achar uma que conta). Por isso o statement_timeout da PARTE 1.
