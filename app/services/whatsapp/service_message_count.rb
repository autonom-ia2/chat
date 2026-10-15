# Quantas respostas ao cliente (mensagem livre, sem modelo) cada número do WhatsApp oficial mandou no mês corrente
# (#1332): a tela compara com a franquia de `Whatsapp::Pricing.free_tier('service')`. Conta mensagens enviadas, não
# privadas, que não falharam e não levam modelo (`additional_attributes.template_params`).
#
# Regra oficial (developers.facebook.com/docs/whatsapp/pricing, atualizada em 30/09/2026; #1592): a franquia é por
# número, conta mensagem entregue e vira à meia-noite no fuso da conta do WhatsApp (WABA), não em UTC. O fuso vem de
# `Whatsapp::WabaTimezone`; sem ele, vale o fuso da conta do Chat2You (e, sem esse, UTC), com log.
#
# Reação não conta na franquia, e já fica fora: o Chat2You não manda reação e o eco de reação mandada pelo app
# (coexistência) é descartado na entrada (`unprocessable_message_type?`), sem virar mensagem.
#
# É estimativa: só vê o que saiu pelo Chat2You (o que sai por fora, no mesmo número, não entra) e conta "não falhou",
# não "entregue". O número exato virá do `pricing.type` do status (#1614).
#
# Uma consulta por fuso (quase sempre uma só para todas as caixas), guardada por 5 minutos.
class Whatsapp::ServiceMessageCount
  CACHE_TTL = 5.minutes

  def initialize(account:, inbox_ids:, now: Time.current)
    @account = account
    @inbox_ids = inbox_ids.sort
    @now = now
  end

  # { inbox_id => n }, com 0 para a caixa que não mandou nada.
  def perform
    counts = inbox_ids_by_zone.reduce({}) { |all, (zone, ids)| all.merge(count(zone, ids)) }
    @inbox_ids.index_with { |inbox_id| counts.fetch(inbox_id, 0) }
  end

  private

  def count(zone, inbox_ids)
    month_start = @now.in_time_zone(zone).beginning_of_month
    Rails.cache.fetch(['whatsapp_service_message_count', @account.id, inbox_ids, zone.tzinfo.identifier, month_start.to_date],
                      expires_in: CACHE_TTL) do
      Message.where(account_id: @account.id, inbox_id: inbox_ids, message_type: :outgoing, private: false,
                    created_at: month_start..@now)
             .where.not(status: :failed)
             .where("(messages.additional_attributes -> 'template_params') IS NULL")
             .reorder(nil).group(:inbox_id).count
    end
  end

  def inbox_ids_by_zone
    channels = @account.inboxes.where(id: @inbox_ids).includes(:channel).to_h { |inbox| [inbox.id, inbox.channel] }
    @inbox_ids.group_by { |inbox_id| zone_for(inbox_id, channels[inbox_id]) }
  end

  def zone_for(inbox_id, channel)
    zone = Whatsapp::WabaTimezone.for(channel) if channel.is_a?(Channel::Whatsapp)
    return zone if zone

    Rails.logger.info "[Whatsapp::ServiceMessageCount] inbox=#{inbox_id} waba_timezone=missing fallback=account_timezone"
    account_zone
  end

  def account_zone
    @account_zone ||= ActiveSupport::TimeZone[@account.reporting_timezone.to_s] || ActiveSupport::TimeZone['UTC']
  end
end
