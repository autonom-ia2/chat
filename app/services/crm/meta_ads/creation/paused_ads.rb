# "Pausados, esperando você ativar" (#2198, ponto 9): os anúncios que a plataforma criou e que continuam pausados,
# lidos na Meta um a um (a lista não varre a conta de anúncios). O orçamento vem do que foi gravado ao criar. Ativado
# por aqui não é lido de novo; ativado no Gerenciador da Meta some porque já não está pausado. Só os da conta de
# anúncios conectada agora: depois de trocar de conta, os da anterior não aparecem.
class Crm::MetaAds::Creation::PausedAds
  LIMIT = 20

  def initialize(connection)
    @connection = connection
    @client = Crm::MetaAds::Creation::Access.new(connection).client
  end

  def list
    records.filter_map do |record|
      result = @client.ad_management(record.ad_id)
      raise Crm::MetaAds::Creation::Error, 'meta_unavailable' if result.transient?
      next unless result.ok && result.data['effective_status'] == 'PAUSED'

      { ad_id: record.ad_id, name: record.name, created_at: record.created_at.iso8601,
        budget: record.budget.merge('active_ads_count' => 0) }
    end
  end

  private

  def records
    Crm::MetaAdsCreatedObject.waiting_activation.where(account_id: @connection.account_id, ad_account_id: @connection.ad_account_id)
                             .order(created_at: :desc).limit(LIMIT)
  end
end
