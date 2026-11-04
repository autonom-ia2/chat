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
  PENDING_KEY_PREFIX = 'meta_ads:messaging_referral:pending:'.freeze
  PENDING_TTL = 1.day

  module_function

  # source: MESSENGER_SOURCE ou INSTAGRAM_SOURCE; event_id: o mid da mensagem ou, no evento só
  # de referral, remetente e hora. true quando o toque foi gravado.
  def attribute!(conversation, referral, source:, event_id:)
    ad_referral = for_campaign(referral, source: source, event_id: event_id)
    return false if conversation.nil? || ad_referral.nil?

    Ctwa::CampaignBuilder.attribute!(conversation, ad_referral)
  end

  # Evento só de referral: a pessoa já tinha conversa na caixa. O toque vai para a conversa mais recente dela, se ainda
  # aberta (ou se a caixa trava numa conversa só, que reabre). Encerrada, a próxima mensagem abre conversa nova e não traz
  # o referral de novo (doc da Meta): o clique fica guardado (PENDING_TTL) e vai para a próxima conversa
  # (`attribute_pending!`). Contato que a caixa não conhece não tem onde gravar.
  #
  # Se a Meta mandasse o mesmo clique no evento solto e de novo na mensagem, seriam dois toques (ids diferentes) do mesmo
  # anúncio na conversa: a doc diz que não manda, e a contagem do painel é por conversa.
  def attribute_to_latest!(inbox, contact_source_id, referral, source:, event_id:)
    return false if for_campaign(referral, source: source, event_id: event_id).nil?

    contact_inbox = inbox.contact_inboxes.find_by(source_id: contact_source_id.to_s)
    return false if contact_inbox.nil?

    conversation = inbox.conversations.where(contact_inbox: contact_inbox).order(created_at: :desc).first
    return attribute!(conversation, referral, source: source, event_id: event_id) if continues?(inbox, conversation)

    keep_pending(contact_inbox, referral, source: source, event_id: event_id)
  end

  # A mensagem sem referral de quem clicou com a conversa encerrada: o clique guardado vai para a conversa dela.
  def attribute_pending!(conversation)
    key = pending_key(conversation.contact_inbox_id)
    # Lê e apaga de uma vez: duas mensagens ao mesmo tempo não levam o mesmo clique.
    raw = Redis::Alfred.with { |conn| conn.multi { |transaction| [transaction.get(key), transaction.del(key)] }.first }
    return false if raw.blank?

    pending = JSON.parse(raw)
    attribute!(conversation, pending['referral'], source: pending['source'], event_id: pending['event_id'])
  end

  # Mensagem que chegou: o anúncio dela, ou o clique guardado do evento solto (referral que não é anúncio, como link
  # m.me ou loja, não conta).
  def attribute_message!(conversation, referral, source:, event_id:)
    return false if conversation.nil?
    return attribute!(conversation, referral, source: source, event_id: event_id) if for_campaign(referral, source: source, event_id: event_id)

    attribute_pending!(conversation)
  end

  def continues?(inbox, conversation)
    conversation.present? && (inbox.lock_to_single_conversation || !conversation.resolved?)
  end

  # O referral traz a foto num link assinado da Meta: fica só no Redis, com prazo, nunca no log.
  def keep_pending(contact_inbox, referral, source:, event_id:)
    Redis::Alfred.set(pending_key(contact_inbox.id), { referral: hash_of(referral), source: source, event_id: event_id }.to_json,
                      ex: PENDING_TTL.to_i)
    false
  end

  def pending_key(contact_inbox_id)
    "#{PENDING_KEY_PREFIX}#{contact_inbox_id}"
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
