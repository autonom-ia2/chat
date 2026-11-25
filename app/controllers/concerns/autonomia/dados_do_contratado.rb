# #3211 — o que o "Contratar" e a troca dos dados da corretora têm em comum na API: os três campos da tela (só eles
# passam pelo strong params) e a recusa, 422 com o código do motivo e o campo que a tela destaca (R14; nil no
# `indisponivel`, que nenhum campo resolve).
module Autonomia::DadosDoContratado
  extend ActiveSupport::Concern

  TAMANHOS = ::Autonomia::Agents::Contratados::Contratar::CAMPOS
  CAMPOS = TAMANHOS.keys.map(&:to_sym).freeze

  included do
    rescue_from ::Autonomia::Agents::Contratados::Contratar::Recusado, with: :render_recusa_do_contratado
  end

  private

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
