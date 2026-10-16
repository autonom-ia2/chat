# `waha_call` (chat#1709, fase 3): ligação pelo WhatsApp na caixa WAHA comum vira AVISO de atividade, e não mensagem
# do cliente (a IA respondia "Chamada de voz recebida"). A atividade não vai a webhook, não dispara a IA nem reabre a
# conversa. O resumo fica em `waha_call_summary` = { call_id, outcome, is_video }.
# - received: o toque; atividade escondida (`c2y_hidden`), só como registro (outcome 'ringing');
# - accepted: "Ligação atendida no celular" (answered);
# - rejected por nós (by_me: recusada no celular da empresa ou pela API): "Ligação recusada" (declined);
# - rejected depois de atendida (mesmo call_id): "Ligação encerrada" (ended);
# - rejected sem atender: "Ligação perdida" (missed).
# Textos em config/locales/whatsapp_rich_native.*.yml (waha.call.*), no idioma da conta; voz ou vídeo por `is_video`.
module Waha::RichNative::Inbound::Call
  SUMMARY_KEY = 'waha_call_summary'.freeze
  # Quantas atividades recentes da conversa olhar para saber se a ligação foi atendida.
  LOOKBACK = 20

  module_function

  def apply(message, data)
    return unless data.is_a?(Hash) && data['call_id'].present?

    outcome = outcome_for(message, data)
    summary = { 'call_id' => data['call_id'].to_s, 'outcome' => outcome, 'is_video' => data['is_video'] == true }
    if outcome == 'ringing'
      Waha::RichNative::Inbound.hide!(message, SUMMARY_KEY => summary)
    else
      show!(message, summary)
    end
  end

  def outcome_for(message, data)
    case data['event']
    when 'received' then 'ringing'
    when 'accepted' then 'answered'
    else rejected_outcome(message, data)
    end
  end

  def rejected_outcome(message, data)
    return 'declined' if data['by_me'] == true

    answered?(message.conversation, data['call_id'].to_s) ? 'ended' : 'missed'
  end

  def answered?(conversation, call_id)
    conversation.messages.where(message_type: :activity).reorder(id: :desc).limit(LOOKBACK).any? do |activity|
      summary = activity.content_attributes.to_h[SUMMARY_KEY]
      summary.is_a?(Hash) && summary['call_id'] == call_id && summary['outcome'] == 'answered'
    end
  end

  def show!(message, summary)
    message.message_type = :activity
    message.private = false
    message.content = text_for(message.account, summary)
    message.content_attributes = message.content_attributes.to_h.merge(SUMMARY_KEY => summary)
  end

  def text_for(account, summary)
    key = "waha.call.#{summary['outcome']}"
    key = "#{key}_video" if summary['is_video'] && %w[missed declined].include?(summary['outcome'])
    I18n.t(key, locale: account.locale, default: I18n.t(key))
  end
end
