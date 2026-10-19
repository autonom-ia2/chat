# #1460 — a série com as próximas datas (calculadas, no fuso da série) e as vezes que já passaram.
next_limit = 5
history_limit = 20

pending = series.follow_ups.pending.order(:due_at).first
last_occurrence = series.follow_ups.maximum(:occurrence_at)
upcoming = []
upcoming << pending.due_at if pending
unless series.ended?
  after = [last_occurrence, Time.current].compact.max
  upcoming += series.schedule.occurrences_after(after, limit: next_limit - upcoming.size)
end

json.extract! series, :id, :card_id, :contact_id, :company_id, :title, :description, :frequency, :weekdays, :weekdays_only,
              :ends_mode, :ends_on, :occurrences_count, :status, :timezone, :recipient_mode, :recipient_user_ids,
              :recipient_team_id
json.starts_at series.starts_at&.iso8601
json.paused_at series.paused_at&.iso8601
json.ended_at series.ended_at&.iso8601
json.pending_follow_up_id pending&.id
json.next_occurrences(upcoming.first(next_limit).map(&:iso8601))
json.recipient_names(Crm::FollowUps::RecipientResolver.new(pending || series.recipient_preview).users.map(&:name))
json.contact { json.extract! series.contact, :id, :name } if series.contact.present?
# Sem ver contatos, sem empresa (#1849, D7).
if series.company.present? && Crm::Cards::ContactReading.full?(user: Current.user, account_user: Current.account_user)
  json.company { json.extract! series.company, :id, :name }
end
json.card { json.extract! series.card, :id, :title, :pipeline_id } if series.card.present?
json.created_by { json.extract! series.created_by, :id, :name } if series.created_by.present?
json.history(series.follow_ups.where.not(status: :pending).order(occurrence_at: :desc).limit(history_limit)) do |follow_up|
  json.id follow_up.id
  json.occurrence_at follow_up.occurrence_at&.iso8601
  json.status follow_up.status
  json.completed_at follow_up.completed_at&.iso8601
end
