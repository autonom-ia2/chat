# Lê a capacidade de mensagem rica nativa de cada motor de `WAHA_RICH_NATIVE_ENGINES` e grava no cache (chat#1709,
# fase 2). Roda a cada minuto (config/schedule.yml), no segundo 25, fora do segundo 0 dos outros crons de minuto. Sem
# lista no ENV, não faz nada. Um motor que falha não para os outros, e o valor anterior dele segue até expirar
# (Waha::EngineCapabilities::CACHE_TTL). O caminho de escrita e a lista de conversas só leem esse cache.
class Waha::EngineCapabilitiesRefreshJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Waha::EngineCapabilities.engines.each { |engine| Waha::EngineCapabilities.refresh!(engine) }
  end
end
