# O anúncio de clique para o Messenger ou para o Direct do Instagram (#2521) como toque de campanha da conversa, igual
# ao clique para o WhatsApp (Ctwa::CampaignBuilder).
#
# A Meta manda o `referral` do anúncio em três lugares (doc da Messenger Platform, webhook events, conferida em
# 04/11/2026): na primeira mensagem de conversa nova (`message.referral`), num evento só de referral quando a pessoa já
# tinha conversa (`messaging[].referral`, campo `messaging_referrals`) e no postback do "Começar" (`postback.referral`).
# Vale só o que é anúncio: `source` = ADS com `ad_id`. Link m.me/ig.me e loja ficam de fora.
#
# O toque guarda o id do anúncio em `source_id` (como o do WhatsApp), o título e a foto do anúncio (`ads_context_data`)
# e o id do evento em `referral_id`: esse clique não tem `ctwa_clid`, e o id do evento separa dois cliques no mesmo
# anúncio e segura a reentrega do webhook.
module Crm::MetaAds::MessagingReferral
  AD_SOURCE = 'ADS'.freeze
  MESSENGER_SOURCE, INSTAGRAM_SOURCE = Ctwa::CampaignBuilder::MESSAGING_AD_SOURCES
  # Origem da ligação conversa → anúncio (Crm::MetaAdLink) por fonte do toque.
  ORIGINS = { MESSENGER_SOURCE => 'messenger', INSTAGRAM_SOURCE => 'instagram' }.freeze

  module_function

  # source: MESSENGER_SOURCE ou INSTAGRAM_SOURCE; event_id: o mid da mensagem ou, no evento só
  # de referral, remetente e hora. true quando o toque foi gravado.
  def attribute!(conversation, referral, source:, event_id:)
    ad_referral = for_campaign(referral, source: source, event_id: event_id)
    return false if conversation.nil? || ad_referral.nil?

    Ctwa::CampaignBuilder.attribute!(conversation, ad_referral)
  end

  # Evento só de referral: a pessoa já tinha conversa na caixa, e o toque vai para a mais recente dela. Sem conversa
  # (contato que a caixa não conhece) não há onde gravar.
  def attribute_to_latest!(inbox, contact_source_id, referral, source:, event_id:)
    contact_inbox = inbox.contact_inboxes.find_by(source_id: contact_source_id.to_s)
    conversation = contact_inbox && inbox.conversations.where(contact_inbox: contact_inbox).order(created_at: :desc).first
    attribute!(conversation, referral, source: source, event_id: event_id)
  end

  # O referral do anúncio no formato que o Ctwa::CampaignBuilder lê, ou nil quando não é anúncio.
  def for_campaign(referral, source:, event_id:)
    ref = hash_of(referral)
    return unless ref['source'].to_s.casecmp?(AD_SOURCE) && ref['ad_id'].present? && event_id.present?

    context = hash_of(ref['ads_context_data'])
    {
      source: source, source_id: ref['ad_id'].to_s, source_type: 'ad', headline: context['ad_title'].presence,
      media_type: context['video_url'].present? ? 'video' : 'image', image_url: context['photo_url'].presence,
      referral_id: event_id.to_s
    }.compact
  end

  def hash_of(value)
    value.respond_to?(:to_h) ? value.to_h.stringify_keys : {}
  end
end
