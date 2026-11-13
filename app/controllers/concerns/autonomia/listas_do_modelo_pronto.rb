# #2881 — o pedido de mudança das listas de um modelo pronto de ramo (perguntas, documentos e ferramentas), igual nos
# dois endereços: pela conversa do Construtor (`build_threads/:id/modelo_pronto`) e pelo agente
# (`agents/:agent_id/modelo_pronto`: o rascunho reaberto sem a conversa e, depois do "Começar", a página do agente). Cada lista que vem substitui a
# lista inteira; a que não vem (ou vem `null`) fica como está. Nenhuma chamada de IA.
# Permissão: perguntas e documentos, `autonomia_manage`; a lista de ferramentas, também `autonomia_tools_manage`.
# Sem modelo (conta sem o pacote `seguros`, flag desligada, agente que não nasceu de um modelo; a Lia, pelo endereço do
# agente): 404 `sem_modelo`. Lista fora do formato, ou o que não muda mais no agente que já começou a atender (tudo
# pela conversa; as ferramentas pelo agente): 422 com o motivo e o campo. A
# Lia pela conversa e o agente em modo manual: 422, de cada controller, antes de chegar aqui. Nada é gravado quando
# algo é recusado.
module Autonomia::ListasDoModeloPronto
  extend ActiveSupport::Concern

  LISTAS_DO_MODELO = %i[perguntas documentos ferramentas].freeze

  included do
    rescue_from ::Autonomia::Agents::ModelosDeRamo::Edicao::Recusada, with: :render_modelo_recusado
  end

  private

  # `alvo`: `thread:` (a conversa) ou `agent:` (o rascunho sem conversa na tela, ou o agente que já atende).
  def editar_modelo_pronto(**alvo)
    campo = lista_malformada
    raise ::Autonomia::Agents::ModelosDeRamo::Edicao::Recusada.new('lista_invalida', campo.to_s) if campo

    ::Autonomia::Agents::ModelosDeRamo::Edicao.new(mudancas: mudancas_do_modelo, actor: Current.user, **alvo).call
  end

  # Perguntas e documentos pedem a escrita da área de Agentes (`autonomia_manage`, conferida na entrada). A lista de
  # ferramentas (tirar, incluir, mudar a frase "Use quando", que vira a descrição da ferramenta para o agente) é assunto
  # da chave "Ferramentas dos agentes", como na vitrine: quem não a tem não mexe em ferramenta por aqui. A equipe da
  # plataforma sempre. Cada controller chama isto num `before_action` da ação que edita as listas: é conferência de
  # permissão, antes da ação, e não parte do pedido.
  def conferir_chave_de_ferramentas!
    return if params[:ferramentas].nil? || Current.user.is_a?(SuperAdmin)

    check_permission_granted!('autonomia_tools_manage')
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
