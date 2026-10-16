# Prepend em Api::V1::Accounts::Conversations::MessagesController (chat#1709, rodada 2): o recibo "ouvido" do áudio que
# mandamos. O conector c2y-rich-3, ao receber o ack PLAYED de uma mensagem nossa mapeada, manda no PATCH de status de
# sempre o parâmetro a mais `c2y_played_at` (ISO 8601), que a main ignora (parâmetro não permitido só vai ao log).
# Aqui, depois do update de sempre, grava `content_attributes.played_at` (só a primeira vez) quando: flag
# `whatsapp_rich_native`, caixa WAHA comum, quem chama é o conector (Waha::RichNative::Inbound.from_connector?) e a
# mensagem é nossa (outgoing) com anexo de áudio. A gravação não vai ao conector (Waha::RichNative::SilentUpdate).
# Entra como after_action, sem sobrescrever `update` (o Guia lê o formato da ação no método original).
module Waha::RichNative::PlayedReceipt
  KEY = 'played_at'.freeze
  PARAM = :c2y_played_at

  def self.prepended(controller)
    controller.after_action :record_waha_played_at, only: :update
  end

  def self.applicable?(message)
    message.outgoing? && Waha::RichNative::Inbound.waha_inbox?(message) && Waha::RichNative.enabled?(message.account) &&
      Waha::RichNative::Inbound.from_connector?(message) && message.attachments.any?(&:audio?)
  end

  def self.parse(value)
    Time.iso8601(value.to_s).iso8601
  rescue ArgumentError
    nil
  end

  def self.record!(message, played_at)
    message.with_lock do
      next if message.content_attributes.to_h[KEY].present?

      message.content_attributes = message.content_attributes.to_h.merge(KEY => played_at)
      message.save!(validate: false)
    end
  end

  private

  def record_waha_played_at
    receipt = Waha::RichNative::PlayedReceipt
    value = params[receipt::PARAM]
    return if value.blank? || @message.nil?

    played_at = receipt.parse(value)
    receipt.record!(@message, played_at) if played_at && receipt.applicable?(@message)
  end
end
