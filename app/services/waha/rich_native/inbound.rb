# Callback `before_create` de Message (chat#1709, fase 3 e rodada 2): os dados estruturados que o conector customizado
# do WAHA (c2y-rich-2 e c2y-rich-3) acrescenta à mensagem que ele cria pela API. O conector roda para TODAS as contas e
# mantém o texto, o tipo e a privacidade de antes; só junta chaves `waha_*` em `content_attributes` (contrato em
# docs/audit/2026-10-16-1709-ricas-waha-rodada2.md). Regra única:
# - as chaves SEMPRE saem. Só o conector pode mandá-las (`from_connector?`: o usuário da requisição é o dono do token da
#   caixa; caixa antiga sem esse registro: um administrador da conta). De qualquer outro (agente, robô, job), as chaves
#   saem e nada mais muda: um agente não reescreve nem esconde mensagem dos outros por aqui.
# - flag `whatsapp_rich_native` DESLIGADA (ou caixa que não é a WAHA comum): nada mais muda. A mensagem fica IGUAL à da
#   main (mesmo texto, tipo e privacidade). Exceções, mensagens que a main nunca recebe: o voto de uma enquete nativa e
#   a resposta a um evento nativo (enviados quando a flag estava ligada) e o aviso de visualização única que o motor não
#   abriu viram atividade escondida (texto comum faria a IA responder "Sim").
# - flag LIGADA na caixa WAHA comum: cada chave vira a apresentação nova (Waha::RichNative::Inbound::<Tipo>), numa ordem
#   fixa (ORDER):
#   1. as que ABSORVEM a mensagem (voto, resposta ao evento, reação, edição, apagada, ligação, álbum): exclusivas, a
#      primeira presente decide e as outras saem; quando ela absorve (a mensagem vira atividade), nada mais roda. A
#      apagada, por ora, marca a original e mantém a nota da main visível (Waha::RichNative::Inbound::Revoke);
#   2. as que mudam o conteúdo (mídia que falhou, localização, contato, pedido, desconhecida);
#   3. a mídia (`waha_media`); 4. a citação (`waha_quote`); 5. o contexto (`waha_context`: encaminhada, temporária).
#   Erro num passo: só ele não vale (log com a classe do erro; o que ele gravou no banco volta, ponto de salvamento) e os
#   outros seguem; a criação nunca é interrompida.
class Waha::RichNative::Inbound
  ABSORBING = {
    'waha_poll_vote' => 'Waha::RichNative::Inbound::PollVote',
    'waha_event_response' => 'Waha::RichNative::Inbound::EventResponse',
    'waha_reaction' => 'Waha::RichNative::Inbound::Reaction',
    'waha_edit' => 'Waha::RichNative::Inbound::Edit',
    'waha_revoke' => 'Waha::RichNative::Inbound::Revoke',
    'waha_call' => 'Waha::RichNative::Inbound::Call',
    'waha_album' => 'Waha::RichNative::Inbound::Album'
  }.freeze
  TRANSFORMING = {
    'waha_media_failed' => 'Waha::RichNative::Inbound::MediaFailed',
    'waha_location' => 'Waha::RichNative::Inbound::Location',
    'waha_contacts' => 'Waha::RichNative::Inbound::Contacts',
    'waha_order' => 'Waha::RichNative::Inbound::Order',
    'waha_unknown' => 'Waha::RichNative::Inbound::Unknown',
    'waha_view_once_unavailable' => 'Waha::RichNative::Inbound::ViewOnceUnavailable',
    'waha_media' => 'Waha::RichNative::Inbound::Media',
    'waha_view_once_resolved' => 'Waha::RichNative::Inbound::ViewOnceResolved',
    'waha_quote' => 'Waha::RichNative::Inbound::Quote',
    'waha_context' => 'Waha::RichNative::Inbound::Context'
  }.freeze
  HANDLERS = ABSORBING.merge(TRANSFORMING).freeze
  KEYS = HANDLERS.keys.freeze
  HIDDEN_KEY = 'c2y_hidden'.freeze
  OWNER_KEY = 'account_token_owner_user_id'.freeze
  # Sem a flag: a mensagem que só existe por causa do pacote vira atividade escondida (chave => tipo do texto).
  HIDDEN_WITHOUT_FLAG = { 'waha_poll_vote' => 'poll_vote', 'waha_event_response' => 'event_response' }.freeze

  def self.before_create(message)
    attributes = message.content_attributes.to_h
    present = KEYS.select { |key| attributes.key?(key) }
    return if present.empty?

    message.content_attributes = attributes.except(*KEYS)
    return unless waha_inbox?(message) && from_connector?(message)

    apply(message, attributes.slice(*present))
    refresh_processed_content(message)
  rescue StandardError => e
    Rails.logger.error("[waha] rich native inbound #{e.class}")
    message.content_attributes = message.content_attributes.to_h.except(*KEYS)
    refresh_processed_content(message)
  end

  # Este callback é `before_create`, que roda DEPOIS dos `before_save`: o `processed_message_content` foi calculado do
  # texto do conector (a nota da mídia que falhou traz o link interno do job; a localização tinha o texto antigo). Ele
  # vai a todo webhook e à condição "conteúdo contém" das automações: recalcular do `content` transformado, pela mesma
  # regra do modelo (Message#ensure_processed_message_content).
  def self.refresh_processed_content(message)
    message.send(:ensure_processed_message_content)
  end

  # present: { chave => dados } das chaves que o conector mandou.
  def self.apply(message, present)
    return apply_without_flag(message, present) unless Waha::RichNative.enabled?(message.account)

    absorbing = ABSORBING.keys.find { |key| present.key?(key) }
    run(message, absorbing, present[absorbing]) if absorbing
    return if absorbed?(message)

    TRANSFORMING.each_key { |key| run(message, key, present[key]) if present.key?(key) }
  end

  # Absorvida: virou atividade escondida, ou o turno do cliente para a IA (voto, resposta ao evento).
  def self.absorbed?(message)
    message.activity? || Waha::RichNative::AiTurn.turn?(message)
  end

  def self.apply_without_flag(message, present)
    return unless message.incoming?

    key = HIDDEN_WITHOUT_FLAG.keys.find { |candidate| present.key?(candidate) }
    return hide!(message, HIDDEN_WITHOUT_FLAG[key]) if key

    return hide!(message, 'view_once') if Waha::RichNative::Inbound::Unknown.unavailable_view_once?(present['waha_unknown'])

    # O aviso de visualização única que o aparelho vinculado não abre: a main nunca recebe essa mensagem.
    hide!(message, 'view_once') if Waha::RichNative::Inbound::ViewOnceUnavailable.customer?(present['waha_view_once_unavailable'])
  end

  # Cada passo num ponto de salvamento (`requires_new`): um erro de SQL num passo aborta a transação da criação no
  # Postgres, e o `rescue` sozinho deixaria os passos seguintes e o próprio INSERT falharem. Com o ponto de salvamento, só
  # o que o passo gravou volta, e a criação segue.
  def self.run(message, key, data)
    ActiveRecord::Base.transaction(requires_new: true) { HANDLERS.fetch(key).constantize.apply(message, data) }
  rescue StandardError => e
    Rails.logger.error("[waha] rich native inbound #{key} #{e.class}")
  end

  # Caixa WAHA comum (Channel::Api com provider 'waha').
  def self.waha_inbox?(message)
    inbox = message.inbox
    inbox&.channel_type == 'Channel::Api' && inbox.channel.try(:waha_provider?) ? true : false
  end

  # O usuário desta requisição é o conector: o dono do token gravado na caixa pelo Waha::InboxProvisioner.
  # - Flag LIGADA: só o dono gravado. Sem o registro, ninguém: um administrador qualquer não injeta evento do conector
  #   (reação, edição, voto, apagada) pela API. Gravar o dono nas caixas WAHA é PRÉ-REQUISITO para ligar a flag
  #   (docs/1709-escopo-e-aceite.md).
  # - Flag desligada (como antes): caixa sem o registro (provisionada pelo SSO ou antes dele) aceita um administrador da
  #   conta (é sempre o token de um). Ali só o voto e a resposta ao evento viram atividade escondida, como na main.
  def self.from_connector?(message)
    user = Current.user
    return false unless user.is_a?(User)

    owner = message.inbox.channel.additional_attributes.to_h[OWNER_KEY]
    return owner.to_s == user.id.to_s if owner.present?
    return warn_missing_owner(message) if Waha::RichNative.enabled?(message.account)

    message.account.account_users.find_by(user_id: user.id)&.administrator? == true
  end

  OWNER_WARNING_TTL = 1.hour

  # Com a flag, a caixa sem o dono gravado perde os pacotes do conector: não em silêncio. Um aviso no log por caixa por
  # hora (Rails.cache), só com os ids. Devolve false (ninguém é o conector).
  def self.warn_missing_owner(message)
    key = "waha/rich_native/missing_token_owner/#{message.inbox_id}"
    if Rails.cache.write(key, true, expires_in: OWNER_WARNING_TTL, unless_exist: true)
      Rails.logger.error("[waha] rich native connector keys dropped: inbox without #{OWNER_KEY} " \
                         "account=#{message.account_id} inbox=#{message.inbox_id}")
    end
    false
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
