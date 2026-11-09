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
  # A Graph não respondeu de vez (rede, 5xx, limite) sobre o dono do anúncio: os jobs que perguntam tentam de novo.
  class OwnerUnavailable < StandardError; end

  AD_SOURCE = 'ADS'.freeze
  MESSENGER_SOURCE, INSTAGRAM_SOURCE = Ctwa::CampaignBuilder::MESSAGING_AD_SOURCES
  # Os toques cujo `source_id` é o id do anúncio da Meta: o clique para o WhatsApp, o Messenger e o Direct.
  AD_CLICK_SOURCES = [Ctwa::CampaignBuilder::CTWA_SOURCE, *Ctwa::CampaignBuilder::MESSAGING_AD_SOURCES].freeze
  # Origem da ligação conversa → anúncio (Crm::MetaAdLink) por fonte do toque.
  ORIGINS = { MESSENGER_SOURCE => 'messenger', INSTAGRAM_SOURCE => 'instagram' }.freeze
  PENDING_KEY_PREFIX = 'meta_ads:messaging_referral:pending:'.freeze
  PENDING_TTL = 1.day
  OWNER_CACHE = 1.hour
  # Id de objeto da Meta: só dígitos, de 6 a 30 (a mesma regra do Crm::Numeros::Origens::Classificador). O ad_id vem do
  # webhook e entra no caminho da Graph e no log: o que não for id fica de fora.
  META_ID_LENGTH = (6..30)

  module_function

  # source: MESSENGER_SOURCE ou INSTAGRAM_SOURCE; event_id: o mid da mensagem ou, no evento só de referral, remetente e
  # hora. true quando o toque foi gravado.
  #
  # ask_owner: false no caminho da mensagem, que roda dentro da trava por contato do webhook. Quando o dono do anúncio
  # depende da Graph (até 8 s), a pergunta vai para o MessagingReferralOwnerJob, fora da trava, e grava de lá.
  def attribute!(conversation, referral, source:, event_id:, ask_owner: true)
    ad_referral = for_campaign(referral, source: source, event_id: event_id)
    return false if conversation.nil? || ad_referral.nil?

    ad_id = ad_referral[:source_id]
    owner = ownership(conversation, ad_id)
    if owner == :ask
      return ask_owner_later(conversation, referral, source: source, event_id: event_id) unless ask_owner

      owner = owner?(conversation.account_id, ad_id) ? :mine : :foreign
    end
    owner == :mine && Ctwa::CampaignBuilder.attribute!(conversation, ad_referral)
  end

  def ask_owner_later(conversation, referral, source:, event_id:)
    Crm::MetaAds::MessagingReferralOwnerJob.perform_later(conversation.id, slim(referral), source, event_id.to_s)
    false
  end

  # Evento só de referral: a pessoa já tinha conversa na caixa. O toque vai para a conversa mais recente dela, se ainda
  # aberta (ou se a caixa trava numa conversa só, que reabre). Encerrada, a próxima mensagem abre conversa nova e não traz
  # o referral de novo (doc da Meta): o clique fica guardado (PENDING_TTL) e vai para a próxima conversa
  # (`attribute_message!`). Contato que a caixa não conhece não tem onde gravar.
  #
  # A Meta manda o mesmo clique no evento solto e de novo na mensagem, com ids diferentes (#2607): vale um toque só
  # (Crm::MetaAds::MessagingReferral::Click).
  def attribute_to_latest!(inbox, contact_source_id, referral, source:, event_id:)
    return false if for_campaign(referral, source: source, event_id: event_id).nil?

    contact_inbox = inbox.contact_inboxes.find_by(source_id: contact_source_id.to_s)
    return false if contact_inbox.nil?

    conversation = inbox.conversations.where(contact_inbox: contact_inbox).order(created_at: :desc).first
    return attribute!(conversation, referral, source: source, event_id: event_id) if continues?(inbox, conversation)

    keep_pending(contact_inbox, referral, source: source, event_id: event_id)
  end

  # Mensagem que chegou: quando ela abriu a conversa, primeiro os cliques guardados do evento solto; depois o anúncio
  # dela, se tiver. O mesmo clique vem no evento e na mensagem (#2607): o guardado entra antes e a repetição da mensagem
  # não grava (Click.same?). Sem ler os guardados aqui, eles iriam para a próxima conversa nova como clique fantasma.
  def attribute_message!(conversation, referral, source:, event_id:, new_conversation:)
    return false if conversation.nil?

    pending = new_conversation && attribute_pending!(conversation)
    return pending unless for_campaign(referral, source: source, event_id: event_id)

    attribute!(conversation, referral, source: source, event_id: event_id, ask_owner: false) || pending
  end

  # Os cliques guardados vão para a conversa nova. Lê e apaga de uma vez: duas mensagens ao mesmo tempo não levam o
  # mesmo clique. Redis fora não derruba a mensagem: o clique se perde e fica no log. Se alguém reabrir a conversa
  # encerrada e a pessoa escrever nela, o clique fica guardado e vai para a próxima conversa nova do contato no mesmo
  # dia (PENDING_TTL): perda aceita, a conversa reaberta não tem o toque.
  def attribute_pending!(conversation)
    key = pending_key(conversation.contact_inbox_id)
    pending = Redis::Alfred.with { |conn| conn.multi { |transaction| [transaction.lrange(key, 0, -1), transaction.del(key)] }.first }
    Array(pending).count { |raw| attribute_click(conversation, raw) }.positive?
  rescue Redis::BaseError => e
    Rails.logger.warn("[#{name}] conversation=#{conversation.id} cliques guardados não lidos: #{e.class}")
    false
  end

  # Um clique guardado com defeito não leva os outros junto: fica no log e no rastreador. Roda no caminho da mensagem
  # (dentro da trava): o dono pela Graph vai para o job.
  def attribute_click(conversation, raw)
    click = JSON.parse(raw)
    attribute!(conversation, click['referral'], source: click['source'], event_id: click['event_id'], ask_owner: false)
  rescue StandardError => e
    Rails.logger.warn("[#{name}] conversation=#{conversation.id} clique guardado não gravado: #{e.class}")
    ChatwootExceptionTracker.new(e, account: conversation.account).capture_exception
    false
  end

  def continues?(inbox, conversation)
    conversation.present? && (inbox.lock_to_single_conversation || !conversation.resolved?)
  end

  # Um clique por item da lista: dois anúncios clicados antes da próxima mensagem valem os dois.
  def keep_pending(contact_inbox, referral, source:, event_id:)
    key = pending_key(contact_inbox.id)
    click = { referral: slim(referral), source: source, event_id: event_id }.to_json
    Redis::Alfred.with { |conn| conn.multi { |transaction| [transaction.rpush(key, click), transaction.expire(key, PENDING_TTL.to_i)] } }
    false
  end

  def pending_key(contact_inbox_id)
    "#{PENDING_KEY_PREFIX}#{contact_inbox_id}"
  end

  # A mesma Página pode ser caixa de mais de uma conta (Integrations::Facebook::MessageCreator grava a mensagem em
  # todas), e o mesmo Instagram também (#2781): se alguma conta conhece o anúncio (gasto ou nome), ele vai só para a
  # conversa dela (:mine ou :foreign). Se nenhuma conhece (anúncio novo, antes da coleta), :ask: a Graph diz de qual
  # conta de anúncios ele é (`owner?`). Caixa de uma conta só é sempre :mine.
  def ownership(conversation, ad_id)
    others = other_accounts(conversation.inbox&.channel, conversation.account_id)
    return :mine if others.empty? || known_ad?(conversation.account_id, ad_id)
    return :foreign if known_ad?(others, ad_id)

    :ask
  end

  # As contas das outras caixas com a mesma Página ou o mesmo Instagram (a Página com Instagram ligado conta pelos dois).
  def other_accounts(channel, account_id)
    return [] unless channel.is_a?(Channel::FacebookPage) || channel.is_a?(Channel::Instagram)

    siblings = Instagram::ConnectedChannels.for(channel.instagram_id)
    siblings += Channel::FacebookPage.where(page_id: channel.page_id).to_a if channel.is_a?(Channel::FacebookPage)
    siblings.reject { |sibling| sibling == channel }.filter_map { |sibling| sibling.inbox&.account_id }.uniq - [account_id]
  end

  # O anúncio é da conta de anúncios conectada nesta conta? GET /<ad_id>?fields=account_id com o token da conexão.
  # Sem conexão ativa ou sem resposta, não, e fica no log (com o motivo, sem token). Só a resposta definitiva fica
  # guardada por 1 hora (as caixas da Página perguntam o mesmo anúncio): o account_id que voltou, ou anúncio inexistente
  # ou de outra conta (100/803). Falha passageira e recusa do token (190, 10, 200–299: token sem ads_read) não ficam.
  def owner?(account_id, ad_id)
    connection = Crm::MetaAdsConnection.active.find_by(account_id: account_id)
    return skip_owner(account_id, ad_id, 'sem conexão de anúncios') if connection&.ad_account_id.blank?

    key = "meta_ads:dono_do_anuncio:#{account_id}:#{ad_id}"
    owner = Rails.cache.read(key)
    owner = graph_owner(connection, ad_id, key) if owner.nil?
    return false if owner.nil?

    owner || skip_owner(account_id, ad_id, 'de outra conta de anúncios')
  end

  # true/false quando a Graph responde de vez (e guarda); falha passageira levanta OwnerUnavailable (o job tenta de
  # novo); recusa do token é nil, no log.
  def graph_owner(connection, ad_id, key)
    result = Meta::AdsGraphClient.new(access_token: connection.read_token).object(ad_id, fields: 'account_id')
    raise OwnerUnavailable, "account=#{connection.account_id} ad=#{ad_id} code=#{result.error_code.inspect}" if result.transient?

    unless result.ok || result.object_error?
      skip_owner(connection.account_id, ad_id, "Graph sem resposta definitiva (code=#{result.error_code.inspect})")
      return
    end

    owner = result.ok && same_ad_account?(result.data.to_h['account_id'], connection.ad_account_id)
    Rails.cache.write(key, owner, expires_in: OWNER_CACHE)
    owner
  end

  def same_ad_account?(one, other)
    one.to_s.delete_prefix('act_') == other.to_s.delete_prefix('act_')
  end

  def skip_owner(account_id, ad_id, reason)
    Rails.logger.warn("[#{name}] account=#{account_id} ad=#{ad_id} não gravado: #{reason}")
    false
  end

  def known_ad?(account_ids, ad_id)
    Crm::MetaAdObject.exists?(account_id: account_ids, meta_object_id: ad_id) ||
      Crm::MetaAdInsightDaily.exists?(account_id: account_ids, ad_id: ad_id)
  end

  # O referral do anúncio no formato que o Ctwa::CampaignBuilder lê, ou nil quando não é anúncio.
  def for_campaign(referral, source:, event_id:)
    ref = hash_of(referral)
    return unless ad?(ref) && event_id.present?

    context = hash_of(ref['ads_context_data'])
    {
      source: source, source_id: ref['ad_id'].to_s, source_type: 'ad', headline: context['ad_title'].presence,
      media_type: media_type(ref, context), image_url: context['photo_url'].presence, referral_id: event_id.to_s,
      touched_at: Click.time(ref['clicked_at'])&.utc&.iso8601
    }.compact
  end

  # O referral do webhook com a hora do clique da Meta (`timestamp` do evento ou da mensagem) em `clicked_at`, que segue
  # com ele para a fila, o Redis e o toque (Click).
  def with_click_time(referral, timestamp)
    referral.is_a?(Hash) && timestamp.present? ? referral.merge('clicked_at' => timestamp.to_s) : referral
  end

  # O referral sem os links assinados da Meta (foto, vídeo), para a fila e o Redis: só o que grava o toque. nil quando
  # não é anúncio.
  def slim(referral)
    ref = hash_of(referral)
    return unless ad?(ref)

    context = hash_of(ref['ads_context_data'])
    { 'source' => AD_SOURCE, 'ad_id' => ref['ad_id'].to_s, 'ads_context_data' => { 'ad_title' => context['ad_title'] }.compact,
      'media_type' => media_type(ref, context), 'clicked_at' => ref['clicked_at'] }.compact
  end

  def ad?(ref)
    ref['source'].to_s.casecmp?(AD_SOURCE) && meta_id?(ref['ad_id'])
  end

  def meta_id?(value)
    id = value.to_s
    META_ID_LENGTH.cover?(id.length) && id.each_char.all? { |char| char.between?('0', '9') }
  end

  def media_type(ref, context)
    ref['media_type'].presence || (context['video_url'].present? ? 'video' : 'image')
  end

  def hash_of(value)
    value.respond_to?(:to_h) ? value.to_h.stringify_keys : {}
  end
end
