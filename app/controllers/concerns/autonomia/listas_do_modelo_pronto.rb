# #2881 — o pedido de mudança das listas de um modelo pronto de ramo (perguntas, documentos e ferramentas), igual nos
# dois endereços: pela conversa do Construtor (`build_threads/:id/modelo_pronto`) e pelo rascunho do agente
# (`agents/:agent_id/modelo_pronto`, quando a tela reabre o rascunho sem a conversa). Cada lista que vem substitui a
# lista inteira; a que não vem (ou vem `null`) fica como está. Nenhuma chamada de IA.
# Sem modelo (conta sem o pacote `seguros`, flag desligada, a Lia, agente que não nasceu de um modelo): 404
# `sem_modelo`. Lista fora do formato ou agente que já começou a atender: 422 com o motivo e o campo. Nada é gravado
# quando algo é recusado.
module Autonomia::ListasDoModeloPronto
  extend ActiveSupport::Concern

  LISTAS_DO_MODELO = %i[perguntas documentos ferramentas].freeze

  included do
    rescue_from ::Autonomia::Agents::ModelosDeRamo::Edicao::Recusada, with: :render_modelo_recusado
  end

  private

  # `alvo`: `thread:` (a conversa) ou `agent:` (o rascunho sem conversa na tela).
  def editar_modelo_pronto(**alvo)
    campo = lista_malformada
    raise ::Autonomia::Agents::ModelosDeRamo::Edicao::Recusada.new('lista_invalida', campo.to_s) if campo

    ::Autonomia::Agents::ModelosDeRamo::Edicao.new(mudancas: mudancas_do_modelo, **alvo).call
  end

  # Os tipos de cada campo ficam declarados aqui (é o que o Guia lê): texto em tudo, verdadeiro ou falso em `tirada`.
  def mudancas_do_modelo
    params.permit(perguntas: %i[id texto tirada], documentos: %i[id texto tirada], ferramentas: %i[fonte usar_quando])
          .to_h.slice(*LISTAS_DO_MODELO.reject { |campo| params[campo].nil? })
  end

  # A lista que veio e não é uma lista de objetos (texto solto, número, lista de textos): o `permit` a esvaziaria em
  # silêncio, e uma lista vazia aqui quer dizer "tirar tudo".
  def lista_malformada
    LISTAS_DO_MODELO.find do |campo|
      valor = params[campo]
      !valor.nil? && !(valor.is_a?(Array) && valor.all?(ActionController::Parameters))
    end
  end

  # 404 quando não há modelo pronto; 422 com o motivo (e o campo) no que foi recusado.
  def render_modelo_recusado(erro)
    status = erro.motivo == 'sem_modelo' ? :not_found : :unprocessable_entity
    render json: { motivo: erro.motivo, campo: erro.campo }, status: status
  end
end
