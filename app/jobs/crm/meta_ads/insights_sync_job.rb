# Uma leitura de insights de uma conexão (#1073). Ver Crm::MetaAds::Insights::Sync.
#
# Quem enfileira já pegou a trava do escopo (Crm::MetaAds::Insights::Refresh); o job a solta no fim, dê certo
# ou não. Depois da leitura de hoje, avisa a tela aberta, mesmo quando a leitura falhou: assim o
# "atualizando…" some e a tela mostra o que tem.
class Crm::MetaAds::InsightsSyncJob < ApplicationJob
  queue_as :low

  def perform(connection_id, scope)
    connection = Crm::MetaAdsConnection.find_by(id: connection_id)
    return if connection.blank?

    Crm::MetaAds::Insights::Sync.new(connection).perform(scope)
    Crm::MetaAds::Insights::Broadcaster.broadcast(connection.reload) if scope == Crm::MetaAds::Insights::Refresh::TODAY
  ensure
    Crm::MetaAds::Insights::Refresh.release(connection_id, scope)
  end
end
