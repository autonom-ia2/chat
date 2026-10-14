# #1181 — base das leituras da nova jornada de Agentes. Os filtros da base de Agentes rodam antes (módulo
# desligado → 404; leitura exige autonomia_view); aqui fecha também a flag da conta (desligada → 404).
# before_action comum, não prepend: Current.account só existe depois do filtro da conta.
class Api::V1::Accounts::Autonomia::JornadaBaseController < Api::V1::Accounts::Autonomia::BaseController
  FLAG = 'autonomia_agents_journey'.freeze

  before_action :ensure_jornada_enabled

  private

  def ensure_jornada_enabled
    head :not_found unless Current.account.feature_enabled?(FLAG)
  end
end
