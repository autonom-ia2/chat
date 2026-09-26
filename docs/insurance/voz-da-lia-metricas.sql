-- A VOZ DA LIA NO AVISO DE FIM DE COTAÇÃO: métricas grátis, só leitura (itens 6 e 5A da auditoria de 26/09/2026).
--
-- O que mede, sobre as falas públicas que a Lia escreveu num turno de evento de fim de cotação (a mensagem carrega a
-- marca `autonomia_evento` = "<id da execução>:<tipo>", `Tools::Evento::CHAVE`):
--   com_item_literal     a fala contém o identificador do bem (`arguments->>'item'`). Meta: 0%.
--   abertura_repetida    as três primeiras palavras iguais às da fala de fim de cotação anterior na mesma conversa.
--   com_travessao        a fala tem travessão ou meia-risca. Meta: 0%.
--   com_real             a fala escreve "R$" num aviso em que nenhum preço veio junto. Meta: 0%, salvo leitura no turno.
--   termina_em_pergunta  a última letra é "?": a Lia devolveu a conversa.
--   tamanho_medio        caracteres por fala.
-- Tudo é contagem: nenhuma linha devolve texto de mensagem, nome, CPF, CNPJ ou placa.
--
-- Sem regex: só posição de texto (`strpos`), `split_part` e `right`, sobre texto que o modelo escreveu.
-- Uso: o período é o `desde` no começo. Rode só em leitura (a sessão abaixo recusa escrita).

BEGIN TRANSACTION READ ONLY;

WITH parametros AS (
  SELECT now() - interval '30 days' AS desde
),
-- O `content_attributes` destas mensagens é gravado como TEXTO JSON dentro da coluna json (medido em 26/09/2026: 43 de
-- 43 com `jsonb_typeof = 'string'`). Lê os dois formatos.
atributos AS (
  SELECT m.id, m.conversation_id, m.created_at, m.content,
         CASE WHEN jsonb_typeof(m.content_attributes::jsonb) = 'string'
              THEN (m.content_attributes::jsonb #>> '{}')::jsonb
              ELSE m.content_attributes::jsonb END AS attrs
  FROM messages m, parametros p
  WHERE m.created_at >= p.desde
    AND m.message_type = 1
    AND m.private = false
    AND m.content IS NOT NULL
    AND strpos(m.content_attributes::text, 'autonomia_evento') > 0
),
falas AS (
  SELECT a.id, a.conversation_id, a.created_at, a.content,
         split_part(a.attrs ->> 'autonomia_evento', ':', 2) AS tipo,
         nullif(split_part(a.attrs ->> 'autonomia_evento', ':', 1), '')::bigint AS execucao_id
  FROM atributos a
),
fim AS (
  SELECT f.*,
         lower(coalesce(r.arguments ->> 'item', '')) AS item,
         lower(split_part(f.content, ' ', 1) || ' ' || split_part(f.content, ' ', 2) || ' ' || split_part(f.content, ' ', 3)) AS abertura
  FROM falas f
  LEFT JOIN autonomia_agent_tool_runs r ON r.id = f.execucao_id
  WHERE f.tipo IN ('concluida', 'encerrada_por_prazo')
),
em_ordem AS (
  SELECT fim.*,
         lag(abertura) OVER (PARTITION BY conversation_id ORDER BY created_at, id) AS abertura_anterior
  FROM fim
)
SELECT count(*) AS falas_de_fim,
       count(*) FILTER (WHERE item <> '') AS falas_com_item_gravado,
       round(100.0 * count(*) FILTER (WHERE item <> '' AND strpos(lower(content), item) > 0)
             / nullif(count(*) FILTER (WHERE item <> ''), 0), 1) AS pct_com_item_literal,
       count(*) FILTER (WHERE abertura_anterior IS NOT NULL) AS falas_com_anterior,
       round(100.0 * count(*) FILTER (WHERE abertura_anterior IS NOT NULL AND abertura = abertura_anterior)
             / nullif(count(*) FILTER (WHERE abertura_anterior IS NOT NULL), 0), 1) AS pct_abertura_repetida,
       round(100.0 * count(*) FILTER (WHERE strpos(content, '—') > 0 OR strpos(content, '–') > 0) / nullif(count(*), 0), 1)
         AS pct_com_travessao,
       round(100.0 * count(*) FILTER (WHERE strpos(content, 'R$') > 0) / nullif(count(*), 0), 1) AS pct_com_real,
       round(100.0 * count(*) FILTER (WHERE right(btrim(content), 1) = '?') / nullif(count(*), 0), 1) AS pct_termina_em_pergunta,
       round(avg(length(content))) AS tamanho_medio
FROM em_ordem;

ROLLBACK;
