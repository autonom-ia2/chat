# "Trazer minha lista" (#2896): as listas que a conta já trouxe e o andamento de uma que ainda está entrando.
class Api::V1::Accounts::Relacionamentos::Trazer::ListasController < Api::V1::Accounts::Relacionamentos::Trazer::BaseController
  def index
    render json: ::Relacionamentos::Trazer::Historico.new(importacoes).call
  end

  # GET listas/:id/andamento
  def andamento
    lista = ::Relacionamentos::Trazer::Situacao.no_historico(importacoes).find(params[:id])
    render json: ::Relacionamentos::Trazer::Andamento.new(lista).call
  end
end
