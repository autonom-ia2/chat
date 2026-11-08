-- HUB2YOU, conta 17 (Hubsegs): grava o dono do token em 26 caixas WAHA, provado por hash (conferência de 19/10).
-- Só as caixas sem dono; cada grupo confere o número de linhas e aborta se divergir.

-- 1) BACKUP (guardar a saída antes de gravar)
SELECT c.id, c.additional_attributes::text
FROM channel_api c JOIN inboxes i ON i.channel_id = c.id AND i.channel_type = 'Channel::Api'
WHERE i.account_id = 17 AND c.id IN (7,12,14,18, 45,46,51,52,54,55,56,57,58,59,62,65,66,68,70,71,72, 73,75,77,79,80)
ORDER BY c.id;

-- 2) GRAVAÇÃO
BEGIN;
DO $$
DECLARE n int;
BEGIN
  -- User 1 (Chat2You Admin): caixas 10, 15, 17, 21
  UPDATE channel_api c
     SET additional_attributes = c.additional_attributes || jsonb_build_object('account_token_owner_user_id', 1), updated_at = NOW()
    FROM inboxes i
   WHERE i.channel_id = c.id AND i.channel_type = 'Channel::Api' AND i.account_id = 17
     AND c.id IN (7,12,14,18)
     AND c.additional_attributes ->> 'provider' = 'waha'
     AND COALESCE(c.additional_attributes ->> 'account_token_owner_user_id', '') = '';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 4 THEN RAISE EXCEPTION 'user 1: esperava 4, afetou %', n; END IF;

  -- User 23: 17 caixas (70, 71, 76, 77, 79, 80, 81, 82, 83, 84, 87, 91, 92, 94, 96, 97, 98)
  UPDATE channel_api c
     SET additional_attributes = c.additional_attributes || jsonb_build_object('account_token_owner_user_id', 23), updated_at = NOW()
    FROM inboxes i
   WHERE i.channel_id = c.id AND i.channel_type = 'Channel::Api' AND i.account_id = 17
     AND c.id IN (45,46,51,52,54,55,56,57,58,59,62,65,66,68,70,71,72)
     AND c.additional_attributes ->> 'provider' = 'waha'
     AND COALESCE(c.additional_attributes ->> 'account_token_owner_user_id', '') = '';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 17 THEN RAISE EXCEPTION 'user 23: esperava 17, afetou %', n; END IF;

  -- User 56: caixas 100, 103, 105, 107, 108
  UPDATE channel_api c
     SET additional_attributes = c.additional_attributes || jsonb_build_object('account_token_owner_user_id', 56), updated_at = NOW()
    FROM inboxes i
   WHERE i.channel_id = c.id AND i.channel_type = 'Channel::Api' AND i.account_id = 17
     AND c.id IN (73,75,77,79,80)
     AND c.additional_attributes ->> 'provider' = 'waha'
     AND COALESCE(c.additional_attributes ->> 'account_token_owner_user_id', '') = '';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 5 THEN RAISE EXCEPTION 'user 56: esperava 5, afetou %', n; END IF;
END $$;
COMMIT;

-- 3) CONFERÊNCIA: rodar de novo a conferência dos donos (rodar.sh hub2you). As 26 devem sair "OK (gravado confere)".

-- ROLLBACK (só nas linhas desta operação)
-- UPDATE channel_api SET additional_attributes = additional_attributes - 'account_token_owner_user_id', updated_at = NOW()
--  WHERE id IN (7,12,14,18) AND additional_attributes ->> 'account_token_owner_user_id' = '1';
-- UPDATE channel_api SET additional_attributes = additional_attributes - 'account_token_owner_user_id', updated_at = NOW()
--  WHERE id IN (45,46,51,52,54,55,56,57,58,59,62,65,66,68,70,71,72) AND additional_attributes ->> 'account_token_owner_user_id' = '23';
-- UPDATE channel_api SET additional_attributes = additional_attributes - 'account_token_owner_user_id', updated_at = NOW()
--  WHERE id IN (73,75,77,79,80) AND additional_attributes ->> 'account_token_owner_user_id' = '56';
