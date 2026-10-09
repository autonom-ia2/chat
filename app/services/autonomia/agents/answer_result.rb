module Autonomia
  module Agents
    # Resultado SÍNCRONO do motor de resposta. Fronteira de segurança: NUNCA carrega
    # instruction/scaffold/prompt montado. `used_knowledge[].content` é conteúdo do próprio
    # usuário (ok expor). `error` é um código curto (ex.: 'ai_unavailable'), nunca a mensagem
    # crua do LLM. `raw_reply` é o texto do modelo antes do portão (gerado, não é IP) — exposto
    # só no Copilot (/suggest); o Testar (/test) o ignora.
    class AnswerResult
      attr_reader :reply, :confidence, :handoff, :used_knowledge,
                  :answered_from_knowledge, :raw_reply, :error, :skipped_tools,
                  :writes_external

      SKIPPED_TOOL_CODES = %w[not_in_test viewer_not_allowed].freeze

      # handoff: { should: Boolean, reason: String|nil }
      # used_knowledge: Array<{ id:, content:, source: }>
      def initialize(reply:, confidence:, handoff:, used_knowledge: [],
                     answered_from_knowledge: false, raw_reply: nil, error: nil,
                     skipped_tools: [], writes_external: false)
        @reply = reply
        @confidence = confidence
        @handoff = handoff
        @used_knowledge = used_knowledge
        @answered_from_knowledge = answered_from_knowledge
        @raw_reply = raw_reply
        @error = error
        @skipped_tools = sanitize_skipped_tools(skipped_tools)
        @writes_external = writes_external == true
      end

      # Consumido pelo jbuilder do Testar. NÃO inclui raw_reply (esse é só do Copilot).
      def to_h
        {
          reply: reply,
          confidence: confidence,
          handoff: { should: handoff[:should], reason: handoff[:reason] },
          used_knowledge: used_knowledge,
          answered_from_knowledge: answered_from_knowledge,
          skipped_tools: skipped_tools,
          writes_external: writes_external,
          error: error
        }
      end

      private

      def sanitize_skipped_tools(items)
        Array(items).filter_map do |item|
          row = item.respond_to?(:to_h) ? item.to_h : {}
          code = row[:code] || row['code']
          next unless SKIPPED_TOOL_CODES.include?(code.to_s)

          {
            slug: (row[:slug] || row['slug']).to_s,
            name: (row[:name] || row['name']).to_s,
            code: code.to_s
          }
        end
      end
    end
  end
end
