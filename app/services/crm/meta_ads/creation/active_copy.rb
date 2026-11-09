# A cópia com a foto ou o texto novos que está no ar no lugar deste anúncio (#2804). É ela que faz o "Pausar o original"
# continuar na tela depois de recarregar, enquanto o original também está ativo.
#
# A ligação entre a cópia e o original é a Auditoria `meta_ads_ad_copied` (`source_ad_id`, `ad_id` e `new_creative`),
# gravada quando a cópia nasce. Vale a cópia criada aqui, ativada pela pessoa (`activated_at`) e que a Meta diz estar
# ACTIVE agora: só nesse caso há uma leitura na Meta, e sem resposta não há botão.
class Crm::MetaAds::Creation::ActiveCopy
  # As cópias mais recentes do anúncio que olhamos.
  RECENT = 5

  def initialize(connection)
    @connection = connection
  end

  # { ad_id, name } ou nil.
  def find(source_ad_id)
    copy = activated_copy(copied_ad_ids(source_ad_id))
    return if copy.nil?

    result = Crm::MetaAds::Creation::Access.new(@connection).client.object_status(copy.ad_id)
    { ad_id: copy.ad_id, name: copy.name } if result.ok && result.data['status'] == 'ACTIVE'
  end

  private

  def copied_ad_ids(source_ad_id)
    Audited.audit_class.where(auditable_type: 'Account', auditable_id: @connection.account_id,
                              action: Crm::MetaAds::Creation::Copy::COPIED_ACTION)
           .where("audited_changes ->> 'source_ad_id' = ?", source_ad_id.to_s)
           .where("audited_changes ->> 'new_creative' = 'true'")
           .order(created_at: :desc).limit(RECENT)
           .filter_map { |audit| audit.audited_changes['ad_id'].presence&.to_s }
  end

  def activated_copy(ad_ids)
    return if ad_ids.empty?

    Crm::MetaAdsCreatedObject.where(account_id: @connection.account_id, ad_account_id: @connection.ad_account_id,
                                    kind: Crm::MetaAds::Creation::Copy::KIND, status: 'created', ad_id: ad_ids)
                             .where.not(activated_at: nil).order(activated_at: :desc).first
  end
end
