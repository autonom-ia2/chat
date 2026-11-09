# "Pausados, esperando você ativar" (#2198, ponto 9): os anúncios que a plataforma criou e que continuam pausados,
# lidos na Meta um a um (a lista não varre a conta de anúncios). O orçamento vem do que foi gravado ao criar. Ativado
# por aqui não é lido de novo; ativado no Gerenciador da Meta (`status` ACTIVE) some porque já não está pausado, e a
# leitura grava a ativação (#2739), como o Ativar daqui: o post impulsionado ganha "Teve anúncio" em Seus posts e o
# anúncio não é lido de novo. Só os da conta de anúncios conectada agora: depois de trocar de conta, os da anterior
# não aparecem. Esta lista só lê os LIMIT mais novos: os outros são lidos de hora em hora por
# Crm::MetaAds::Creation::ActivationSweep (#2804). A mídia do anúncio no Instagram, que veio na mesma leitura, fica
# guardada (Crm::MetaAds::Creation::AdMedia).
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
      next unless result.ok

      Crm::MetaAds::Creation::AdMedia.remember(record, result.data)
      result.data['status'] == 'ACTIVE' ? activated!(record) : paused_row(record, result.data)
    end
  end

  private

  def paused_row(record, meta_ad)
    return unless meta_ad['status'] == 'PAUSED'

    in_review = Crm::MetaAds::AdManagement.in_review?(meta_ad['status'], meta_ad['effective_status'])
    return unless in_review || READY.include?(meta_ad['effective_status'])

    { ad_id: record.ad_id, name: record.name, created_at: record.created_at.iso8601,
      budget: record.budget.merge('active_ads_count' => 0), in_review: in_review }
  end

  # nil: o anúncio ligado sai da lista. Sem gravar, a lista sai mesmo assim e a próxima leitura tenta de novo, como o
  # Ativar daqui (Crm::MetaAds::Creation::Levels#mark_activated).
  def activated!(record)
    record.update!(activated_at: Time.current)
    nil
  rescue ActiveRecord::ActiveRecordError => e
    ChatwootExceptionTracker.new(e, account: @connection.account).capture_exception
    nil
  end

  def records
    Crm::MetaAdsCreatedObject.waiting_activation.where(account_id: @connection.account_id, ad_account_id: @connection.ad_account_id)
                             .order(created_at: :desc).limit(LIMIT)
  end
end
