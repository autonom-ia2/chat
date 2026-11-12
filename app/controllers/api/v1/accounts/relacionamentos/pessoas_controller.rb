# A aba Pessoas da Lista nova de Relacionamentos (#2894): a página, o número de cada grupo e a consulta inteira.
class Api::V1::Accounts::Relacionamentos::PessoasController < Api::V1::Accounts::Relacionamentos::BaseController
  def index
    @consulta = consulta
  end

  def contagens
    render json: consulta.contagens
  end

  # Para "Marcar todas as N": sem página e sem teto.
  def todas
    itens = consulta.todos
    render json: { itens: itens, total: itens.size }
  end

  private

  def consulta
    ::Relacionamentos::ConsultaDePessoas.new(Current.account, pedido)
  end

  def pedido
    conferido(params.permit(:grupo, :busca, :ordem, :pagina, filtros: [:empresa, :etiqueta, :cidade, :chegou_em]))
  end
end
