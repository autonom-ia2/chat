# "Trazer minha lista" (#2896): as listas que a conta já trouxe, o andamento de uma que ainda está entrando e o
# "Desfazer" de uma lista gravada, com a prévia do que ele faria.
#
# O Desfazer pede a mesma permissão das outras rotas (importar contatos): ele só tira o que a própria lista pôs e em que
# ninguém tocou. O clique só marca a lista como "desfazendo" e põe o job na fila; a resposta diz a situação de agora
# ("desfazendo", ou "desfeito" quando ela já tinha sido desfeita). A lista que ainda não foi gravada (entrando, ou que
# falhou no meio) é recusada com `nao_pode_desfazer`, na prévia também.
class Api::V1::Accounts::Relacionamentos::Trazer::ListasController < Api::V1::Accounts::Relacionamentos::Trazer::BaseController
  NAO_PODE = ::Relacionamentos::Trazer::Desfazer::NAO_PODE

  def index
    render json: ::Relacionamentos::Trazer::Historico.new(importacoes).call
  end

  # GET listas/:id/andamento
  def andamento
    render json: ::Relacionamentos::Trazer::Andamento.new(lista).call
  end

  # GET listas/:id/previa_do_desfazer
  def previa_do_desfazer
    return recusar_com(NAO_PODE) unless ::Relacionamentos::Trazer::Desfazer.pode?(lista)

    render json: ::Relacionamentos::Trazer::PreviaDoDesfazer.new(lista).call
  end

  # POST listas/:id/desfazer
  def desfazer
    pedido = ::Relacionamentos::Trazer::Desfazer.new(lista).pedir
    return recusar_com(pedido.erro) if pedido.erro

    ::Relacionamentos::Trazer::DesfazerJob.perform_later(lista, Current.user) if pedido.enfileirar
    render json: { id: lista.id, situacao: ::Relacionamentos::Trazer::Situacao.de(lista) }, status: :accepted
  end

  private

  def lista
    @lista ||= ::Relacionamentos::Trazer::Situacao.no_historico(importacoes).find(params[:id])
  end
end
