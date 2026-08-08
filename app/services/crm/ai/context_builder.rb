module Crm
  module Ai
    class ContextBuilder
      MAX_RECENT_MESSAGES = 12
      MAX_MESSAGES_CAP = 40

      # A legenda dos papéis mora junto de quem os produz (#role_for). Todo prompt que lê
      # recent_messages descreve os papéis a partir daqui: foi a cópia divergente que fez o
      # follow-up receber "human_agent" e ler uma instrução que só falava de "customer" e "agent".
      ROLES_LEGEND = 'Cada mensagem tem um "role": "customer" (o cliente), "human_agent" (uma pessoa do time), ' \
                     '"platform_agent" (agente de IA da plataforma, incluindo os follow-ups automáticos anteriores) ' \
                     'ou "external_agent" (bot ou automação externa).'.freeze

      def initialize(card:)
        @card = card
      end

      def perform
        {
          summary: ai_metadata['summary'].to_s,
          recent_messages: recent_messages,
          current_stage: {
            id: @card.stage_id,
            name: @card.stage&.name
          },
          known_attributes: known_attributes,
          conversation_state: conversation_state,
          temporal: temporal_context
        }
      end

      private

      # Valores JÁ salvos dos atributos customizados (contato + conversa). O classificador recebe o
      # SCHEMA (chaves permitidas) em attribute_schema; aqui vão os VALORES atuais, para ele decidir o
      # estágio ciente do que já se sabe e não re-extrair o que não mudou.
      def known_attributes
        {
          contact: attribute_values(@card.try(:contact)),
          conversation: attribute_values(@card.primary_conversation)
        }
      end

      def attribute_values(record)
        attributes = record.try(:custom_attributes)
        return {} unless attributes.is_a?(Hash)

        # compact_blank descartaria `false` (false.blank? == true), mas checkbox salvo como
        # false é valor real. Removemos só nil/""/coleções vazias, preservando false e 0.
        attributes.reject { |_key, value| value != false && value.blank? }
      end

      # Estado atual do atendimento. Os papéis por mensagem dizem QUEM falou; isto diz quem está com a
      # conversa AGORA: resolvida por gente, atribuída a uma pessoa, e há quanto tempo um humano falou.
      # Sem isso a IA decide retomar uma conversa que uma pessoa do time está conduzindo neste momento.
      def conversation_state
        conversation = latest_conversation
        return {} if conversation.blank?

        {
          status: conversation.status,
          assigned_to_human: conversation.assignee_id.present?,
          last_human_agent_at: last_human_agent_at&.iso8601
        }
      end

      # A conversa "corrente" do card quando há várias: a de atividade mais recente.
      def latest_conversation
        @latest_conversation ||= Conversation.where(id: conversation_ids).reorder(last_activity_at: :desc).first
      end

      def last_human_agent_at
        Message.where(conversation_id: conversation_ids, sender_type: 'User')
               .where.not(message_type: :activity)
               .reorder(id: :desc)
               .limit(1)
               .pick(:created_at)
      end

      # Âncora temporal para a IA resolver datas relativas ("amanhã", "terça que vem") em data real.
      # Fuso resolvido como nos follow-ups (contato → account.reporting_timezone → UTC).
      def temporal_context
        tz = Config.resolved_timezone(account: @card.account, contact: @card.try(:contact))
        now_local = Time.current.in_time_zone(tz)
        {
          timezone: tz,
          now_local: now_local.strftime('%Y-%m-%dT%H:%M'),
          weekday: now_local.strftime('%A'),
          default_hour: Config::CALLBACK_DEFAULT_HOUR
        }
      end

      def ai_metadata
        (@card.metadata || {}).fetch('ai', {}).to_h
      end

      # TODAS as conversas do card (primária + vinculadas), não só a primária: um card pode acumular
      # conversas e o score/estágio precisa ler o histórico inteiro, não um pedaço dele.
      # Janela POR CONVERSA, não global: com um único LIMIT, uma conversa movimentada consumia a cota
      # inteira e a vinculada — que pode conter a promessa não cumprida — não chegava ao modelo.
      def recent_messages
        ids = conversation_ids
        return [] if ids.empty?

        ids.flat_map { |conversation_id| latest_for(conversation_id) }
           .sort_by(&:id)
           .last(MAX_MESSAGES_CAP)
           .map { |message| format_message(message) }
      end

      # reorder (not order) to override Message's default_scope(created_at: :asc), and by id (arrival
      # order) so just-arrived messages/media are always in the recent window even if provider
      # timestamps are skewed/out-of-order. includes(:attachments) evita N+1 no message_content.
      def latest_for(conversation_id)
        Message.where(conversation_id: conversation_id, private: false)
               .where.not(message_type: :activity)
               .includes(:attachments)
               .reorder(id: :desc)
               .limit(MAX_RECENT_MESSAGES)
      end

      def conversation_ids
        @conversation_ids ||= ([@card.conversation_id] + @card.card_conversations.pluck(:conversation_id)).compact.uniq
      end

      # Janela cresce com o número de conversas para um card com várias não perder o começo de cada
      # uma, mas com teto para não estourar o prompt.
      def window_size(conversation_count)
        [MAX_RECENT_MESSAGES * conversation_count, MAX_MESSAGES_CAP].min
      end

      def format_message(message)
        payload = {
          role: role_for(message),
          content: message_content(message).truncate(2000),
          created_at: message.created_at.iso8601
        }
        # Só desambigua a origem quando há mais de uma conversa; senão é ruído no prompt.
        payload[:conversation_id] = message.conversation_id if conversation_ids.size > 1
        payload
      end

      # Quatro papéis, não dois. "Cliente cobrou e só o bot respondeu" é urgente; "humano respondeu
      # há 5 minutos" não é — e com role='agent' para todo mundo a IA não conseguia distinguir.
      def role_for(message)
        return 'customer' if message.incoming?
        # O follow-up automático é entregue em nome do humano responsável (MessageSender usa
        # created_by/assignee), então sem esta checagem a própria IA reaparece no transcript como
        # "pessoa do time" e o cérebro conclui que houve pergunta humana sem resposta — foi o que
        # fez a IA cobrar o mesmo cliente duas vezes pelo mesmo questionário.
        # Continua sendo platform_agent, e não um quinto papel, porque o enum last_turn_owner do
        # ScoreCalculator conhece só quatro.
        return 'platform_agent' if message.content_attributes.to_h['crm_follow_up_id'].present?

        case message.sender_type
        when 'User' then 'human_agent'
        when 'AgentBot' then platform_bot_ids.include?(message.sender_id) ? 'platform_agent' : 'external_agent'
        # Saída sem sender (automação, API) cai em external_agent e não num quinto papel: o enum de
        # last_turn_owner só conhece quatro, e um valor fora dele fazia o modelo adivinhar.
        else 'external_agent'
        end
      end

      # Bot da plataforma = AgentBot criado por um agente Autonom.ia (Operate::Responder posta com
      # sender_id = agent_inbox.agent_bot_id). Qualquer outro AgentBot é integração externa.
      def platform_bot_ids
        @platform_bot_ids ||= Autonomia::Agents::AgentInbox.where(account_id: @card.account_id).pluck(:agent_bot_id).compact.to_set
      end

      # Combines the text body with text extracted from media attachments
      # (audio transcription, image caption) and presence markers for media we
      # don't process (video, document).
      def message_content(message)
        parts = []
        text = message.content.to_s.strip
        parts << text if text.present?
        message.attachments.each { |attachment| parts << media_fragment(attachment) }
        parts.compact_blank.join("\n").presence || '[mensagem sem texto]'
      end

      def media_fragment(attachment)
        meta = attachment.meta.to_h
        case attachment.file_type.to_s
        when 'audio'
          transcript = meta['transcribed_text'].to_s.strip
          transcript.present? ? "[áudio transcrito]: #{transcript.truncate(Config::TRANSCRIPT_MAX_CHARS)}" : '[áudio recebido, não transcrito]'
        when 'image'
          caption = meta['ai_caption'].to_s.strip
          caption.present? ? "[imagem]: #{caption.truncate(Config::CAPTION_MAX_CHARS)}" : '[imagem recebida]'
        when 'video'
          '[vídeo recebido]'
        when 'file'
          '[documento recebido]'
        end
      end
    end
  end
end
