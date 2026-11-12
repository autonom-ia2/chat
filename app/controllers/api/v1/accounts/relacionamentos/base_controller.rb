# Base das leituras da Lista nova de Relacionamentos (#2894): só com a chave da conta ligada (404 sem ela) e com a mesma
# permissão de ver contatos de hoje. Pedido que a lista não conhece (grupo, ordem, página, filtro) responde 422.
class Api::V1::Accounts::Relacionamentos::BaseController < Api::V1::Accounts::BaseController
  CHAVES_DO_PEDIDO = %w[grupo busca ordem pagina filtros].freeze

  # De quem a pessoa precisa poder ver a lista (a policy de hoje); a aba Empresas troca por Company.
  class_attribute :registro_da_permissao, instance_writer: false, default: Contact

  before_action :exigir_chave
  before_action :conferir_permissao

  rescue_from ::Relacionamentos::PedidoInvalido do |erro|
    render json: { error: erro.message }, status: :unprocessable_entity
  end

  private

  def exigir_chave
    head :not_found unless Current.account.feature_enabled?('relacionamentos_novo')
  end

  def conferir_permissao
    authorize(registro_da_permissao, :index?)
  end

  # O permit descarta em silêncio o que chega no formato errado (grupo[]=x, filtros=abc) e o filtro que a lista não tem:
  # o pedido seguiria sem filtro, e "Marcar todas" marcaria a base inteira. Aqui, o que a tela mandou e o permit não
  # deixou passar responde 422. `permitido` é o params.permit de cada lista.
  def conferido(permitido)
    recebido = request.parameters.slice(*CHAVES_DO_PEDIDO)
    aceito = permitido.to_h
    filtros = recebido['filtros']
    conferir_filtros(filtros, aceito.fetch('filtros', {})) if filtros.is_a?(Hash)
    fora = (recebido.keys - aceito.keys).find { |chave| chave != 'filtros' || !filtros.is_a?(Hash) }
    recusar("#{fora} em formato inválido") if fora
    permitido
  end

  def conferir_filtros(recebidos, aceitos)
    fora = (recebidos.keys - aceitos.keys).first
    return unless fora

    recusar(recebidos[fora].is_a?(String) ? "filtro desconhecido: #{fora}" : "filtros[#{fora}] em formato inválido")
  end

  def recusar(mensagem)
    raise ::Relacionamentos::PedidoInvalido, mensagem
  end
end
