-- #1676 (épico #1140): IA de assunto em Automática por padrão, atrás da flag crm_avaliar_toda_mensagem (#1675).
--
-- NÃO RODAR sem o OK do Rodrigo. Quem roda é a Orquestração, na stack Hub2You, DEPOIS do deploy do #1687 e do #1676
-- e depois de ligar a flag nas contas 1, 16 e 18 (#1688). Na stack Autonomia os ids 1, 16 e 18 são outras empresas:
-- não rodar lá.
--
-- Valores de crm_inbox_settings.subject_ai_mode: 0 = off (desligada), 1 = suggest (Sugerir), 2 = auto (Automática).
-- O UPDATE grava direto no banco, sem callback do Rails. Ir de off para auto não tem efeito colateral no modelo (o
-- callback de Crm::InboxSetting só age quando a caixa SAI de Sugerir/Automática).
--
-- Escopo: TODA caixa com CRM e IA de assunto desligada nessas contas, de 1 ou de 2+ funis ("ligada 100% para todos",
-- Rodrigo, 16/10). Isso inclui a caixa de 2+ funis em que a equipe escolheu "à mão" e a de 1 funil "à mão": nelas a IA
-- passa a abrir card quando identifica um pedido novo. Para virar só as de 1 funil, usar o mesmo critério de funis do
-- passo 1 no UPDATE. Funil com a IA do funil desligada continua fora da IA de assunto, mesmo com a caixa em auto.
--
-- Desligar a flag depois NÃO desliga a IA de assunto dessas caixas: o valor fica gravado. O caminho de volta é o
-- rollback no fim deste arquivo (ou a tela de Caixas, caixa de 2+ funis).
--
-- Ordem: 1) contagem, 2) retrato (guardar a saída, é o rollback), 3) UPDATE numa transação, 4) conferência.

-- 1) Contagem (só leitura): caixas com o CRM ligado e a IA de assunto desligada, por conta e por quantidade de funis
--    ativos ligados à caixa. Rodar também sem o filtro de conta, para saber o tamanho fora do piloto.
SELECT s.account_id,
       COUNT(*) AS caixas_com_ia_de_assunto_off,
       COUNT(*) FILTER (WHERE f.funis = 1) AS de_1_funil,
       COUNT(*) FILTER (WHERE f.funis >= 2) AS de_2_ou_mais_funis,
       COUNT(*) FILTER (WHERE COALESCE(f.funis, 0) = 0) AS sem_funil_ativo
FROM crm_inbox_settings s
LEFT JOIN LATERAL (
  SELECT COUNT(DISTINCT pi.pipeline_id) AS funis
  FROM crm_pipeline_inboxes pi
  JOIN crm_pipelines p ON p.id = pi.pipeline_id AND p.status = 0
  WHERE pi.account_id = s.account_id AND pi.inbox_id = s.inbox_id
) f ON TRUE
WHERE s.crm_enabled = TRUE
  AND s.subject_ai_mode = 0
  AND s.account_id IN (1, 16, 18)
GROUP BY s.account_id
ORDER BY s.account_id;

-- 2) Retrato (só leitura): as linhas que o UPDATE vai mudar. Guardar a saída antes do passo 3.
SELECT s.id, s.account_id, s.inbox_id, s.subject_ai_mode, s.auto_create_card, s.updated_at
FROM crm_inbox_settings s
WHERE s.crm_enabled = TRUE
  AND s.subject_ai_mode = 0
  AND s.account_id IN (1, 16, 18)
ORDER BY s.account_id, s.inbox_id;

-- 3) Virada (ESCRITA, só com OK): off -> auto nas caixas com CRM das contas 1, 16 e 18. Conferir que o número de linhas
--    do UPDATE é o total do passo 1 antes do COMMIT; se não for, ROLLBACK.
BEGIN;
UPDATE crm_inbox_settings
SET subject_ai_mode = 2, updated_at = NOW()
WHERE crm_enabled = TRUE
  AND subject_ai_mode = 0
  AND account_id IN (1, 16, 18);
-- COMMIT;   -- ou ROLLBACK;

-- 4) Conferência (só leitura): deve voltar 0 linhas.
SELECT s.account_id, COUNT(*)
FROM crm_inbox_settings s
WHERE s.crm_enabled = TRUE
  AND s.subject_ai_mode = 0
  AND s.account_id IN (1, 16, 18)
GROUP BY s.account_id;

-- Rollback (ESCRITA, só se precisar): volta para off exatamente as linhas do retrato do passo 2. Pelo SQL, as sugestões
-- de assunto que ficaram esperando nessas caixas não expiram sozinhas (o callback do Rails não roda): desligar pela tela
-- de Caixas faz isso, ou expirar à parte as crm_subject_decisions com state 'suggested' dessas caixas.
-- UPDATE crm_inbox_settings SET subject_ai_mode = 0, updated_at = NOW()
-- WHERE id IN (/* ids do passo 2 */) AND subject_ai_mode = 2;
