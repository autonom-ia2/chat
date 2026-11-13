# O selo de seguro das pessoas de uma página da lista de pessoas (E4, #2897): a tela manda os ids da página que acabou
# de mostrar (`pessoa_ids[]`) e recebe, de quem tem seguro, quantos são e o selo do que mais pede atenção. Pede o mesmo
# que a lista de pessoas: poder ver contatos. Pessoa de outra conta não vem. Pedido sem os ids, com id que não é número
# ou com parâmetro que a leitura não conhece responde 422.
class Api::V1::Accounts::Relacionamentos::Seguros::ResumoPorDonoController < Api::V1::Accounts::Relacionamentos::CarteiraController
  PARAMETROS = %w[pessoa_ids].freeze

  def show
    recusar('parâmetro desconhecido') unless (request.query_parameters.keys - PARAMETROS).empty?

    render json: ::Carteira::ResumoPorPessoa.new(Current.account, params[:pessoa_ids]).call
  end
end
