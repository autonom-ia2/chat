# #3211 — o que a API do agente contratado tem em comum: os três campos da tela do "Contratar" e da troca dos dados da
# corretora (só eles passam pelo strong params), a recusa, 422 com o código do motivo e o campo que a tela destaca
# (R14; nil no `indisponivel`, que nenhum campo resolve), e a busca do agente das rotas `agents/:agent_id/...`.
module Autonomia::DadosDoContratado
  extend ActiveSupport::Concern

  TAMANHOS = ::Autonomia::Agents::Contratados::Contratar::CAMPOS
  CAMPOS = TAMANHOS.keys.map(&:to_sym).freeze

  included do
    rescue_from ::Autonomia::Agents::Contratados::Contratar::Recusado, with: :render_recusa_do_contratado
  end

  private

  # Agente da conta (fora os de sistema e os apagados) e contratado; o resto é 404.
  def buscar_contratado
    @agent = agents_scope.find(params[:agent_id])
    raise ActiveRecord::RecordNotFound unless @agent.contratado?
  end

  # Sempre as três chaves (a ausente vai como nil, e a conferência do `Contratar` a recusa pelo tamanho).
  def dados_da_corretora
    permitidos = params.permit(*CAMPOS)
    CAMPOS.index_with { |campo| permitidos[campo] }
  end

  def render_recusa_do_contratado(error)
    texto = I18n.t("autonomia.contratados.recusa.#{error.motivo}", maximo: TAMANHOS[error.motivo]&.max)
    render json: { error: texto, code: error.motivo, campo: error.campo }, status: :unprocessable_entity
  end
end
