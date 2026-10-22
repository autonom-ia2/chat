# Avisa a tela aberta que a leitura de hoje terminou (#1073, CA-2.8): a tela troca os números sem recarregar.
# Vai para quem vê Anúncios da Meta: administrador ou função com `meta_ads_view`/`meta_ads_manage` (#2070), a mesma
# regra da tela (Crm::MetaAdsConnectionPolicy#show?).
class Crm::MetaAds::Insights::Broadcaster
  include Events::Types

  THROTTLE = 30.seconds
  THROTTLE_PREFIX = 'crm:meta_ads:insights:broadcast'.freeze

  # Para avisos que podem vir em rajada (uma ligação conversa → anúncio por conversa nova): no máximo um por
  # conexão a cada THROTTLE. O que cair dentro da janela chega na próxima conferência da tela (a cada 2 min).
  def self.broadcast_throttled(connection)
    return unless Redis::Alfred.set("#{THROTTLE_PREFIX}:#{connection.id}", 1, nx: true, ex: THROTTLE.to_i)

    broadcast(connection)
  end

  def self.broadcast(connection)
    tokens = recipients(connection.account_id).filter_map { |account_user| account_user.user.pubsub_token }
    return if tokens.empty?

    payload = { account_id: connection.account_id }.merge(Crm::MetaAds::Insights::Summary.payload(connection, refreshing: false))
    ActionCableBroadcastJob.perform_later(tokens, CRM_META_ADS_INSIGHTS_UPDATED, payload)
  end

  # Duas leituras fixas (membros com usuário e, no EE, as funções), sem consulta por pessoa. `custom_role` só existe
  # no EE: carregar a associação no OSS levanta AssociationNotFound (como em Crm::Ai::UsageBroadcaster).
  def self.recipients(account_id)
    relation = AccountUser.human.where(account_id: account_id).includes(:user)
    relation = relation.includes(:custom_role) if AccountUser.reflect_on_association(:custom_role)
    relation.select { |account_user| account_user.permission_granted?('meta_ads_view') }
  end
  private_class_method :recipients
end
