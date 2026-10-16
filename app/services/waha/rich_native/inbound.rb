# Callback `before_create` de Message (chat#1709, fase 3): os dados estruturados que o conector customizado do WAHA
# (c2y-rich-2) acrescenta à mensagem que ele cria pela API. O conector roda para TODAS as contas e mantém o texto, o tipo
# e a privacidade de antes; só junta uma destas chaves em `content_attributes`:
#   waha_poll_vote  { poll_message_id, options: [títulos], vote_id, timestamp }  + in_reply_to (a enquete)
#   waha_call       { call_id, event: received|accepted|rejected, is_video, by_me, reason }
#   waha_unknown    { content_type, from_me }
#   waha_reaction   { emoji ('' = removida), reacted_wa_id, from_me }            + in_reply_to (a reagida)
#   waha_edit       { text, edited_wa_id, from_me }                               + in_reply_to (a editada)
# Regra única:
# - a chave SEMPRE sai. Só o conector pode mandá-las (`from_connector?`: o usuário da requisição é o dono do token da
#   caixa; caixa antiga sem esse registro: um administrador da conta). De qualquer outro (agente, robô, job), a chave sai
#   e nada mais muda: um agente não reescreve nem esconde mensagem dos outros por aqui.
# - flag `whatsapp_rich_native` DESLIGADA (ou caixa que não é a WAHA comum): nada mais muda. A mensagem fica IGUAL à da
#   main (mesmo texto, tipo e privacidade). Exceção: o voto de uma enquete nativa enviada quando a flag estava ligada
#   vira atividade escondida (na main o voto nunca chega; texto comum faria a IA responder "Sim").
# - flag LIGADA na caixa WAHA comum: a mensagem vira a apresentação nova (Waha::RichNative::Inbound::<Tipo>). Erro em
#   qualquer passo: a chave sai e a mensagem fica como a main (nunca interrompe a criação).
class Waha::RichNative::Inbound
  HANDLERS = {
    'waha_poll_vote' => 'Waha::RichNative::Inbound::PollVote',
    'waha_call' => 'Waha::RichNative::Inbound::Call',
    'waha_unknown' => 'Waha::RichNative::Inbound::Unknown',
    'waha_reaction' => 'Waha::RichNative::Inbound::Reaction',
    'waha_edit' => 'Waha::RichNative::Inbound::Edit'
  }.freeze
  KEYS = HANDLERS.keys.freeze
  HIDDEN_KEY = 'c2y_hidden'.freeze
  OWNER_KEY = 'account_token_owner_user_id'.freeze

  def self.before_create(message)
    attributes = message.content_attributes.to_h
    present = KEYS.select { |key| attributes.key?(key) }
    return if present.empty?

    message.content_attributes = attributes.except(*KEYS)
    return unless waha_inbox?(message) && from_connector?(message)

    apply(message, present.first, attributes[present.first])
  rescue StandardError => e
    Rails.logger.error("[waha] rich native inbound #{e.class}")
    message.content_attributes = message.content_attributes.to_h.except(*KEYS)
  end

  def self.apply(message, key, data)
    if Waha::RichNative.enabled?(message.account)
      HANDLERS[key].constantize.apply(message, data)
    elsif key == 'waha_poll_vote' && message.incoming?
      hide!(message, 'poll_vote')
    end
  end

  # Caixa WAHA comum (Channel::Api com provider 'waha').
  def self.waha_inbox?(message)
    inbox = message.inbox
    inbox&.channel_type == 'Channel::Api' && inbox.channel.try(:waha_provider?) ? true : false
  end

  # Flag na conta e caixa WAHA comum (o que transforma a mensagem).
  def self.transform?(message)
    waha_inbox?(message) && Waha::RichNative.enabled?(message.account)
  end

  # O usuário desta requisição é o conector: o dono do token gravado na caixa pelo Waha::InboxProvisioner. Caixa sem
  # esse registro (provisionada pelo SSO ou antes dele): um administrador da conta (é sempre o token de um).
  def self.from_connector?(message)
    user = Current.user
    return false unless user.is_a?(User)

    owner = message.inbox.channel.additional_attributes.to_h[OWNER_KEY]
    return owner.to_s == user.id.to_s if owner.present?

    message.account.account_users.find_by(user_id: user.id)&.administrator? == true
  end

  # A mensagem citada pelo conector (`in_reply_to`), na mesma caixa e do MESMO contato: o conector pode criar a reação
  # ou a edição numa conversa nova (a original estava resolvida), e a citada fica na conversa antiga. Nunca nota,
  # atividade, apagada ou falhada (`external_error`: gravar nela reenviaria a mensagem pelo conector).
  def self.target_of(message, **filters)
    target_id = Waha::RichNative::Inbound::ReplyTarget.target_id(message)
    contact_id = message.conversation&.contact_id
    return if target_id.blank? || contact_id.nil?

    target = Message.joins(:conversation).where(conversations: { contact_id: contact_id })
                    .where.not(message_type: :activity).where(private: false)
                    .find_by(id: target_id, inbox_id: message.inbox_id, **filters)
    target if target && applicable?(target)
  end

  def self.applicable?(target)
    attributes = target.content_attributes.to_h
    !attributes['deleted'] && attributes['external_error'].blank?
  end

  # A mensagem criada vira uma atividade escondida (não aparece na conversa nem vai à IA): fica só como registro de que
  # o evento chegou, apontando a mensagem que mudou. O texto do conector ("*Reagiu com* 👍", o texto editado inteiro)
  # dá lugar a uma linha curta e neutra (waha.hidden.<tipo>), que é o que o app do celular, a busca e as exportações
  # mostram, já que só o painel web esconde a atividade.
  def self.hide!(message, kind, extra = {})
    message.message_type = :activity
    message.private = false
    message.content = hidden_text(message.account, kind)
    message.content_attributes = message.content_attributes.to_h.merge(HIDDEN_KEY => true).merge(extra)
  end

  def self.hidden_text(account, kind)
    key = "waha.hidden.#{kind}"
    I18n.t(key, locale: account.locale, default: I18n.t(key))
  end

  def self.hidden?(message)
    message.activity? && message.content_attributes.to_h[HIDDEN_KEY] == true
  end
end
