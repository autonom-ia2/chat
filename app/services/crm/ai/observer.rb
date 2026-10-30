module Crm
  module Ai
    class Observer
      DEBOUNCE = Config::DEBOUNCE_SECONDS.seconds
      # Gatilho da avaliação agendada pela mensagem da equipe (#1923): fica na sugestão e no log, para medir à parte.
      TRIGGER_DA_EQUIPE = 'mensagem_da_equipe'.freeze

      def initialize(card:)
        @card = card
      end

      # Agenda (ou adia) a avaliação deste card: o debounce de sempre, uma rajada, uma avaliação.
      def schedule_evaluation(espera: DEBOUNCE)
        agendar(espera: espera) { false }
      end

      # A mensagem do cliente (#1675): não agenda de novo quando alguém já agendou depois de `chegada` (a troca de foco ou o
      # card novo da mesma mensagem) para rodar dentro do debounce dele. A avaliação da equipe (#1923), mais longa, não
      # conta: a do cliente a deixa velha e o cliente não espera a espera da equipe.
      def schedule_evaluation_do_cliente(chegada)
        agendar(espera: DEBOUNCE) { |estado| self.class.agendada_para_o_cliente?(estado, chegada) }
      end

      # A mensagem da pessoa da equipe (#1923): com uma avaliação esperando a vez (a do cliente ou a da equipe), não agenda
      # nem adia; aquela vai lê-la. Senão, agenda com a espera da equipe.
      def schedule_evaluation_da_equipe(espera)
        agendar(espera: espera, trigger: TRIGGER_DA_EQUIPE) { |estado| self.class.pendente?(estado) }
      end

      # A fala pública do nosso agente de IA (IA entende a conversa F1, Crm::Ai::FatosDaConversa): como a da equipe, não
      # agenda nem adia com uma avaliação esperando a vez; e no máximo MAX_AVALIACOES_DO_ROBO_POR_DIA por card, contadas
      # no `ai` do metadata sob a mesma trava. Passou do teto, não agenda e deixa a linha no log.
      def schedule_evaluation_do_robo(espera)
        fatos = Crm::Ai::FatosDaConversa
        agendar(espera: espera, trigger: fatos::TRIGGER_DO_ROBO, extra: ->(estado) { fatos.contar_avaliacao_do_robo(estado) }) do |estado|
          self.class.pendente?(estado) || cota_do_robo_esgotada?(estado)
        end
      end

      # Alguém já agendou a avaliação deste card depois de `momento` (#1675): a troca de foco ou o card novo da mesma
      # mensagem. Lê o token do card como ele veio do banco.
      def agendada_desde?(momento)
        self.class.agendada_desde?(ai_do(@card), momento)
      end

      # Já há avaliação agendada depois de `chegada` que roda dentro do debounce do cliente. Lê o card como veio do banco.
      def agendada_para_o_cliente?(chegada)
        self.class.agendada_para_o_cliente?(ai_do(@card), chegada)
      end

      def self.agendada_desde?(estado, momento)
        token = estado['evaluate_token']
        token.present? && token.to_f > momento.to_f
      end

      def self.agendada_para_o_cliente?(estado, chegada)
        agendada_desde?(estado, chegada) && !pendente?(estado, apos: DEBOUNCE.from_now)
      end

      # Há uma avaliação esperando a vez que roda depois de `apos`. `evaluate_after` que já passou é de uma avaliação que
      # rodou (ou caiu).
      def self.pendente?(estado, apos: Time.current)
        depois = estado['evaluate_after']
        depois.present? && Time.iso8601(depois.to_s) > apos
      rescue ArgumentError
        false
      end

      # Grava o token do agendamento no card (#1693: a avaliação conjunta usa o mesmo token em todos os cards dela). Uma
      # avaliação agendada antes, deste card, fica velha e não roda (EvaluateCardJob e EvaluateCardsJob).
      def marcar(token, espera: DEBOUNCE)
        travar { |estado| gravar(estado, token, espera) }
      end

      private

      def ai_do(card) = card.metadata.to_h.fetch('ai', {}).to_h

      def cota_do_robo_esgotada?(estado)
        return false unless Crm::Ai::FatosDaConversa.cota_do_robo_esgotada?(estado)

        Rails.logger.info("[crm][ai] card=#{@card.id} fala_do_robo=sem_avaliacao motivo=teto_do_dia")
        true
      end

      # A decisão (pular?) e a gravação acontecem sob a mesma trava do card: dois jobs da mesma conversa (o do cliente e o
      # da equipe) que rodam juntos não agendam os dois, e o token sai daqui de dentro, sempre maior que o gravado, para
      # que o agendamento mais novo seja sempre o que vale (#1923).
      # extra: o que mais gravar no `ai` junto com o agendamento (o contador da fala do robô), a partir do estado lido.
      def agendar(espera:, trigger: nil, extra: nil)
        return unless Config.enabled?

        token = travar do |estado|
          next if yield(estado)

          gravar(estado.merge(extra ? extra.call(estado) : {}), [Time.current.to_f, estado['evaluate_token'].to_f + 0.001].max, espera)
        end
        return if token.nil?

        Crm::Ai::EvaluateCardJob.set(wait: espera).perform_later(@card.id, token, *trigger)
        token
      end

      # Lido de novo dentro da trava: o card em memória pode ser de antes de outro processo gravar o metadata (estado do
      # follow-up, última avaliação) e sobrescrevê-lo. Um registro novo, não o @card: quem chamou pode ter alterações
      # ainda não salvas nele. O bloco recebe o `ai` do metadata do banco e devolve o token gravado, ou nil quando não grava.
      def travar
        Crm::Card.transaction do
          @fresh = Crm::Card.lock.find(@card.id)
          yield ai_do(@fresh)
        end
      end

      def gravar(estado, token, espera)
        metadata = (@fresh.metadata || {}).deep_dup
        metadata['ai'] = estado.merge('evaluate_after' => (Time.current + espera).iso8601, 'evaluate_token' => token)
        @fresh.update!(metadata: metadata)
        # Quem chamou continua com o metadata gravado: um save seguinte dele não apaga o token.
        @card.metadata = @fresh.metadata
        @card.clear_attribute_changes([:metadata])
        token
      end
    end
  end
end
