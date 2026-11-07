# Abre as execuções filhas do passo "em outro registro" (G18, #2671): ver FilhasDoPasso. Fica fora da rodada da mãe,
# para a procura (sem teto de registros) não prender o worker dela.
#
# Sem nova tentativa do Sidekiq: repetir abriria de novo só o que o índice único deixa, mas um erro no meio fica no log
# e as filhas já abertas seguem.
class Autonomia::Automacao::EmOutroRegistroJob < ApplicationJob
  queue_as :medium
  sidekiq_options retry: false

  def perform(mae_id, passo_id, contato_id)
    mae = ::Autonomia::Automacao::Execucao.find_by(id: mae_id)
    passo = mae && ::Autonomia::Automacao::Roteiro.new(mae.versao.receita).passo(passo_id)
    return unless passo && ::Autonomia::Automacao::EmOutroRegistro.do_tipo?(passo)

    abertas = ::Autonomia::Automacao::FilhasDoPasso.new(mae, passo, contato_id).abrir
    Rails.logger.info("[automacao][motor] em_outro_registro execucao=#{mae.id} passo=#{passo_id} filhas=#{abertas}")
  end
end
