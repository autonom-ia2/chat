-- AUTONOM.IA, conta 17: grava o dono do token na caixa WAHA 9 (canal 7), provado por hash (conferência de 19/10).

-- 1) BACKUP
SELECT c.id, c.additional_attributes::text FROM channel_api c
JOIN inboxes i ON i.channel_id = c.id AND i.channel_type = 'Channel::Api'
WHERE i.account_id = 17 AND c.id = 7;

-- 2) GRAVAÇÃO
BEGIN;
DO $$
DECLARE n int;
BEGIN
  UPDATE channel_api c
     SET additional_attributes = c.additional_attributes || jsonb_build_object('account_token_owner_user_id', 1), updated_at = NOW()
    FROM inboxes i
   WHERE i.channel_id = c.id AND i.channel_type = 'Channel::Api' AND i.account_id = 17
     AND c.id = 7
     AND c.additional_attributes ->> 'provider' = 'waha'
     AND COALESCE(c.additional_attributes ->> 'account_token_owner_user_id', '') = '';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'esperava 1, afetou %', n; END IF;
END $$;
COMMIT;

-- ROLLBACK
-- UPDATE channel_api SET additional_attributes = additional_attributes - 'account_token_owner_user_id', updated_at = NOW()
--  WHERE id = 7 AND additional_attributes ->> 'account_token_owner_user_id' = '1';
