module Autonomia
  module Agents
    # "Testar" — camada fina de sandbox sobre o Answerer. Recebe agent + message + history
    # opcional, SEM conversa/inbox real. Delega direto ao Answerer (síncrono). Camada explícita
    # p/ o controller e p/ futura divergência Testar vs Operar (Fase D). NUNCA expõe prompt/IP.
    class Playground
      # #1367 — o Testar é medido à parte do atendimento (que segue `agente_resposta`).
      USAGE_FEATURE = 'agente_teste'.freeze

      QUANTITY_QUESTION = /\b(?:quant[oa]s|qual (?:é )?a quantidade|how many)\b[^.!?]*\?\s*\z/i
      QUANTITY_HISTORY_MESSAGES = 4
      QUANTITY_HISTORY_ITEM_CHARS = 400

      # Tema 6 (#1428): o Testar, a prova do ajuste, o autoteste do material e a comparação da base medem o MESMO agente
      # que atende o cliente: sem o portão de confiança, como o Responder (`trust_instruction`). Com o portão, a resposta
      # do modelo era trocada pela mensagem fixa, e o dono testava um agente que o cliente nunca vê. A Lia
      # (insurance_quote) fica no portão (decisão do Rodrigo de 30/10, D6).
      # TODO(#2382): desvio por tipo de agente, temporário; o Testar da Lia também deve medir o motor do atendimento.
      def self.como_no_atendimento?(agent)
        agent.agent_type != 'insurance_quote'
      end

      # #2918: as rodadas do Testar e do Copiloto são as do atendimento (`RodadasDoTurno`): o agente com ajudante ou com
      # pronta testa com as mesmas da produção. A Lia fica no desvio dela (o TODO acima): uma rodada, como antes.
      def self.rodadas(agent)
        como_no_atendimento?(agent) ? RodadasDoTurno.para(agent) : {}
      end

      def initialize(agent:, message:, history: [], images: [])
        @agent = agent
        @message = message
        @history = history
        @images = Array(images)
      end

      # -> Autonomia::Agents::AnswerResult
      def run
        # Tema 14 (#1434) e #2918: as mesmas rodadas da produção (ajudante, pronta).
        Answerer.new(agent: @agent, query: @message, history: @history, images: @images, feature: USAGE_FEATURE,
                     retrieval_query: quantity_retrieval_query, trust_instruction: self.class.como_no_atendimento?(@agent),
                     **self.class.rodadas(@agent)).answer
      end

      private

      # O número sozinho não identifica o assunto da busca. Usa a pergunta de quantidade e os turnos que a antecedem.
      def quantity_retrieval_query
        quantity = @message.to_s.strip
        return unless quantity.match?(/\A[0-9]{1,9}\z/)

        turns = Array(@history).last(QUANTITY_HISTORY_MESSAGES)
        last_turn = turns.last
        return unless last_turn && last_turn[:role] == 'assistant' && QUANTITY_QUESTION.match?(last_turn[:content].to_s)

        context = turns.reverse.map { |turn| turn[:content].to_s[0, QUANTITY_HISTORY_ITEM_CHARS] }
        ["Quantidade: #{quantity}", *context].join("\n")
      end
    end
  end
end
