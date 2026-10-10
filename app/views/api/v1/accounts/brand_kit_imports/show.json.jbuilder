json.id @import.id
json.url @import.url
json.status @import.status
json.error_code @import.error_code
json.error_message(@import.error_code.present? ? error_message(@import.error_code) : nil)
json.started_at @import.started_at
json.finished_at @import.finished_at
json.created_at @import.created_at
json.proposal(@import.succeeded? ? @import.result : nil)
