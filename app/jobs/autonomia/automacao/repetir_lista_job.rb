# Abre as execuções filhas do passo "para cada um de uma lista" (#2932): ver FilhasDaLista. Fica fora da rodada da mãe,
# para a lista (até 200 por vez) não prender o worker dela.
#
# Com as novas tentativas do Sidekiq: um erro passageiro no meio da lista não pode deixar itens sem os passos. Repetir é
# seguro: a filha que a tentativa anterior já abriu é reconhecida pela marca (índice único automacao_id, evento) e conta
# para o teto sem abrir de novo.
class Autonomia::Automacao::RepetirListaJob < ApplicationJob
  queue_as :medium

  def perform(account_id, mae_id, passo_id)
    mae = ::Autonomia::Automacao::Execucao.find_by(id: mae_id, account_id: account_id)
    passo = mae && ::Autonomia::Automacao::Roteiro.da(mae).passo(passo_id)
    return unless passo && ::Autonomia::Automacao::RepetirLista.do_tipo?(passo)

    contagem = ::Autonomia::Automacao::FilhasDaLista.new(mae, passo).abrir
    Rails.logger.info("[automacao][motor] repetir_lista execucao=#{mae.id} passo=#{passo_id} #{contagem.to_query}")
  end
end
