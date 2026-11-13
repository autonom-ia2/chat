# Base das rotas da carteira de seguros (E4, #2897). Além do que a Lista de Relacionamentos já pede (a chave das telas
# novas e a permissão de ver contatos), a conta precisa ter a carteira (Carteira::Acesso): sem ela, toda rota responde
# 404, como se não existisse.
#
# Seguro é dado da ficha, do nível das notas do contato, e a permissão é a do contato (sem policy própria): ver o seguro
# é poder ver a pessoa (`show?`) e mudar é poder editá-la (`update?`). Função personalizada sem `contact_view` recebe 401.
# O seguro é sempre achado dentro da conta de quem pede: o de outra conta responde 404.
#
# O corpo de erro da carteira nunca repete o que a pessoa mandou: a recusa é um código (CustomExceptions::CarteiraRecusa),
# e o pedido que a carteira não conhece responde só `pedido_invalido`.
class Api::V1::Accounts::Relacionamentos::CarteiraController < Api::V1::Accounts::Relacionamentos::BaseController
  # O corpo chega como a tela manda, sem o envelope do Rails: a chave a mais seria um campo que a ação não conhece.
  wrap_parameters false

  before_action :exigir_carteira

  rescue_from ::Relacionamentos::PedidoInvalido do
    render json: { error: 'pedido_invalido' }, status: :unprocessable_entity
  end
  rescue_from CustomExceptions::CarteiraRecusa, with: :render_error_response

  private

  def exigir_carteira
    head :not_found unless ::Carteira::Acesso.liberada?(Current.account)
  end

  def seguros_da_conta
    ::Carteira::Apolice.where(account_id: Current.account.id).preload(::Carteira::Consulta::O_QUE_A_LINHA_USA)
  end

  def achar_seguro
    @seguro = seguros_da_conta.find(params[:id])
  end

  def poder_ver
    authorize @seguro.contact, :show?
  end

  def poder_editar
    authorize @seguro.contact, :update?
  end

  # Com quem pede: o id do card de renovação só vai no seguro para quem enxerga aquele card no quadro.
  def apresentacao
    ::Carteira::Apresentacao.new(Current.account, quem: pundit_user)
  end

  def responder_seguro(seguro = @seguro)
    render json: apresentacao.de(seguro)
  end

  # O que a ação recebeu, só com os campos dela. O permit descarta em silêncio a chave que não conhece e a que chega no
  # formato errado (valor[]=1): a ação seguiria pela metade. Aqui as duas respondem 422.
  def corpo(*campos)
    recebidas = request.parameters.keys - request.path_parameters.keys.map(&:to_s)
    aceitas = params.permit(*campos).to_h
    recusar('corpo desconhecido') unless (recebidas - aceitas.keys).empty?
    aceitas
  end
end
