# `waha_context` (chat#1709, rodada 2): o contexto da mensagem do cliente, { ephemeral_expiration (segundos, 0 =
# desligada), forwarded, forwarding_score }, quando algum não é o padrão.
# - Encaminhada: `forwarded: true`; `frequently_forwarded: true` com forwarding_score >= FREQUENT_SCORE (o rótulo
#   "Encaminhada com frequência" do WhatsApp). A tela mostra o rótulo "Encaminhada".
# - Temporária: o conteúdo é mantido. Quando o tempo muda em relação ao último visto na conversa
#   (`additional_attributes.c2y_ephemeral_expiration`), inclusive para 0, depois de criada a mensagem fica UMA
#   atividade visível ("Mensagens temporárias ativadas (24 horas)…" ou "…desativadas") com `waha_ephemeral`
#   { expiration_seconds, at }, e a conversa guarda o tempo novo. A atividade não vai à IA. Conversa nova sem
#   temporária (0) não ganha aviso.
module Waha::RichNative::Inbound::Context
  FREQUENT_SCORE = 5
  CONVERSATION_KEY = 'c2y_ephemeral_expiration'.freeze
  ACTIVITY_KEY = 'waha_ephemeral'.freeze
  PENDING = :@c2y_ephemeral_change

  module_function

  def apply(message, data)
    return unless message.incoming? && data.is_a?(Hash)

    forwarded!(message, data)
    expiration = data['ephemeral_expiration']
    message.instance_variable_set(PENDING, expiration) if expiration.is_a?(Integer) && changed?(message, expiration)
  end

  def forwarded!(message, data)
    return unless data['forwarded'] == true

    extra = { 'forwarded' => true }
    extra['frequently_forwarded'] = true if data['forwarding_score'].to_i >= FREQUENT_SCORE
    message.content_attributes = message.content_attributes.to_h.merge(extra)
  end

  def changed?(message, expiration)
    previous = message.conversation&.additional_attributes.to_h[CONVERSATION_KEY]
    previous.nil? ? expiration.positive? : previous != expiration
  end

  # after_create_commit de Message. Nunca levanta: a mensagem do cliente já está gravada, e uma exceção aqui voltaria
  # 500 ao conector (que repetiria o job e gravaria a mensagem DE NOVO) e, pela ordem inversa dos after_commit, ainda
  # tiraria o `message_created` dela. Falhou: só o aviso não sai (log com a classe do erro).
  def after_commit(message)
    return unless message.instance_variable_defined?(PENDING)

    expiration = message.instance_variable_get(PENDING)
    message.remove_instance_variable(PENDING)
    notify!(message.conversation, expiration)
  rescue StandardError => e
    Rails.logger.error("[waha] rich native ephemeral notice message=#{message.id} #{e.class}")
  end

  # Sem as validações do modelo (a de rajada recusaria o aviso numa conversa movimentada), como as outras gravações.
  def notify!(conversation, expiration)
    conversation.additional_attributes = conversation.additional_attributes.to_h.merge(CONVERSATION_KEY => expiration)
    conversation.save!(validate: false)
    activity = conversation.messages.new(account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :activity,
                                         content: notice(conversation.account, expiration),
                                         content_attributes: { ACTIVITY_KEY => { 'expiration_seconds' => expiration,
                                                                                 'at' => Time.current.iso8601 } })
    Waha::RichNative::InternalWrite.mark!(activity).save!(validate: false)
  end

  def notice(account, expiration)
    key = expiration.positive? ? 'waha.ephemeral.on' : 'waha.ephemeral.off'
    translate(key, account, duration: duration(account, expiration))
  end

  def duration(account, seconds)
    return '' unless seconds.positive?

    days = seconds / 1.day.to_i
    return translate('waha.ephemeral.hours', account, count: seconds / 1.hour.to_i) if days.zero?

    translate('waha.ephemeral.days', account, count: days)
  end

  # No idioma da conta; sem a chave nele (só há en e pt_BR), no idioma padrão.
  def translate(key, account, **)
    I18n.t(key, **, locale: account.locale, default: I18n.t(key, **))
  end
end
