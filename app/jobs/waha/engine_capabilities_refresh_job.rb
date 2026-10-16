# Lê a capacidade de mensagem rica nativa de cada motor de `WAHA_RICH_NATIVE_ENGINES` e grava no cache (chat#1709,
# fase 2). Roda a cada 5 minutos (config/schedule.yml); o cache dura 10 (cobre duas rodadas com falha). Não faz HTTP
# sem lista no ENV nem quando nenhuma conta tem a flag `whatsapp_rich_native` (uma consulta por rodada). Um motor que
# falha não para os outros, e o valor anterior dele segue até expirar (Waha::EngineCapabilities::CACHE_TTL). O
# caminho de escrita e a lista de conversas só leem esse cache.
class Waha::EngineCapabilitiesRefreshJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    engines = Waha::EngineCapabilities.engines
    return if engines.empty? || !Account.feature_whatsapp_rich_native.exists?

    engines.each { |engine| Waha::EngineCapabilities.refresh!(engine) }
  end
end
