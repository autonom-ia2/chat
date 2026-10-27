# Depois de ativar o anúncio (#2198, ponto 6): confere a campanha e o grupo. Se um deles não estiver no ar (pausado por
# alguém no Gerenciador, por exemplo), a tela avisa em vez de dizer que o anúncio começou a rodar. O anúncio criado
# aqui sai da lista de pausados.
class Crm::MetaAds::Creation::Activation
  # Situações de entrega que seguram o anúncio, mesmo ativo.
  HOLDING = %w[PAUSED CAMPAIGN_PAUSED ADSET_PAUSED ARCHIVED DELETED].freeze

  def initialize(connection)
    @connection = connection
    @client = Crm::MetaAds::Creation::Access.new(connection).client
  end

  # 'campaign' | 'adset' | nil. Sem leitura, nil: a ativação já aconteceu e não há o que afirmar.
  def held_by(ad_id)
    Crm::MetaAdsCreatedObject.waiting_activation.where(account_id: @connection.account_id, ad_id: ad_id)
                             .find_each { |record| record.update!(activated_at: Time.current) }
    result = @client.ad_budget(ad_id)
    return unless result.ok

    return 'campaign' if paused?(result.data['campaign'])

    'adset' if paused?(result.data['adset'])
  end

  private

  def paused?(object)
    HOLDING.include?(object.to_h['effective_status'])
  end
end
