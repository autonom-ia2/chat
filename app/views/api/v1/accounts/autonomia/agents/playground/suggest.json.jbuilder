json.reply (@result.reply.presence || @result.raw_reply)
json.confidence @result.confidence
json.handoff do
  json.set! :should, @result.handoff[:should]
  json.reason @result.handoff[:reason]
end
json.answered_from_knowledge @result.answered_from_knowledge
json.used_knowledge @result.used_knowledge do |k|
  json.content k[:content]
  json.source k[:source]
end
json.error @result.error if @result.error.present?
