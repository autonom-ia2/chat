json.reply @result.reply
json.confidence @result.confidence
json.handoff do
  json.set! :should, @result.handoff[:should]
  json.reason @result.handoff[:reason]
end
json.answered_from_knowledge @result.answered_from_knowledge
json.skipped_tools @result.skipped_tools do |tool|
  json.slug tool[:slug]
  json.name tool[:name]
  json.code tool[:code]
end
json.writes_external @result.writes_external
json.used_knowledge @result.used_knowledge do |k|
  json.content k[:content]
  json.source k[:source]
end
json.error @result.error if @result.error.present?

# ENTREGA HUMANIZADA (paridade do Testar com a produção): quando ligada para o agente, expõe os
# MESMOS pedaços + delay (ms) do ReplyChunker que o canal real entregaria, para o painel tocar a
# prévia com bolha "digitando" e pausas. `humanized=false` -> o FE mostra 1 balão (texto completo).
humanized = Autonomia::Agents::Config.humanize_delivery_enabled?(@agent)
json.humanized humanized
if humanized && @result.reply.present? && !@result.handoff[:should]
  json.chunks(Autonomia::Agents::Operate::ReplyChunker.call(@result.reply)) do |chunk|
    json.text chunk['text']
    json.type chunk['type']
    json.delay_ms chunk['delay_ms']
  end
else
  json.chunks []
end
