module Autonomia
  module Agents
    # "Testar" — camada fina de sandbox sobre o Answerer. Recebe agent + message + history
    # opcional, SEM conversa/inbox real. Delega direto ao Answerer (síncrono). Camada explícita
    # p/ o controller e p/ futura divergência Testar vs Operar (Fase D). NUNCA expõe prompt/IP.
    class Playground
      # #1367 — o Testar é medido à parte do atendimento (que segue `agente_resposta`).
      USAGE_FEATURE = 'agente_teste'.freeze

      def initialize(agent:, message:, history: [], images: [])
        @agent = agent
        @message = message
        @history = history
        @images = Array(images)
      end

      # -> Autonomia::Agents::AnswerResult
      def run
        Answerer.new(agent: @agent, query: @message, history: @history, images: @images, feature: USAGE_FEATURE).answer
      end
    end
  end
end
