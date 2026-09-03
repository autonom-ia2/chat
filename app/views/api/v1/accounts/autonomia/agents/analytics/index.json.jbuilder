json.range @analytics[:range]
json.conversations_handled @analytics[:conversations_handled]
json.replies_sent @analytics[:replies_sent]
json.handoff_count @analytics[:handoff_count]
json.handoff_rate @analytics[:handoff_rate]
json.avg_confidence @analytics[:avg_confidence]
json.knowledge_answer_rate @analytics[:knowledge_answer_rate]

json.top_handoff_reasons @analytics[:top_handoff_reasons] do |row|
  json.reason row[:reason]
  json.count row[:count]
end

json.outcomes do
  json.handled @analytics[:outcomes][:handled]
  json.resolved_without_human @analytics[:outcomes][:resolved_without_human]
  json.handed_off @analytics[:outcomes][:handed_off]
  json.reopened @analytics[:outcomes][:reopened]
  json.wrong_replies @analytics[:outcomes][:wrong_replies]
end

json.timeline @analytics[:timeline] do |point|
  json.date point[:date]
  json.replies point[:replies]
  json.handoffs point[:handoffs]
end

if @analytics[:insight].present?
  json.insight do
    json.type @analytics[:insight][:type]
    json.handoff_rate @analytics[:insight][:handoff_rate]
    json.knowledge_answer_rate @analytics[:insight][:knowledge_answer_rate]
    json.top_reasons @analytics[:insight][:top_reasons] do |row|
      json.reason row[:reason]
      json.count row[:count]
    end
  end
else
  json.insight nil
end
