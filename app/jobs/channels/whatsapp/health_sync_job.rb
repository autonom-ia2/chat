class Channels::Whatsapp::HealthSyncJob < ApplicationJob
  queue_as :low

  def perform(whatsapp_channel)
    Whatsapp::HealthService.new(whatsapp_channel).sync_health_status!
    # #935 — a saúde do WhatsApp mudou de leitura: o Guia mede já (só antecipa).
    ::Autonomia::Guide::Pulso.agora(whatsapp_channel.account)
  rescue Whatsapp::HealthService::ApiError, ArgumentError
    nil
  end
end
