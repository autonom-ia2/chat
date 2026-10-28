# Ativar e pausar anúncio (#2198, ponto 6).
#
# - Anúncio criado aqui (`created_here`): campanha, grupo e anúncio nasceram pausados. `change!` liga os três, em
#   ordem, relendo cada um, ou pausa os três, do anúncio para a campanha (Crm::MetaAds::Creation::Levels). Ativado,
#   sai da lista de pausados. Enquanto um clique liga ou pausa, a linha fica travada (`switching_at`, por UPDATE
#   condicional) e um segundo clique recebe `in_progress`.
# - Outro anúncio da conta: a ativação de sempre liga só o anúncio, e `held_by` confere a campanha e o grupo. Se um
#   deles não estiver no ar (pausado no Gerenciador, por exemplo), a tela avisa em vez de dizer que começou a rodar.
class Crm::MetaAds::Creation::Activation
  # Situações de entrega que seguram o anúncio, mesmo ativo.
  HOLDING = %w[PAUSED CAMPAIGN_PAUSED ADSET_PAUSED ARCHIVED DELETED].freeze
  # Trava esquecida (processo caiu no meio): os três níveis, com a volta, cabem nisso com folga
  # (Meta::AdsGraphClient::TIMEOUT_SECONDS por chamada).
  SWITCH_STALE_AFTER = 3.minutes

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

  # Liga (ACTIVE) ou pausa (PAUSED) os três níveis. Erros como os da gestão de sempre (Crm::MetaAds::AdManagement::Error).
  def change!(record, status)
    raise Crm::MetaAds::AdManagement::Error, 'invalid_status' unless Crm::MetaAds::AdManagement::STATUSES.include?(status)
    raise Crm::MetaAds::AdManagement::Error, 'cannot_change' unless @access.can_change_ads?

    hold!(record) do
      levels = Crm::MetaAds::Creation::Levels.new(@client, account: @connection.account, user: @user)
      status == 'ACTIVE' ? levels.activate!(record) : levels.pause!(record)
    end
    status
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

  def hold!(record)
    scope = Crm::MetaAdsCreatedObject.where(id: record.id)
    taken = scope.where(switching_at: nil).or(scope.where(switching_at: ...SWITCH_STALE_AFTER.ago))
                 .update_all(switching_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    raise Crm::MetaAds::AdManagement::Error, 'in_progress' unless taken == 1

    begin
      yield
    ensure
      scope.update_all(switching_at: nil) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def paused?(object)
    HOLDING.include?(object.to_h['effective_status'])
  end
end
