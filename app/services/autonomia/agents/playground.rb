module Autonomia
  module Agents
    # "Testar" — camada fina de sandbox sobre o Answerer. Recebe agent + message + history
    # opcional, SEM conversa/inbox real. Delega direto ao Answerer (síncrono). Camada explícita
    # p/ o controller e p/ futura divergência Testar vs Operar (Fase D). NUNCA expõe prompt/IP.
    class Playground
      def initialize(agent:, message:, history: [], images: [], pode_editar: false)
        @agent = agent
        @message = message
        @history = history
        @images = Array(images)
        @pode_editar = pode_editar == true
      end

      # -> Autonomia::Agents::AnswerResult
      def run
        if internal_agent?
          return Copilot.new(agent: @agent, message: @message, history: @history, pode_editar: @pode_editar,
                             test_mode: true, surface: :copilot).suggest
        end

        Answerer.new(
          agent: @agent,
          query: @message,
          history: @history,
          images: @images,
          trust_instruction: true,
          audience: :customer,
          delivery: nil,
          test_mode: true,
          pode_editar: @pode_editar,
          surface: :test,
          **test_turn_options
        ).answer
      end

      private

      def internal_agent?
        @agent.respond_to?(:actuation) && @agent.actuation.to_s == 'internal'
      end

      # O Testar roda dentro do InteractiveJob, cujo pedido expira em 30 minutos. A última ida ao
      # modelo precisa caber antes do TTL; a receita da Lia foi escrita para o ReplyJob e chega a
      # 7.560 s. Neste caminho, mantém-se uma única rodada de ferramentas e reserva-se uma chamada
      # final inteira, sem alterar o orçamento do atendimento real nem chamar provider pago.
      def test_turn_options
        options = Autonomia::Insurance::QuoteAgent::Builder.rodadas_do_turno(@agent)
        return options if options[:max_segundos].blank?

        request_budget = Crm::Ai::InteractiveRequest::TTL.to_i
        last_call = Crm::Ai::ResponsesClient::REQUEST_TIMEOUT
        remaining = [request_budget - last_call, 0].max
        bounded_seconds = [options.fetch(:max_segundos).to_i, remaining].min
        bounded_rounds = [options.fetch(:max_rodadas).to_i, 1].min

        options.merge(max_rodadas: bounded_rounds, max_segundos: bounded_seconds)
      end
    end
  end
end
