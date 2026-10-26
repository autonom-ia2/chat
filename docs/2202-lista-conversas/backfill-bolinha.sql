-- #2202, PR 0: a bolinha de não lida parada em conversa já respondida.
--
-- NÃO RODADO EM LUGAR NENHUM. Rascunho para o Rodrigo aprovar. Produção só por psql (SSM + docker exec), nunca
-- rails runner. Rode a PARTE 1 (só leitura) primeiro; a PARTE 2 só com OK explícito, depois do deploy do PR 0
-- (antes dele, a próxima resposta pelo celular voltaria a deixar bolinha parada nas conversas novas).
--
-- A regra é a mesma do código (app/services/conversa_canal/vista_ao_responder.rb): o "visto" da conversa
-- (conversations.agent_last_seen_at) vai até a última resposta nossa que conta, e nunca para trás.
-- Conta: mensagem que sai (message_type = 1), pública (private = false).
-- Não conta: campanha (additional_attributes com campaign_id ou whatsapp_api_campaign_id), envio automático em nome
-- de alguém (content_attributes com automation_rule_id, crm_follow_up_id, crm_booking_invite_id ou
-- crm_booking_notice) e mensagem importada do histórico (history_import).
--
-- Por que ::text LIKE e não ->> / ?: em produção messages.content_attributes é JSON dentro de string (JSON duplo), e
-- ->> devolve NULL. LIKE '%campaign_id%' também pega whatsapp_api_campaign_id (as duas ficam de fora, de propósito).
-- Uma chave gravada com valor null também sai: errar para menos (não marcar) é o lado seguro.
--
-- Uma conversa entra quando: (a) tem resposta nossa que conta depois do "visto" atual; e (b) tem mensagem do cliente
-- entre o "visto" atual e essa resposta (é a bolinha parada). Mensagem do cliente que chegou DEPOIS da nossa última
-- resposta continua não lida, de propósito.

-- =====================================================================================================
-- PARTE 1 — SÓ LEITURA: quantas seriam corrigidas
-- =====================================================================================================
BEGIN READ ONLY;

WITH alvo AS (
  SELECT c.id, c.account_id, c.status, c.agent_last_seen_at, r.ultima_resposta
  FROM conversations c
  CROSS JOIN LATERAL (
    SELECT MAX(m.created_at) AS ultima_resposta
    FROM messages m
    WHERE m.conversation_id = c.id
      AND m.account_id = c.account_id
      AND m.message_type = 1
      AND m.private = false
      AND (c.agent_last_seen_at IS NULL OR m.created_at > c.agent_last_seen_at)
      AND m.additional_attributes::text NOT LIKE '%campaign_id%'
      AND m.content_attributes::text NOT LIKE '%automation_rule_id%'
      AND m.content_attributes::text NOT LIKE '%crm_follow_up_id%'
      AND m.content_attributes::text NOT LIKE '%crm_booking_invite_id%'
      AND m.content_attributes::text NOT LIKE '%crm_booking_notice%'
      AND m.content_attributes::text NOT LIKE '%history_import%'
  ) r
  WHERE r.ultima_resposta IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM messages i
      WHERE i.conversation_id = c.id
        AND i.account_id = c.account_id
        AND i.message_type = 0
        AND (c.agent_last_seen_at IS NULL OR i.created_at > c.agent_last_seen_at)
        AND i.created_at <= r.ultima_resposta
    )
)
SELECT
  COUNT(*)                                     AS seriam_corrigidas,
  COUNT(*) FILTER (WHERE a.status = 0)         AS abertas,
  COUNT(*) FILTER (WHERE a.status = 2)         AS pendentes,
  COUNT(*) FILTER (WHERE a.status = 3)         AS adiadas,
  COUNT(*) FILTER (WHERE a.status = 1)         AS resolvidas,
  -- Sem bolinha depois da correção: nenhuma mensagem do cliente depois da nossa última resposta.
  COUNT(*) FILTER (WHERE NOT EXISTS (
    SELECT 1 FROM messages i
    WHERE i.conversation_id = a.id AND i.account_id = a.account_id AND i.message_type = 0
      AND i.created_at > a.ultima_resposta
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
-- Backup: a tabela backup_2202_agent_last_seen guarda id e o "visto" antigo de cada conversa tocada.
-- Rollback (comando exato, segundos):
--   UPDATE conversations c SET agent_last_seen_at = b.agent_last_seen_at
--   FROM backup_2202_agent_last_seen b WHERE c.id = b.id AND c.agent_last_seen_at = b.ultima_resposta;
--   (só volta a linha que ninguém leu de novo depois do backfill)
-- Depois: a contagem de não lidas da barra lateral (Redis, flag conversation_unread_counts) se refaz sozinha em até
-- 24 h (READY_TTL); a lista já mostra certo no próximo carregamento, porque o unread_count sai do banco.
-- O UPDATE não mexe em updated_at nem dispara callback (sem webhook, automação ou evento ao vivo).
--
-- BEGIN;
--
-- CREATE TABLE backup_2202_agent_last_seen AS
-- WITH alvo AS (
--   SELECT c.id, c.account_id, c.agent_last_seen_at, r.ultima_resposta
--   FROM conversations c
--   CROSS JOIN LATERAL (
--     SELECT MAX(m.created_at) AS ultima_resposta
--     FROM messages m
--     WHERE m.conversation_id = c.id
--       AND m.account_id = c.account_id
--       AND m.message_type = 1
--       AND m.private = false
--       AND (c.agent_last_seen_at IS NULL OR m.created_at > c.agent_last_seen_at)
--       AND m.additional_attributes::text NOT LIKE '%campaign_id%'
--       AND m.content_attributes::text NOT LIKE '%automation_rule_id%'
--       AND m.content_attributes::text NOT LIKE '%crm_follow_up_id%'
--       AND m.content_attributes::text NOT LIKE '%crm_booking_invite_id%'
--       AND m.content_attributes::text NOT LIKE '%crm_booking_notice%'
--       AND m.content_attributes::text NOT LIKE '%history_import%'
--   ) r
--   WHERE r.ultima_resposta IS NOT NULL
--     AND EXISTS (
--       SELECT 1
--       FROM messages i
--       WHERE i.conversation_id = c.id
--         AND i.account_id = c.account_id
--         AND i.message_type = 0
--         AND (c.agent_last_seen_at IS NULL OR i.created_at > c.agent_last_seen_at)
--         AND i.created_at <= r.ultima_resposta
--     )
-- )
-- SELECT id, account_id, agent_last_seen_at, ultima_resposta, now() AS copiado_em FROM alvo;
--
-- -- Conferir: tem de bater com seriam_corrigidas da PARTE 1.
-- SELECT COUNT(*) FROM backup_2202_agent_last_seen;
--
-- UPDATE conversations c
-- SET agent_last_seen_at = b.ultima_resposta
-- FROM backup_2202_agent_last_seen b
-- WHERE c.id = b.id
--   AND (c.agent_last_seen_at IS NULL OR c.agent_last_seen_at < b.ultima_resposta);
--
-- -- Conferir o número de linhas do UPDATE contra o COUNT acima; diferente -> ROLLBACK.
-- COMMIT;  -- ou ROLLBACK
