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

  module_function

  # O objeto com os sinais do toque `elemento` (uma expressão jsonb), para jsonb_agg(DISTINCT ...) e SELECT DISTINCT.
  def sinais_sql(elemento)
    lidos = CAMPOS_LIDOS.map { |campo| "'#{campo}', #{elemento} ->> '#{campo}'" }
    cliques = IDS_DE_CLIQUE.map { |campo| "'#{campo}', CASE WHEN COALESCE(#{elemento} ->> '#{campo}', '') <> '' THEN '1' END" }
    "jsonb_build_object(#{(lidos + cliques).join(', ')})"
  end

  # Os toques (a lista e a origem) das conversas da conta com um dos ids, num caminho só, qualquer que seja a quantidade
  # de ids: o toque antigo, gravado só em `campaign` (sem o espelho `campaign_source_ids`), conta igual. EXPLAIN ANALYZE
  # local (105 mil conversas na conta, 40% com 3 toques): 50 ids em 34 ms; as 184 campanhas da conta em 105 ms. Sem limite
  # de ids: um filtro salvo com muitas campanhas continua funcionando (uma consulta só).
  def toques_sql
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

    sql = ActiveRecord::Base.sanitize_sql_array([toques_sql, { account_id: account.id, ids: ids }])
    ActiveRecord::Base.connection.select_rows(sql).each_with_object({}) do |(id, sinais), classes|
      classes[id] = classes.fetch(id, false) || anuncio?([JSON.parse(sinais)])
    end
  end
end
