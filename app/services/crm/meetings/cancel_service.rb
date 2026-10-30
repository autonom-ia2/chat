class Crm::Meetings::CancelService
  # propagate:false — cancel LOCALLY only, skipping the provider delete. Used by the
  # 2-way sync (S7) when the event was already deleted/cancelled IN the provider
  # calendar (no echo-back). Default true = unchanged behavior.
  #
  # validar:false — grava sem as validações a reunião, o lembrete dela e a próxima data do card (#2096). A exclusão do
  # contato e o excluir de vez usam: a reunião de uma caixa removida (inbox_id nulo), o card ou o lembrete com dono que
  # saiu da conta não passam mais na validação, e o update! falharia DEPOIS de o Google ou a Microsoft já terem apagado
  # o evento, deixando a reunião "marcada" aqui. Cancelar não depende de nada disso continuar válido. Padrão true = como
  # sempre.
  def initialize(meeting:, propagate: true, validar: true)
    @meeting = meeting
    @propagate = propagate
    @validar = validar
  end

  def perform
    canceled_now = false

    @meeting.with_lock do
      next if @meeting.canceled?

      # 404/410 (already gone) are treated as success by delete_event; a REAL
      # provider error raises and rolls back, so we never mark the meeting
      # cancelled locally while it is still live on the provider. The lock makes
      # a double-cancel idempotent (the second request hits the guard above).
      delete_provider_event unless skip_provider_call?

      marcar_cancelada!
      cancel_reminder!
      Crm::FollowUps::CardNextDueUpdater.update(@meeting.card, validar: @validar)
      canceled_now = true
    end

    if canceled_now
      invalidate_availability!
      log_activity
    end
    @meeting.reload
  end

  private

  # Free the slot in the free/busy cache so the canceled time shows as available
  # again on the next scheduler open.
  def invalidate_availability!
    return if @meeting.inbox_id.blank? || @meeting.starts_at.blank?

    day = @meeting.starts_at.in_time_zone(@meeting.timezone.presence || 'UTC').to_date.to_s
    Crm::Meetings::AvailabilityService.invalidate(
      inbox_id: @meeting.inbox_id, date: day, timezone: @meeting.timezone
    )
  end

  def marcar_cancelada!
    @meeting.status = :canceled
    @meeting.save!(validate: @validar)
  end

  def skip_provider_call?
    return true unless @propagate

    external_id = @meeting.external_event_id
    external_id.blank? || external_id.to_s.start_with?('sim-') ||
      (@meeting.google? && Crm::Config.calendar_google_simulate?) ||
      (@meeting.microsoft? && Crm::Config.calendar_ms_simulate?)
  end

  def delete_provider_event
    if @meeting.microsoft?
      Microsoft::CalendarEventService.new(meeting: @meeting).delete_event(@meeting.external_event_id)
    elsif @meeting.google?
      Google::CalendarEventService.new(channel: @meeting.email_channel, meeting_params: {}, guests: [])
                                  .delete_event(@meeting.external_event_id)
    end
  end

  def cancel_reminder!
    reminder = @meeting.reminder
    return if reminder.blank? || reminder.canceled? || reminder.done?

    reminder.status = :canceled
    reminder.save!(validate: @validar)
  end

  def log_activity
    Crm::ActivityLogger.new(
      card: @meeting.card,
      actor: @meeting.created_by,
      event_type: 'meeting_canceled',
      conversation: @meeting.card.primary_conversation,
      payload: {
        meeting_id: @meeting.id,
        title: @meeting.title,
        starts_at: @meeting.starts_at&.iso8601,
        provider: @meeting.provider
      }
    ).perform
  end
end
