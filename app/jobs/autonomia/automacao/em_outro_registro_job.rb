# Abre as execuções filhas do passo "em outro registro" (G18, #2671): ver FilhasDoPasso. Fica fora da rodada da mãe,
# para a procura (sem teto de registros) não prender o worker dela.
#
# Com as novas tentativas do Sidekiq: um erro passageiro no meio da procura não pode deixar registros sem os passos. Repetir
# é seguro: a filha que a tentativa anterior já abriu é reconhecida pela marca (índice único automacao_id, evento) e não
# abre de novo, nem conta como pulada.
class Autonomia::Automacao::EmOutroRegistroJob < ApplicationJob
  queue_as :medium

  def perform(account_id, mae_id, passo_id, contato_id)
    mae = ::Autonomia::Automacao::Execucao.find_by(id: mae_id, account_id: account_id)
    passo = mae && ::Autonomia::Automacao::Roteiro.new(mae.versao.receita).passo(passo_id)
    return unless passo && ::Autonomia::Automacao::EmOutroRegistro.do_tipo?(passo)

    contagem = ::Autonomia::Automacao::FilhasDoPasso.new(mae, passo, contato_id).abrir
    Rails.logger.info("[automacao][motor] em_outro_registro execucao=#{mae.id} passo=#{passo_id} #{contagem.to_query}")
  end
end
