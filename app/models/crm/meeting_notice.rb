# Um aviso no WhatsApp de uma reunião do agendamento (#1192, J5-A1): ao marcar, remarcada, 1 dia antes ou 1 hora
# antes. Nasce `pending` com o vencimento; o cron (`Crm::BookingV2::NoticeDispatchJob`) o pega de forma atômica
# (`sending`) e o `Notices::Sender` grava o resultado: `sent`, `skipped` (com o motivo) ou `failed` (com o erro).
# Nada aqui altera a reunião (J5-A4).
class Crm::MeetingNotice < ApplicationRecord
  self.table_name = 'crm_meeting_notices'

  KINDS = %w[booked rescheduled day_before hour_before].freeze
  # Avisos que lembram do horário (vencem antes da reunião); `booked` e `rescheduled` saem na hora.
  REMINDER_KINDS = %w[day_before hour_before].freeze

  belongs_to :meeting, class_name: 'Crm::Meeting'
  belongs_to :account

  enum status: { pending: 0, sending: 1, sent: 2, skipped: 3, failed: 4 }

  validates :kind, inclusion: { in: KINDS }
  validates :due_at, presence: true

  def as_summary
    { kind: kind, due_at: due_at&.iso8601, status: status, skip_reason: skip_reason }
  end
end
