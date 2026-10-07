# Um envio do resumo ou do alerta de uma conexão (#1100, F4b). Ver Crm::MetaAds::WhatsappReport::Sender.
#
# No máximo um de cada por dia: antes de enviar, `SET NX` de 36 h na chave da conta, do tipo e do dia no fuso da
# conta de anúncios. Sem a chave, não envia.
# - Falha clara (nada saiu): apaga a chave e grava `last_error`. A próxima rodada é a do dia seguinte (cron diário).
# - `send_uncertain` (pode ter saído): mantém a chave e grava `last_error`; nunca reenvia.
# - Erro inesperado: sobe, e a chave fica, para um novo tentar do Sidekiq não mandar duas vezes.
# - Sucesso: grava `last_summary_at` ou `last_alert_at`.
#
# Ontem sem gasto e sem conversa, o resumo não sai e `last_error` fica `nothing_to_report` (informativo). Nenhum
# anúncio no critério, o alerta não sai e nada é gravado.
class Crm::MetaAds::WhatsappReport::DeliverJob < ApplicationJob
  queue_as :low

  FEATURE = 'meta_ads_hub'.freeze
  LOCK_TTL = 36.hours
  KEY_PREFIX = 'crm:meta_ads:whatsapp_report'.freeze
  NOTHING_TO_REPORT = 'nothing_to_report'.freeze
  UNCERTAIN = 'send_uncertain'.freeze

  def perform(connection_id, kind)
    raise ArgumentError, "unknown kind #{kind}" unless Crm::MetaAdsConnection::WHATSAPP_REPORT_FLAGS.key?(kind)

    connection = Crm::MetaAdsConnection.find_by(id: connection_id)
    return unless deliverable?(connection, kind)

    kind == 'summary' ? deliver_summary(connection) : deliver_alert(connection)
  end

  def self.lock_key(connection, kind)
    "#{KEY_PREFIX}:#{connection.account_id}:#{kind}:#{connection.ad_account_today || Time.zone.today}"
  end

  private

  def deliverable?(connection, kind)
    connection.present? && connection.active? && connection.ad_account_id.present? &&
      connection.whatsapp_report_on?(kind) && connection.account.feature_enabled?(FEATURE)
  end

  def deliver_summary(connection)
    digest = Crm::MetaAds::WhatsappReport::Digest.new(connection, with_ai: true)
    return settings(connection).record_error!(NOTHING_TO_REPORT) if digest.nothing_to_report?

    # Números e texto da IA antes da chave do dia: um erro aqui sobe sem a chave, e o novo tentar do Sidekiq refaz.
    payload = digest.payload
    deliver(connection, 'summary') do |sender|
      sender.send_summary(payload)
      # Só o envio real conta a ação 1 como mostrada (F5, métrica de aceite); o de teste não passa por aqui.
      digest.mark_shown!
    end
  end

  def deliver_alert(connection)
    alert = Crm::MetaAds::WhatsappReport::SpendAlert.new(connection).candidate
    return if alert.nil?

    deliver(connection, 'alert') { |sender| sender.send_alert(alert) }
  end

  def deliver(connection, kind)
    key = self.class.lock_key(connection, kind)
    return unless Redis::Alfred.set(key, 1, nx: true, ex: LOCK_TTL.to_i)

    yield Crm::MetaAds::WhatsappReport::Sender.new(connection)
    settings(connection).record_sent!(kind)
  rescue Crm::MetaAds::WhatsappReport::Settings::Error => e
    Redis::Alfred.delete(key) unless e.code == UNCERTAIN
    settings(connection).record_error!(e.code)
  end

  def settings(connection)
    Crm::MetaAds::WhatsappReport::Settings.new(connection)
  end
end
