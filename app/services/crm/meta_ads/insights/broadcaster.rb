# Avisa a tela aberta que a leitura de hoje terminou (#1073, CA-2.8): a tela troca os números sem recarregar.
# Vai só para os administradores da conta, os únicos que veem Anúncios da Meta.
class Crm::MetaAds::Insights::Broadcaster
  include Events::Types

  def self.broadcast(connection)
    tokens = connection.account.administrators.filter_map(&:pubsub_token)
    return if tokens.empty?

    payload = { account_id: connection.account_id }.merge(Crm::MetaAds::Insights::Summary.payload(connection, refreshing: false))
    ActionCableBroadcastJob.perform_later(tokens, CRM_META_ADS_INSIGHTS_UPDATED, payload)
  end
end
