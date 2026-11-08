# Um evento do card na Automação livre (#2499, F6): ver Autonomia::Automacao::Escuta.evento_do_card.
#
# Job próprio, fora do EventDispatcherJob: o erro sobe aqui e o Sidekiq tenta de novo só a parte da automação, sem
# repetir os outros listeners (webhook, Meta, Google). Repetir é seguro: a marca da atividade (índice único
# automacao_id + evento) não deixa o mesmo evento abrir duas execuções.
#
# A cadeia de automações (laço, profundidade) vem nos argumentos, como no evento: o job roda em outra thread, sem ela.
class Autonomia::Automacao::EventoDoCardJob < ApplicationJob
  CHAVE_DA_CADEIA = 'autonomia_cadeia'.freeze

  queue_as :medium

  def perform(dados, evento)
    cadeia = dados[CHAVE_DA_CADEIA].to_h
    dados = dados.except(CHAVE_DA_CADEIA)
    return ::Autonomia::Automacao::Escuta.evento_do_card(dados, evento) if cadeia.blank?

    ::Autonomia::Automacao::Cadeia.retomar(cadeia['origens'], Account.find_by(id: cadeia['conta']), cadeia['raiz']) do
      ::Autonomia::Automacao::Escuta.evento_do_card(dados, evento)
    end
  end
end
