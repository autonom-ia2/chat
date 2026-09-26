# Quem vê o quê na Prospecção (#732). Um objeto por pessoa na conta (AccountUser):
# - buscas (item 6; MOTOR-37, ACAO-33, CARD-59): o agente vê, exporta e exclui só as próprias. O administrador, e quem
#   tem a chave "Ver buscas de todos", vê todas. Os leads seguem a busca: o agente vê o lead que voltou numa busca dele
#   ou que está numa lista, porque as listas são da conta.
# - detalhe técnico da nota (item 9; MODO-51, PLAT-05): componentes, pesos, motor e fatores negativos só vão para o
#   administrador da conta. Os outros recebem a faixa (nota e prioridade) e a frase.
class Autonomia::Prospecting::Visibility
  VIEW_ALL_SEARCHES = 'prospecting_view_all_searches'.freeze
  TECHNICAL_SCORE_FIELDS = %w[score_breakdown negative_factors].freeze

  # Os ids de metadata['lead_ids'] de cada busca, como o SearchRunner grava (número ou texto). Coluna que não é array
  # conta como nenhum lead.
  SEARCH_LEAD_IDS_SQL = <<~SQL.squish.freeze
    jsonb_array_elements_text(
      CASE WHEN jsonb_typeof(autonomia_prospecting_searches.metadata->'lead_ids') = 'array'
           THEN autonomia_prospecting_searches.metadata->'lead_ids' ELSE '[]'::jsonb END
    )::bigint
  SQL

  attr_reader :account_user

  def initialize(account_user)
    @account_user = account_user
  end

  def all_searches?
    return @all_searches if defined?(@all_searches)

    @all_searches = account_user.present? && account_user.permission_granted?(VIEW_ALL_SEARCHES)
  end

  def score_details?
    account_user&.administrator? || false
  end

  def searches(scope)
    return scope if all_searches?
    return scope.none if account_user.nil?

    scope.where(user_id: account_user.user_id)
  end

  def leads(scope)
    return scope if all_searches?
    return scope.none if account_user.nil?

    own_searches = searches(Autonomia::Prospecting::Search.where(account_id: account_user.account_id))
    list_lead_ids = Autonomia::Prospecting::ListLead.where(account_id: account_user.account_id).select(:prospect_lead_id)

    scope.where(prospect_search_id: own_searches.select(:id))
         .or(scope.where(id: own_searches.select(Arel.sql(SEARCH_LEAD_IDS_SQL))))
         .or(scope.where(id: list_lead_ids))
  end

  def lead_visible?(lead)
    all_searches? || leads(Autonomia::Prospecting::Lead.where(id: lead.id)).exists?
  end

  # O lead como a API o devolve (chaves texto ou símbolo), sem o bloco técnico para quem não é administrador.
  def lead_payload(payload)
    return payload if score_details?

    payload.except(*TECHNICAL_SCORE_FIELDS, *TECHNICAL_SCORE_FIELDS.map(&:to_sym))
  end
end
