# Apaga os avisos do Guia com mais de 30 dias (#935), e a notificação de cada um junto. Passado esse
# tempo o aviso já não serve para nada: o que ele mediu mudou.
class Autonomia::Guide::LimparAvisosJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    ::Autonomia::Guide::Aviso.where(created_at: ...::Autonomia::Guide::Aviso::VALIDADE.ago).in_batches(of: 500) do |lote|
      Notification.where(primary_actor_type: ::Autonomia::Guide::Aviso.name, primary_actor_id: lote.select(:id)).delete_all
      lote.delete_all
    end
  end
end
