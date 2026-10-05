# Resolução retroativa dos nomes da Meta (#1034), enfileirada ao salvar a credencial da conta.
#
# Alcança as conversas com toques dos últimos WINDOW que têm ID e ainda não têm nome. Primeiro junta
# todos os IDs e resolve em lote, uma vez (o NameResolver agrupa em chamadas de até 50, guarda no
# cache e põe no cache negativo o ID que a Meta não resolve); depois grava conversa a conversa a
# partir desse mesmo resultado, sem nova consulta à Graph nem ao cache por conversa.
class Crm::MetaAds::BackfillJob < ApplicationJob
  queue_as :low

  WINDOW = 90.days

  def perform(account_id)
    account = Account.find_by(id: account_id)
    return if account.blank? || Crm::MetaAdsConnection.active_for(account.id).blank?

    conversation_ids, ids_by_type = pending(account)
    return if conversation_ids.empty?

    resolver = Crm::MetaAds::NameResolver.new(account)
    resolved = ids_by_type.reduce({}) { |all, (type, ids)| all.merge(resolver.resolve(ids, type: type)) }
    return if resolved.empty?

    Conversation.where(id: conversation_ids).find_each do |conversation|
      Crm::MetaAds::TouchEnricher.new(conversation, resolved: resolved).perform
    end
  end

  private

  def pending(account)
    since = WINDOW.ago
    conversation_ids = []
    ids_by_type = Hash.new { |hash, key| hash[key] = [] }

    candidates(account, since).find_each do |conversation|
      touches = pending_touches(conversation, since)
      next if touches.empty?

      conversation_ids << conversation.id
      touches.each { |touch| Crm::MetaAds::TouchEnricher.ids_by_type(touch).each { |type, ids| ids_by_type[type] |= ids } }
    end
    [conversation_ids, ids_by_type]
  end

  # Gravar um toque atualiza a conversa: quem teve toque na janela tem updated_at dentro dela.
  def candidates(account, since)
    Conversation.where(account_id: account.id)
                .where(updated_at: since..)
                .where("conversations.additional_attributes ? 'campaign_touches'")
  end

  def pending_touches(conversation, since)
    touches = conversation.additional_attributes.to_h['campaign_touches']
    return [] unless touches.is_a?(Array)

    touches.select { |touch| Crm::MetaAds::TouchEnricher.unnamed?(touch) && recent?(touch, since) }
  end

  def recent?(touch, since)
    touched_at = Time.zone.parse(touch['touched_at'].to_s)
    touched_at.present? && touched_at >= since
  rescue ArgumentError
    false
  end
end
