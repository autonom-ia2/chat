# Quais ids de campanha (`source_id` dos toques) são de anúncio (#2271). Um id que foi anúncio em QUALQUER toque, de
# qualquer conversa, conta como anúncio — no filtro do CRM, no filtro de Conversas e nas opções do filtro
# (GET /ctwa_campaigns). A regra é a de Crm::AnuncioDeOrigem.fonte_de_anuncio, aplicada em Ruby sobre os sinais do toque.
#
# Do banco sai só o que a regra lê (`sinais_sql`): a origem, o tipo e as UTMs de origem/meio, e a PRESENÇA dos ids de
# clique, sem o valor (ctwa_clid, gclid, ttclid e fbclid são únicos por clique e impediriam o DISTINCT). Assim a consulta
# devolve poucas combinações por id. Se Ctwa::CampaignBuilder.source_for passar a ler outro campo, ele entra aqui.
#
#   Crm::AnuncioDeOrigem::Ids.de_anuncio(account, ids)  -> os ids, dentre `ids`, que são de anúncio na conta
#   Crm::AnuncioDeOrigem::Ids.sem_anuncio(account, ids) -> os ids, dentre `ids`, que existem na conta e nunca foram anúncio
#   Crm::AnuncioDeOrigem::Ids.anuncio?(sinais)          -> algum dos sinais (lista de hashes) é de anúncio?
module Crm::AnuncioDeOrigem::Ids
  CAMPOS_LIDOS = %w[source source_type utm_source utm_medium].freeze
  IDS_DE_CLIQUE = %w[ctwa_clid gclid ttclid fbclid].freeze

  # Os toques (a lista e a origem) das conversas da conta com um dos ids. Com poucos ids (o filtro), o espelho
  # `campaign_source_ids` filtra primeiro, pelo índice trigram (a mesma sonda do filtro do CRM). Com muitos (as opções do
  # filtro, uma linha por campanha), uma sonda por id custa mais que ler os toques da conta uma vez: EXPLAIN ANALYZE local
  # (300 mil conversas, 100 mil na conta, 480 ids) deu 4,0 s com sonda e 0,4 s sem; com 2 ids, 0,09 s com sonda.
  MAX_SONDAS = 20
  SONDA_SQL = "AND conversations.additional_attributes ->> 'campaign_source_ids' ILIKE ANY (ARRAY[:sondas])".freeze

  module_function

  # O objeto com os sinais do toque `elemento` (uma expressão jsonb), para jsonb_agg(DISTINCT ...) e SELECT DISTINCT.
  def sinais_sql(elemento)
    lidos = CAMPOS_LIDOS.map { |campo| "'#{campo}', #{elemento} ->> '#{campo}'" }
    cliques = IDS_DE_CLIQUE.map { |campo| "'#{campo}', CASE WHEN COALESCE(#{elemento} ->> '#{campo}', '') <> '' THEN '1' END" }
    "jsonb_build_object(#{(lidos + cliques).join(', ')})"
  end

  def toques_sql(com_sonda)
    <<~SQL.squish
      SELECT DISTINCT toque ->> 'source_id' AS source_id, #{sinais_sql('toque')}::text AS sinais
      FROM conversations
      CROSS JOIN LATERAL jsonb_array_elements(
        (CASE WHEN jsonb_typeof(conversations.additional_attributes -> 'campaign_touches') = 'array'
              THEN conversations.additional_attributes -> 'campaign_touches' ELSE '[]'::jsonb END) ||
        (CASE WHEN jsonb_typeof(conversations.additional_attributes -> 'campaign') = 'object'
              THEN jsonb_build_array(conversations.additional_attributes -> 'campaign') ELSE '[]'::jsonb END)
      ) AS toque
      WHERE conversations.account_id = :account_id
        #{SONDA_SQL if com_sonda}
        AND toque ->> 'source_id' IN (:ids)
    SQL
  end

  def de_anuncio(account, ids)
    classifica(account, ids).select { |_id, anuncio| anuncio }.keys
  end

  def sem_anuncio(account, ids)
    classifica(account, ids).reject { |_id, anuncio| anuncio }.keys
  end

  def anuncio?(sinais)
    Array(sinais).any? { |sinal| sinal.is_a?(Hash) && Crm::AnuncioDeOrigem.fonte_de_anuncio(sinal) }
  end

  # { id => true (foi anúncio em algum toque) | false } para os ids que existem na conta.
  def classifica(account, ids)
    ids = Array(ids).compact_blank.uniq
    return {} if ids.empty?

    com_sonda = ids.size <= MAX_SONDAS
    sondas = ids.map { |id| "%\"#{ActiveRecord::Base.sanitize_sql_like(id)}\"%" }
    sql = ActiveRecord::Base.sanitize_sql_array([toques_sql(com_sonda), { account_id: account.id, sondas: sondas, ids: ids }])
    ActiveRecord::Base.connection.select_rows(sql).each_with_object({}) do |(id, sinais), classes|
      classes[id] = classes.fetch(id, false) || anuncio?([JSON.parse(sinais)])
    end
  end
end
