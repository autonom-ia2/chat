# Apaga as conversas com o Guia paradas há mais de 30 dias (#861). O texto pode
# ter dado pessoal de cliente — nome, telefone, apólice —, e passado o prazo de
# investigar um relato ele não tem por que continuar no banco. Os turnos saem
# junto, pela chave estrangeira.
class Autonomia::Guide::LimparConversasJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    ::Autonomia::Guide::Conversa.vencidas.in_batches(of: 500).delete_all
  end
end
