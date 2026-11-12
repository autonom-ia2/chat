# Base das leituras da Lista nova de Relacionamentos (#2894) e da ficha (#2895): só com a chave da conta ligada (404 sem
# ela) e com a mesma permissão de ver contatos de hoje. Pedido que a lista não conhece (grupo, ordem, página, filtro)
# responde 422; a ficha não aceita parâmetro nenhum.
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

  # As leituras da ficha não têm filtro nem página: o que vier na consulta é pedido que a ficha não conhece.
  def sem_parametros
    desconhecido = request.query_parameters.keys.first
    recusar("parâmetro desconhecido: #{desconhecido}") if desconhecido
  end

  # As conversas destas pessoas que quem pede pode ler: a regra do histórico do contato de hoje.
  def conversas_legiveis_de(pessoas)
    ::Contacts::ConversasLegiveis.call(pessoas, user: Current.user, account: Current.account)
  end

  # Os cards da ficha, para quem vê o CRM, como os funis da lista: com o CRM desligado a lista vem vazia. O bloco recebe
  # os cards que a pessoa enxerga no CRM e escolhe os da ficha.
  def responder_cards(com_pessoa: false)
    authorize ::Crm::Card, :index?
    return render json: [] unless ::Crm::Config.enabled?

    cards = yield policy_scope(::Crm::Card)
    render json: ::Relacionamentos::Ficha::Cards.new(cards, Current.account_user, com_pessoa: com_pessoa).call
  end
end
