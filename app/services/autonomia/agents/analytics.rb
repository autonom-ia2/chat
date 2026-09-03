module Autonomia
  module Agents
    # Fase F — Analytics de Desempenho. Agrega autonomia_agent_events SEMPRE escopado
    # por agente+conta sobre uma janela (7d/30d). Nada de IP: só métricas numéricas e
    # motivos de handoff já curados (truncados) pelo EventLogger.
    class Analytics
      RANGES = { '7d' => 7, '30d' => 30 }.freeze
      DEFAULT_RANGE = '7d'.freeze
      TOP_REASONS_LIMIT = 5

      # #284 — resultados por conversa (números clicáveis). DERIVADOS de dados existentes, sem tabela
      # de episódios: autonomia_agent_events (quem o agente atendeu / handoff sinalizado),
      # reporting_events do core (conversation_resolved / conversation_opened / conversation_bot_handoff)
      # e Captain::MessageReport (respostas marcadas como erradas).
      OUTCOME_METRICS = %w[handled resolved_without_human handed_off reopened wrong_replies].freeze

      INSIGHT_MIN_EVENTS = 10
      HIGH_HANDOFF_RATE  = 0.4
      LOW_KNOWLEDGE_RATE = 0.3

      attr_reader :range

      def initialize(agent:, range: DEFAULT_RANGE)
        @agent = agent
        @range = RANGES.key?(range.to_s) ? range.to_s : DEFAULT_RANGE
        @days  = RANGES[@range]
        @to    = Time.current
        # Alinha a janela de eventos ao PRIMEIRO balde renderizado pela timeline
        # (que cobre exatamente @days dias terminando hoje). Com @days.days.ago a
        # janela abriria 1 dia antes do primeiro balde -> eventos desse dia entrariam
        # nos cards/rates mas em NENHUMA barra, e a soma das barras < replies_sent.
        @from  = (@days - 1).days.ago.beginning_of_day
      end

      def call
        {
          range: @range,
          conversations_handled: conversations_handled,
          replies_sent: replies_count,
          handoff_count: handoff_count,
          handoff_rate: handoff_rate,
          avg_confidence: avg_confidence,
          knowledge_answer_rate: knowledge_answer_rate,
          top_handoff_reasons: top_handoff_reasons,
          timeline: timeline,
          insight: insight,
          outcomes: outcomes
        }
      end

      # { handled:, resolved_without_human:, handed_off:, reopened:, wrong_replies: } — contagens.
      # wrong_replies conta RESPOSTAS reportadas; as demais contam CONVERSAS distintas.
      def outcomes
        OUTCOME_METRICS.index_with do |metric|
          metric == 'wrong_replies' ? wrong_reply_reports.count : outcome_scope(metric).count
        end.symbolize_keys
      end

      # Relation de Conversation por métrica (a lista que abre no clique). Sempre presa à conta do
      # agente. Métrica desconhecida -> none (nunca 500, nunca "todas").
      def outcome_scope(metric)
        case metric.to_s
        when 'handled' then handled_conversations
        when 'resolved_without_human' then resolved_without_human_conversations
        when 'handed_off' then handed_off_conversations
        when 'reopened' then reopened_conversations
        when 'wrong_replies' then reported_conversations
        else ::Conversation.none
        end
      end

      private

      def events
        @events ||= ::Autonomia::Agents::AgentEvent
                    .where(autonomia_agent_id: @agent.id, account_id: @agent.account_id)
                    .in_range(@from, @to)
      end

      # group(:event_type) chaveia por NOME do enum ("replied"/"handed_off").
      def counts_by_type
        @counts_by_type ||= events.group(:event_type).count
      end

      def replies_count
        counts_by_type['replied'].to_i
      end

      def handoff_count
        counts_by_type['handed_off'].to_i
      end

      # Conversas distintas tocadas pelo bot na janela (replied OU handed_off).
      def conversations_handled
        events.where.not(conversation_id: nil).distinct.count(:conversation_id)
      end

      # handoffs / (replies + handoffs). 0 quando não houve atividade.
      def handoff_rate
        total = replies_count + handoff_count
        total.zero? ? 0.0 : (handoff_count.to_f / total).round(4)
      end

      def avg_confidence
        avg = events.replied.where.not(confidence: nil).average(:confidence)
        avg ? avg.to_f.round(4) : nil
      end

      # % de replies respondidas a partir do conhecimento.
      def knowledge_answer_rate
        replies = replies_count
        return 0.0 if replies.zero?

        from_knowledge = events.replied.where(answered_from_knowledge: true).count
        (from_knowledge.to_f / replies).round(4)
      end

      # [{ reason:, count: }] dos handoffs com motivo, SEMPRE colapsado a um código da
      # allowlist. Blank/NULL/legado-freeform -> 'other'. Soma no Ruby para que NULL e ''
      # (dado legado) não virem duas linhas distintas e para nunca vazar texto livre legado
      # pelo endpoint (defesa em profundidade, além do EventLogger no caminho de escrita).
      def top_handoff_reasons
        events.handed_off.group(:handoff_reason).count
              .each_with_object(Hash.new(0)) { |(reason, count), acc| acc[curate_reason(reason)] += count }
              .map { |reason, count| { reason: reason, count: count } }
              .sort_by { |row| -row[:count] }
              .first(TOP_REASONS_LIMIT)
      end

      def curate_reason(reason)
        code = reason.to_s.strip.downcase
        ::Autonomia::Agents::Operate::EventLogger::ALLOWED_REASONS.include?(code) ? code : 'other'
      end

      # [{ date: 'YYYY-MM-DD', replies:, handoffs: }] por dia do range (zeros incluídos).
      def timeline
        replied_by_day = day_buckets(events.replied)
        handed_by_day  = day_buckets(events.handed_off)
        (0...@days).map do |offset|
          date = (@to.to_date - (@days - 1 - offset))
          key  = date.iso8601
          { date: key, replies: replied_by_day[key].to_i, handoffs: handed_by_day[key].to_i }
        end
      end

      def day_buckets(scope)
        scope.group('DATE(created_at)').count
             .transform_keys { |d| d.is_a?(String) ? d : d.iso8601 }
      end

      # ---- Resultados por conversa (#284) ------------------------------------------------------

      # Conversas tocadas pelo agente (replied/handed_off) NA JANELA — o "universo" dos resultados.
      def handled_conversations
        ::Conversation.where(account_id: @agent.account_id, id: handled_ids)
      end

      def handled_ids
        events.where.not(conversation_id: nil).select(:conversation_id)
      end

      # Todas as conversas que o agente já tocou (sem janela): usada para excluir handoffs antigos e
      # para ligar reports de mensagens à conversa do agente.
      def all_time_handled_ids
        ::Autonomia::Agents::AgentEvent.where(autonomia_agent_id: @agent.id, account_id: @agent.account_id)
                                       .where.not(conversation_id: nil).select(:conversation_id)
      end

      # Passadas para humano na janela: handoff sinalizado pela instrução/CRM (evento handed_off) OU
      # CONVERSATION_BOT_HANDOFF do core (humano assumiu / desconexão), pelo reporting_event.
      def handed_off_conversations
        handled_conversations.where(id: events.handed_off.select(:conversation_id))
                             .or(handled_conversations.where(id: reporting_events('conversation_bot_handoff').select(:conversation_id)))
      end

      # Resolvidas na janela SEM humano: sem handoff em qualquer momento e sem resposta pública de
      # um usuário (User) na conversa.
      def resolved_without_human_conversations
        handled_conversations
          .where(id: reporting_events('conversation_resolved').select(:conversation_id))
          .where.not(id: all_time_handoff_ids)
          .where.not(id: human_replied_ids)
      end

      def all_time_handoff_ids
        from_events = ::Autonomia::Agents::AgentEvent.where(autonomia_agent_id: @agent.id, account_id: @agent.account_id)
                                                     .handed_off.where.not(conversation_id: nil).select(:conversation_id)
        from_core = ::ReportingEvent.where(account_id: @agent.account_id, name: 'conversation_bot_handoff',
                                           conversation_id: all_time_handled_ids).select(:conversation_id)
        ::Conversation.where(id: from_events).or(::Conversation.where(id: from_core)).select(:id)
      end

      def human_replied_ids
        ::Message.where(account_id: @agent.account_id, conversation_id: handled_ids, message_type: :outgoing,
                        sender_type: 'User', private: false).select(:conversation_id)
      end

      # Reabertas na janela: conversation_opened precedido por um conversation_resolved da mesma conversa
      # (o core grava opened também na 1ª abertura; o EXISTS separa a reabertura).
      def reopened_conversations
        reopened = reporting_events('conversation_opened').where(<<~SQL.squish)
          EXISTS (
            SELECT 1 FROM reporting_events r
            WHERE r.conversation_id = reporting_events.conversation_id
              AND r.name = 'conversation_resolved'
              AND r.event_end_time <= reporting_events.event_end_time
          )
        SQL
        handled_conversations.where(id: reopened.select(:conversation_id))
      end

      def reporting_events(name)
        ::ReportingEvent.where(account_id: @agent.account_id, name: name, conversation_id: handled_ids,
                               event_end_time: @from..@to)
      end

      # Respostas marcadas como erradas na janela: reports em mensagens do AgentBot em conversas que o
      # agente atendeu (qualquer momento). Uma caixa tem um agente por vez, logo a conversa identifica
      # o agente sem depender do message_id do evento (a entrega em pedaços posta várias mensagens).
      def wrong_reply_reports
        ::Captain::MessageReport.joins(:message)
                                .where(account_id: @agent.account_id, created_at: @from..@to)
                                .where(messages: { sender_type: 'AgentBot', conversation_id: all_time_handled_ids })
      end

      def reported_conversations
        ::Conversation.where(account_id: @agent.account_id, id: wrong_reply_reports.select(:conversation_id))
      end

      # INSIGHT honesto e simples derivado das métricas. nil quando não há sinal/dados.
      def insight
        return nil if (replies_count + handoff_count) < INSIGHT_MIN_EVENTS

        if handoff_rate >= HIGH_HANDOFF_RATE || knowledge_answer_rate <= LOW_KNOWLEDGE_RATE
          {
            type: handoff_rate >= HIGH_HANDOFF_RATE ? 'high_handoff' : 'low_knowledge',
            handoff_rate: handoff_rate,
            knowledge_answer_rate: knowledge_answer_rate,
            top_reasons: top_handoff_reasons.first(3)
          }
        end
      end
    end
  end
end
