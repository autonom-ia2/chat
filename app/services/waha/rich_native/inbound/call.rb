# `waha_call` (chat#1709, fase 3): ligação pelo WhatsApp na caixa WAHA comum vira AVISO de atividade, e não mensagem
# do cliente (a IA respondia "Chamada de voz recebida"). A atividade não vai a webhook nem dispara a IA. Uma ligação =
# UMA linha na conversa, com o resumo em `waha_call_summary` = { call_id, outcome, is_video }:
# - received: "Ligação de voz/vídeo recebida" (ringing). Fica VISÍVEL: na sessão do WAHA (aparelho vinculado), atender
#   ou recusar no celular da empresa chega como accepted/rejected_elsewhere, e o motor (GOWS) descarta esse fim; se
#   nenhum desfecho chegar, a linha da ligação continua na conversa.
# - o desfecho troca o texto da linha da mesma ligação (mesmo call_id), e a mensagem do desfecho vira atividade
#   escondida. Sem a linha (o desfecho chegou antes do toque, ou numa conversa nova), o desfecho vira a linha:
#   - accepted: "Ligação atendida no celular" (answered);
#   - rejected depois de atendida: "Ligação atendida e encerrada" (ended);
#   - rejected por nós (by_me: recusada no celular da empresa ou pela API): "Ligação de voz/vídeo recusada" (declined);
#   - rejected sem atender: "Ligação de voz/vídeo perdida" (missed).
# - toque que chega depois do desfecho não volta a linha para "recebida".
# Textos em config/locales/whatsapp_rich_native.*.yml (waha.call.*), no idioma da conta.
module Waha::RichNative::Inbound::Call
  SUMMARY_KEY = 'waha_call_summary'.freeze
  # Quantas atividades recentes da conversa olhar para achar a linha da mesma ligação.
  LOOKBACK = 20
  BY_MEDIA = %w[ringing missed declined].freeze

  module_function

  def apply(message, data)
    return unless data.is_a?(Hash) && data['call_id'].present?

    call_id = data['call_id'].to_s
    is_video = data['is_video'] == true
    line = call_line(message.conversation, call_id)
    outcome = outcome_for(line, data)
    return show!(message, summary(call_id, outcome, is_video)) if line.nil?

    update_line!(line, summary(call_id, outcome, is_video)) unless outcome == 'ringing'
    Waha::RichNative::Inbound.hide!(message, 'call', SUMMARY_KEY => summary(call_id, outcome, is_video))
  end

  def summary(call_id, outcome, is_video)
    { 'call_id' => call_id, 'outcome' => outcome, 'is_video' => is_video }
  end

  def outcome_for(line, data)
    previous = line&.content_attributes.to_h.dig(SUMMARY_KEY, 'outcome')
    case data['event']
    when 'received' then previous || 'ringing'
    when 'accepted' then 'answered'
    else rejected_outcome(previous, data)
    end
  end

  def rejected_outcome(previous, data)
    return 'ended' if %w[answered ended].include?(previous)
    return 'declined' if data['by_me'] == true

    'missed'
  end

  # A linha visível da mesma ligação nesta conversa, ou nil.
  def call_line(conversation, call_id)
    return if conversation.nil?

    conversation.messages.where(message_type: :activity).reorder(id: :desc).limit(LOOKBACK).find do |activity|
      attributes = activity.content_attributes.to_h
      summary = attributes[SUMMARY_KEY]
      summary.is_a?(Hash) && summary['call_id'] == call_id && attributes[Waha::RichNative::Inbound::HIDDEN_KEY] != true
    end
  end

  def show!(message, summary)
    message.message_type = :activity
    message.private = false
    message.content = text_for(message.account, summary)
    message.content_attributes = message.content_attributes.to_h.merge(SUMMARY_KEY => summary)
  end

  def update_line!(line, summary)
    line.with_lock do
      line.content = text_for(line.account, summary)
      line.content_attributes = line.content_attributes.to_h.merge(SUMMARY_KEY => summary)
      line.save!(validate: false)
    end
  end

  def text_for(account, summary)
    outcome = summary['outcome']
    key = "waha.call.#{outcome}"
    key = "#{key}_#{summary['is_video'] ? 'video' : 'voice'}" if BY_MEDIA.include?(outcome)
    I18n.t(key, locale: account.locale, default: I18n.t(key))
  end
end
