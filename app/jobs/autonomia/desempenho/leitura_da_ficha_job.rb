# A rodada da leitura automática de UM agente (#2301), enfileirada pelo LeituraAutomaticaJob da conta.
# Cada tentativa paga chamadas de IA de novo: se a rodada cair, ela fica `erro` e o job é descartado, sem nova
# tentativa; a próxima é a do dia seguinte. Confere de novo, na hora de rodar, que a leitura segue ligada e que a ficha
# ainda é a vigente com chave de leitura.
class Autonomia::Desempenho::LeituraDaFichaJob < ApplicationJob
  queue_as :low
  discard_on StandardError

  def perform(account_id, ficha_id)
    return unless ::Autonomia::Desempenho::LeituraAutomatica::Orquestrador.ligada?

    ficha = ::Autonomia::Desempenho::Ficha.find_by(id: ficha_id, account_id: account_id)
    return unless ficha&.chave_de_leitura.present? && vigente?(ficha)

    ::Autonomia::Desempenho::LeituraAutomatica::Orquestrador.new(ficha).call
  end

  private

  def vigente?(ficha) = ::Autonomia::Desempenho::Ficha.vigente(ficha.account, ficha.sujeito_type, ficha.sujeito_id)&.id == ficha.id
end
