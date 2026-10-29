# "Pausados, esperando você ativar" (#2198, ponto 9): os anúncios que a plataforma criou e que continuam pausados,
# lidos na Meta um a um (a lista não varre a conta de anúncios). O orçamento vem do que foi gravado ao criar. Ativado
# por aqui não é lido de novo; ativado no Gerenciador da Meta some porque já não está pausado. Só os da conta de
# anúncios conectada agora: depois de trocar de conta, os da anterior não aparecem.
#
# Por classe de `effective_status` (#2354, enum da doc do Ad), com o próprio anúncio PAUSED: `PAUSED`, `CAMPAIGN_PAUSED`
# e `ADSET_PAUSED` estão prontos para ativar (os dois últimos por regra, não vistos em leitura real: o Ativar de um
# anúncio criado aqui liga os três níveis); `PENDING_REVIEW` e
# `IN_PROCESS` estão em análise da Meta (`in_review`: a tela avisa e não oferece ativar); o resto (recusado, com
# problema, conta sem pagamento, arquivado…) fica fora, como antes.
class Crm::MetaAds::Creation::PausedAds
  LIMIT = 20
  READY = %w[PAUSED CAMPAIGN_PAUSED ADSET_PAUSED].freeze

  def initialize(connection)
    @connection = connection
    @client = Crm::MetaAds::Creation::Access.new(connection).client
  end

  def list
    records.filter_map do |record|
      result = @client.ad_management(record.ad_id)
      raise Crm::MetaAds::Creation::Error, 'meta_unavailable' if result.transient?
      next unless result.ok && result.data['status'] == 'PAUSED'

      in_review = Crm::MetaAds::AdManagement.in_review?(result.data['status'], result.data['effective_status'])
      next unless in_review || READY.include?(result.data['effective_status'])

      { ad_id: record.ad_id, name: record.name, created_at: record.created_at.iso8601,
        budget: record.budget.merge('active_ads_count' => 0), in_review: in_review }
    end
  end

  private

  def records
    Crm::MetaAdsCreatedObject.waiting_activation.where(account_id: @connection.account_id, ad_account_id: @connection.ad_account_id)
                             .order(created_at: :desc).limit(LIMIT)
  end
end
