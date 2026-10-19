# Reschedules a Crm::FollowUp to a new due_at.
#
# This is the intent-named wrapper for moving a follow-up in time (used by the
# calendar drag/drop and the "Reschedule" event action). A plain
# PATCH /crm/follow_ups/:id { follow_up: { due_at } } already works through the
# controller's #update, but this service centralises the side effects so the
# calendar can call a single, intent-named action and so we can enforce the
# WhatsApp past-guard for auto_send_message follow-ups in one place.
#
# Side effects mirror the controller's `after_follow_up_change`:
#   - persists the new due_at (idempotent: a no-op when due_at is unchanged)
#   - re-applies the conversation snooze when in snooze_conversation mode
#   - recomputes card.next_follow_up_at via CardNextDueUpdater
#   - writes a `follow_up_rescheduled` Crm::Activity audit entry
#   - broadcasts the parent card so realtime clients update
#
# === Expected-close reschedule (NOT handled here) ===
# Rescheduling a deal's forecast / expected close date is a DIFFERENT concern and
# already has a working path — do NOT route it through this service and do NOT
# add a dedicated endpoint for it. The card update endpoint already permits the
# field:
#
#   PATCH /api/v1/accounts/:account_id/crm/cards/:id
#   body: { card: { expected_close_at: "<ISO8601>" } }
#
# (`expected_close_at` is in `Cards::Controller#update_params`.) The calendar's
# `expected_close` drag/drop reuses the existing `updateCard` store action with
# that single field. Only `next_follow_up_at`-bearing follow-up events are
# rescheduled through this class.
class Crm::FollowUps::Rescheduler
  class PastDueError < StandardError; end
  class NotAReminderError < StandardError; end

  # reminders_only (#1855): o reagendamento em lote do calendário ("Passar os meus para amanhã") só move lembrete de uma
  # pessoa. Envio ao cliente, inclusive o aviso de um que caiu, é recusado e fica como está; item a item, segue como antes.
  def initialize(follow_up:, user:, due_at:, reminders_only: false)
    @follow_up = follow_up
    @user = user
    @due_at = normalize_due_at(due_at)
    @reminders_only = reminders_only
  end

  def perform
    raise NotAReminderError, 'not_a_reminder' if @reminders_only && Crm::FollowUps::CallbackFallback.automatic_send?(@follow_up)

    validate_due_at!

    # Idempotent: skip persistence and side effects when nothing changed.
    return @follow_up if unchanged?

    @follow_up.transaction do
      restoring = restoring_automatic_send?
      @follow_up.update!(due_at: @due_at)
      @follow_up.update!(status: :pending) if @follow_up.overdue?
      @follow_up.update!(Crm::FollowUps::CallbackFallback.restoring_attributes(@follow_up)) if restoring
      Crm::FollowUps::SnoozeHandler.apply(@follow_up) if @follow_up.pending?
      Crm::FollowUps::CardNextDueUpdater.update(@follow_up.card)
      log_activity
    end

    broadcast_card
    @follow_up
  end

  private

  def normalize_due_at(due_at)
    return due_at if due_at.blank? || due_at.is_a?(ActiveSupport::TimeWithZone) || due_at.is_a?(Time)

    Time.zone.parse(due_at.to_s)
  rescue ArgumentError
    nil
  end

  def validate_due_at!
    raise PastDueError, 'due_at is required' if @due_at.blank?

    # WhatsApp auto-send cannot be scheduled in the past — there is no way to
    # send a message at a time that has already elapsed. Mirrors the
    # server-side guard called out in the manifest (R5).
    return unless @follow_up.auto_send_message? || restoring_automatic_send?
    return if @due_at.future?

    raise PastDueError, 'due_at must be in the future for auto-send follow-ups'
  end

  # Aviso da equipe que caiu por falha passageira da Meta (CallbackFallback): reagendar tenta o envio automático de novo.
  def restoring_automatic_send?
    Crm::FollowUps::CallbackFallback.restorable?(@follow_up)
  end

  def unchanged?
    persisted = @follow_up.due_at
    persisted.present? && persisted.to_i == @due_at.to_i
  end

  def log_activity
    Crm::ActivityLogger.new(
      card: @follow_up.card,
      actor: @user,
      event_type: 'follow_up_rescheduled',
      conversation: @follow_up.conversation,
      payload: activity_payload
    ).perform
  end

  def activity_payload
    {
      follow_up_id: @follow_up.id,
      title: @follow_up.title,
      status: @follow_up.status,
      automation_mode: @follow_up.automation_mode,
      due_at: @follow_up.due_at&.iso8601
    }
  end

  def broadcast_card
    Crm::Cards::Broadcaster.broadcast(@follow_up.card, Events::Types::CRM_CARD_UPDATED)
  end
end
