# #2907 — Aplica o aviso `account_update` da Meta às caixas da WABA.
#
# Perda de acesso (doc da Meta, webhooks/reference/account_update):
# - PARTNER_REMOVED: a empresa tirou a WABA do parceiro (no coexistência, também ao desconectar no app);
# - PARTNER_APP_UNINSTALLED: a empresa desautorizou o app;
# - ACCOUNT_DELETED: a conta foi apagada;
# - ACCOUNT_OFFBOARDED: coexistência desfeita por troca de aparelho ou novo registro do número.
# Nesses, a caixa fica "precisa reconectar" na hora, sem esperar a checagem de saúde.
#
# ACCOUNT_RECONNECTED (a Meta religou a coexistência sozinha e devolveu o acesso à mesma WABA, segundo a doc) apaga o aviso
# e pede uma checagem de saúde: se o acesso não voltou de fato, a contagem da checagem marca de novo.
#
# A WABA vem em `waba_info.waba_id` nos eventos de parceiro (lá o `entry.id` é o portfólio do parceiro) e no `entry.id`
# nos demais. Campo fora do formato é ignorado, nunca derruba as outras mudanças do POST; evento de acesso sem caixa
# conhecida fica no log.
#
# A Meta reenvia o mesmo aviso: a caixa já marcada não é marcada de novo (o e-mail de desconexão sai a cada marcação).
class Whatsapp::AccessLoss::AccountUpdateJob < ApplicationJob
  queue_as :default

  ACCESS_LOST_EVENTS = %w[PARTNER_REMOVED PARTNER_APP_UNINSTALLED ACCOUNT_DELETED ACCOUNT_OFFBOARDED].freeze
  RECONNECTED_EVENT = 'ACCOUNT_RECONNECTED'.freeze

  # changes: [{ 'entry_id', 'value' }], na ordem do POST.
  def perform(changes)
    Array(changes).each { |change| apply(change) if change.is_a?(Hash) }
  end

  private

  def apply(change)
    value = hash_or_empty(change['value'])
    event = value['event'].to_s
    return unless ACCESS_LOST_EVENTS.include?(event) || event == RECONNECTED_EVENT

    waba_id = hash_or_empty(value['waba_info'])['waba_id'].to_s.presence || change['entry_id'].to_s
    channels = channels_for(waba_id).to_a
    return log_unknown(event, waba_id) if channels.empty?

    channels.each do |channel|
      log(channel, event, hash_or_empty(value['disconnection_info']))
      event == RECONNECTED_EVENT ? reconnected(channel) : access_lost(channel)
    end
  end

  def access_lost(channel)
    Whatsapp::AccessLoss::GuideAlert.marcar_pela_meta!(channel)
    channel.prompt_reauthorization! unless channel.reauthorization_required?
    Whatsapp::AccessLoss::GuideAlert.avisar!(channel)
  end

  def reconnected(channel)
    channel.reauthorized!
    Channels::Whatsapp::HealthSyncJob.perform_later(channel)
  end

  def channels_for(waba_id)
    return Channel::Whatsapp.none if waba_id.blank?

    Channel::Whatsapp.where(provider: 'whatsapp_cloud').where("provider_config ->> 'business_account_id' = ?", waba_id.to_s)
  end

  def hash_or_empty(value) = value.is_a?(Hash) ? value : {}

  def log(channel, event, disconnection_info)
    Rails.logger.warn(
      "[WHATSAPP ACCESS] account_update event=#{event} account_id=#{channel.account_id} inbox_id=#{channel.inbox&.id} " \
      "channel_id=#{channel.id} disconnection=#{disconnection_info.slice('reason', 'initiated_by').to_json}"
    )
  end

  def log_unknown(event, waba_id)
    Rails.logger.warn("[WHATSAPP ACCESS] account_update event=#{event} sem caixa conhecida waba_id=#{waba_id.presence || '-'}")
  end
end
