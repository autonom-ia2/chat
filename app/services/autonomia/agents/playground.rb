module Autonomia
  module Agents
    # "Testar" — camada fina de sandbox sobre o Answerer. Recebe agent + message + history
    # opcional, SEM conversa/inbox real. Delega direto ao Answerer (síncrono). Camada explícita
    # p/ o controller e p/ futura divergência Testar vs Operar (Fase D). NUNCA expõe prompt/IP.
    class Playground
      # #1367 — o Testar é medido à parte do atendimento (que segue `agente_resposta`).
      USAGE_FEATURE = 'agente_teste'.freeze

      # Tema 6 (#1428): o Testar, a prova do ajuste, o autoteste do material e a comparação da base medem o MESMO agente
      # que atende o cliente: sem o portão de confiança, como o Responder (`trust_instruction`). Com o portão, a resposta
      # do modelo era trocada pela mensagem fixa, e o dono testava um agente que o cliente nunca vê. A Lia
      # (insurance_quote) fica no portão (decisão do Rodrigo de 30/10, D6).
      def self.como_no_atendimento?(agent)
        agent.agent_type != 'insurance_quote'
      end

      def initialize(agent:, message:, history: [], images: [])
        @agent = agent
        @message = message
        @history = history
        @images = Array(images)
      end

      # -> Autonomia::Agents::AnswerResult
      def run
        # Tema 14 (#1434): o principal com ajudante testa com as mesmas rodadas da produção.
        Answerer.new(agent: @agent, query: @message, history: @history, images: @images, feature: USAGE_FEATURE,
                     trust_instruction: self.class.como_no_atendimento?(@agent), **(Ajudantes.rodadas(@agent) || {})).answer
      end
    end
  end
end
