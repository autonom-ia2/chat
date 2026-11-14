# "Trazer minha lista" (#2896): as listas que a conta já trouxe, o andamento de uma que ainda está entrando e o
# "Desfazer" de uma lista gravada, com a prévia do que ele faria.
#
# O Desfazer pede a mesma permissão das outras rotas (importar contatos): ele só tira o que a própria lista pôs e em que
# ninguém tocou. O clique só marca a lista como "desfazendo" e põe o job na fila; a resposta diz a situação de agora
# ("desfazendo", ou "desfeito" quando ela já tinha sido desfeita). A lista que ainda está entrando é recusada com
# `nao_pode_desfazer`, na prévia também; a que quebrou no meio da gravação pode ser desfeita. Se o job não chega à fila,
# a marca de "desfazendo" volta (a lista não fica presa) e o erro sobe.
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
    desfazer = ::Relacionamentos::Trazer::Desfazer.new(lista)
    pedido = desfazer.pedir
    return recusar_com(pedido.erro) if pedido.erro

    por_na_fila(desfazer) if pedido.enfileirar
    render json: { id: lista.id, situacao: ::Relacionamentos::Trazer::Situacao.de(lista) }, status: :accepted
  end

  private

  # `perform_later` devolve false quando a fila recusa o job, e levanta quando ela está fora do ar.
  def por_na_fila(desfazer)
    raise ActiveJob::EnqueueError, 'desfazer_fora_da_fila' unless ::Relacionamentos::Trazer::DesfazerJob.perform_later(lista, Current.user)
  rescue StandardError
    desfazer.desistir
    raise
  end

  def lista
    @lista ||= ::Relacionamentos::Trazer::Situacao.no_historico(importacoes).find(params[:id])
  end
end
