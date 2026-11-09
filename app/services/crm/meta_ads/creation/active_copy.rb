# A cópia com a foto ou o texto novos que está no ar no lugar deste anúncio (#2804). É ela que faz o "Pausar o original"
# continuar na tela depois de recarregar, enquanto o original também está ativo.
#
# A ligação entre a cópia e o original é a Auditoria `meta_ads_ad_copied` (`source_ad_id`, `ad_id` e `new_creative`),
# gravada quando a cópia nasce. Vale a cópia criada aqui, nesta conta de anúncios, ativada pela pessoa (`activated_at`) e
# que a Meta diz estar ligada agora: `status` ACTIVE e a entrega sem campanha ou grupo pausados
# (Crm::MetaAds::Creation::Activation::HOLDING). Sem resposta da Meta, não há botão.
#
# Só a resposta "ligada" fica guardada por CACHE_FOR, por conta e anúncio original: cada abertura do detalhe chamaria a
# Graph. A cópia desligada depois aparece no máximo por esse tempo, e o "Pausar o original" ainda pede confirmação.
class Crm::MetaAds::Creation::ActiveCopy
  CACHE_FOR = 5.minutes

  def self.cache_key(account_id, source_ad_id)
    "meta_ads:care_state:active_copy:#{account_id}:#{source_ad_id}"
  end

  def initialize(connection)
    @connection = connection
  end

  # { ad_id, name } ou nil.
  def find(source_ad_id)
    key = self.class.cache_key(@connection.account_id, source_ad_id)
    cached = Redis::Alfred.get(key)
    return JSON.parse(cached).symbolize_keys if cached.present?

    found = live_copy(source_ad_id)
    Redis::Alfred.setex(key, found.to_json, CACHE_FOR) if found
    found
  end

  private

  def live_copy(source_ad_id)
    copy = activated_copy(copied_ad_ids(source_ad_id))
    return if copy.nil?

    result = Crm::MetaAds::Creation::Access.new(@connection).client.object_status(copy.ad_id)
    return unless result.ok && result.data['status'] == 'ACTIVE'
    return if Crm::MetaAds::Creation::Activation::HOLDING.include?(result.data['effective_status'])

    { ad_id: copy.ad_id, name: copy.name }
  end

  def copied_ad_ids(source_ad_id)
    Audited.audit_class.where(auditable_type: 'Account', auditable_id: @connection.account_id,
                              action: Crm::MetaAds::Creation::Copy::COPIED_ACTION)
           .where("audited_changes ->> 'source_ad_id' = ?", source_ad_id.to_s)
           .where("audited_changes ->> 'new_creative' = 'true'")
           .pluck(Arel.sql("audited_changes ->> 'ad_id'")).compact_blank
  end

  def activated_copy(ad_ids)
    return if ad_ids.empty?

    Crm::MetaAdsCreatedObject.where(account_id: @connection.account_id, ad_account_id: @connection.ad_account_id,
                                    kind: Crm::MetaAds::Creation::Copy::KIND, status: 'created', ad_id: ad_ids)
                             .where.not(activated_at: nil).order(activated_at: :desc).first
  end
end
