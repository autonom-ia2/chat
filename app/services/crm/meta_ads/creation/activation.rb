# Ativar anúncio (#2198, ponto 6).
#
# - Anúncio criado aqui (`created_here`): campanha, grupo e anúncio nasceram pausados, e `activate!` liga os três, em
#   ordem, relendo cada um (Crm::MetaAds::Creation::Levels). Sai da lista de pausados.
# - Outro anúncio da conta: a ativação de sempre liga só o anúncio, e `held_by` confere a campanha e o grupo. Se um
#   deles não estiver no ar (pausado no Gerenciador, por exemplo), a tela avisa em vez de dizer que começou a rodar.
class Crm::MetaAds::Creation::Activation
  # Situações de entrega que seguram o anúncio, mesmo ativo.
  HOLDING = %w[PAUSED CAMPAIGN_PAUSED ADSET_PAUSED ARCHIVED DELETED].freeze

  def initialize(connection, user: nil)
    @connection = connection
    @user = user
    @access = Crm::MetaAds::Creation::Access.new(connection)
    @client = @access.client
  end

  # A linha do anúncio criado aqui nesta conta de anúncios, ou nil.
  def created_here(ad_id)
    Crm::MetaAdsCreatedObject.find_by(account_id: @connection.account_id, ad_account_id: @connection.ad_account_id,
                                      ad_id: ad_id.to_s, status: 'created')
  end

  # Liga os três níveis. Erros como os da ativação de sempre (Crm::MetaAds::AdManagement::Error).
  def activate!(record)
    raise Crm::MetaAds::AdManagement::Error, 'cannot_change' unless @access.can_change_ads?

    Crm::MetaAds::Creation::Levels.new(@client, account: @connection.account, user: @user).activate!(record)
    'ACTIVE'
  rescue Crm::MetaAds::Creation::Error => e
    raise Crm::MetaAds::AdManagement::Error, e.code
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
