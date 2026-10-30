module Crm
  module Ai
    class ContextBuilder # rubocop:disable Metrics/ClassLength -- já passava do teto com a main + #1761 (177)
      MAX_RECENT_MESSAGES = 12
      MAX_MESSAGES_CAP = 40
      MAX_OTHER_SUBJECTS = 5
      # Quantas mensagens recentes olhar para trás procurando a última fala humana que NÃO seja um
      # toque da própria IA. Ver #last_human_agent_at.
      FOLLOW_UP_SCAN_LIMIT = 20

      # Cópia que a EQUIPE encaminhou de outra conversa (#1702: forwarded = true + forwarded_from) traz texto de outra
      # pessoa: sem a marca, a IA lia como fala deste cliente (#1760). O que o CLIENTE encaminha pelo WhatsApp (forwarded
      # sem forwarded_from) é parte do pedido dele e fica sem marca.
      FORWARDED_PREFIX = '[Encaminhada de outra conversa — não é fala deste cliente] '.freeze

      # A legenda dos papéis mora junto de quem os produz (#role_for). Todo prompt que lê
      # recent_messages descreve os papéis a partir daqui: foi a cópia divergente que fez o
      # follow-up receber "human_agent" e ler uma instrução que só falava de "customer" e "agent".
      ROLES_LEGEND = 'Cada mensagem tem um "role": "customer" (o cliente), "human_agent" (uma pessoa do time), ' \
                     '"platform_agent" (agente de IA da plataforma, incluindo os follow-ups automáticos anteriores) ' \
                     'ou "external_agent" (bot ou automação externa).'.freeze

      # Separada da ROLES_LEGEND para entrar no FIM do prefixo do classificador (cache de prompt, ClassifierPrompt).
      FORWARDED_LEGEND = 'Mensagem com "forwarded": true foi ENCAMINHADA pela equipe de outra conversa e começa com ' \
                         "\"#{FORWARDED_PREFIX.strip}\": o texto é de outra pessoa. Não conte como fala, pedido " \
                         'ou dado deste cliente, nem como sinal de etapa, valor ou campo dele.'.freeze

      # fora (#1693): outros cards que também vão na mesma avaliação (Crm::Ai::AvaliacaoConjunta); saem de other_subjects.
      # memoria (#1601): só a avaliação de card com a flag `memoria_ia` pede; cada mensagem ganha um id LOCAL ("ref": m1,
      # m2...) e o contexto traz os fatos já registrados (Crm::Memoria::ParaAvaliacao). Os outros leitores não mudam.
      # pedido_anterior (#1925): só a avaliação de card pede; traz o card encerrado que este pode estar retomando.
      # #1926 (MITIGAÇÃO; o fix definitivo, o fato persistido, é o #1966): a avaliação de etapa decide pela conversa, e o
      # resumo (metadata.ai.summary) só existe quando alguém abre o card. Com 12 mensagens, o preço enviado no meio de uma
      # conversa longa ficava de fora e o card não saía de "Em atendimento". Ela lê o teto inteiro, dividido em partes
      # iguais entre as conversas: a movimentada não toma a vez da vinculada, e a soma nunca passa do teto (com 4 ou
      # mais conversas, cada uma fica com menos de MAX_RECENT_MESSAGES, mas nenhuma some).
      def self.janela_da_avaliacao(conversas)
        [MAX_MESSAGES_CAP / [conversas, 1].max, 1].max
      end

      # janela (#1926): :avaliacao é a avaliação de etapa (Crm::Ai::Evaluator), que lê até MAX_MESSAGES_CAP mensagens
      # (#janela_por_conversa). Os outros leitores seguem com MAX_RECENT_MESSAGES por conversa.
      def initialize(card:, fora: [], memoria: false, janela: :curta, pedido_anterior: false)
        @card = card
        @fora = fora
        @numeracao = Crm::Memoria::ParaAvaliacao::Numeracao.new if memoria
        @janela = janela
        @pedido_anterior = pedido_anterior
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
          temporal: temporal_context,
          other_subjects: other_subjects
        }.merge(memoria_payload).merge(pedido_anterior_payload)
      end

      private

      # Card que renasce (#1925): o pedido encerrado sem sucesso antes deste, com as últimas mensagens da vida dele
      # (Crm::Ai::PedidoAnterior). Sem ids locais da memória: nada dali é prova de fato deste card.
      def pedido_anterior_payload
        anterior = @pedido_anterior && Crm::Ai::PedidoAnterior.do_card(@card)
        return {} unless anterior

        mensagens = Crm::Ai::PedidoAnterior.mensagens(anterior, fora: recent_records.map(&:id))
        { previous_card: Crm::Ai::PedidoAnterior.payload(anterior).merge(messages: mensagens.map { |m| format_message(m, numerar: false) }) }
      end

      def memoria_payload
        @numeracao ? Crm::Memoria::ParaAvaliacao.contexto(@card, conversation_ids, @numeracao) : {}
      end

      # Os outros pedidos abertos nas conversas deste card (multifunil, #1147). A IA decide a etapa, os campos e o
      # follow-up só DESTE card: uma mensagem sobre outro pedido não o move. Vazio quando a conversa tem um pedido só.
      # Com a flag `crm_ia_arquiva_lixo` (#1922), cada um leva o id: é o que a IA aponta quando este card repete outro
      # (`nao_e_negocio.duplicado_de`). Sem ela, a entrada fica igual à de antes.
      def other_subjects
        account = @card.account
        com_id = Crm::Ai::NaoENegocio.ligada?(account)
        linked = Crm::CardConversation.where(account_id: account.id, conversation_id: conversation_ids).select(:card_id)
        account.crm_cards.open.where(conversation_id: conversation_ids).or(account.crm_cards.open.where(id: linked))
               .where.not(id: [@card.id, *@fora]).includes(:pipeline, :stage).order(id: :desc).limit(MAX_OTHER_SUBJECTS)
               .map { |card| outro_pedido(card, com_id) }
      end

      def outro_pedido(card, com_id)
        pedido = { title: card.title, pipeline: card.pipeline&.name, stage: card.stage&.name }
        com_id ? { id: card.id, **pedido } : pedido
      end

      # Valores JÁ salvos dos atributos customizados (contato, conversa e o próprio card, #1146). O classificador recebe o
      # SCHEMA (chaves permitidas) em attribute_schema; aqui vão os VALORES atuais, para ele decidir o
      # estágio ciente do que já se sabe e não re-extrair o que não mudou.
      def known_attributes
        {
          contact: attribute_values(@card.try(:contact)),
          conversation: attribute_values(@card.primary_conversation),
          card: attribute_values(@card)
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
          last_human_agent_at: last_human_agent_at&.iso8601,
          # Quando um humano devolveu a conversa à IA depois de uma passagem (DevolucaoAIa). O que foi dito antes
          # disso já foi atendido por gente e não pede humano de novo.
          returned_to_ai_at: DevolucaoAIa.em(@card, @card.conversa_em_atendimento)&.iso8601
        }.merge(handoff_history).merge(espera_do_cliente)
      end

      # IA entende a conversa F1 (flag `crm_ia_fatos_da_conversa`), só na avaliação de etapa: desde quando o cliente
      # espera resposta (Crm::Ai::FatosDaConversa). Sem a flag, a entrada fica igual à de antes.
      def espera_do_cliente
        return {} unless fatos_da_ordem?

        { customer_waiting_since: FatosDaConversa.cliente_espera_desde(recent_records.map { |m| [m.conversation_id, role_for(m), m.created_at] }) }
      end

      def fatos_da_ordem?
        return @fatos_da_ordem if defined?(@fatos_da_ordem)

        @fatos_da_ordem = @janela == :avaliacao && FatosDaConversa.ligada?(@card.account)
      end

      # As passagens recentes da conversa (#1606), em qualquer modo (convite, sem regra do funil, atribuição pela tela):
      # texto cercado como dado. Sem passagem, a entrada fica igual à de antes.
      # Vale para todas as contas, com ou sem a Fase 2 dos Agentes (correção do pingue-pongue). Só a conversa da conta do
      # card: account_id conferido aqui, como no #latest_conversation.
      def handoff_history
        conversa = @card.conversa_em_atendimento
        conversa = nil unless conversa&.account_id == @card.account_id
        texto = conversa ? Crm::Passagens.recentes(conversa) : ''
        texto.present? ? { handoff_history: texto } : {}
      end

      # A conversa "corrente" do card quando há várias: a de atividade mais recente.
      # account_id explícito nas duas queries abaixo: hoje só a validação de modelo impede um card de
      # apontar para conversa de outra conta, e validação de aplicação não é barreira suficiente para
      # vazamento entre clientes.
      def latest_conversation
        @latest_conversation ||= Conversation.where(id: conversation_ids, account_id: @card.account_id)
                                             .reorder(last_activity_at: :desc).first
      end

      # Mesmos filtros do #role_for e do #latest_for, e pelo mesmo motivo: o follow-up automático sai
      # com sender_type 'User', então sem excluí-lo cada toque da IA "renovava" o horário da última
      # fala humana e a conversa parecia estar sendo conduzida por uma pessoa. Nota privada também
      # fica de fora: ela nunca chega ao modelo em recent_messages, e contá-la aqui criaria um
      # contexto que se contradiz.
      #
      # O descarte é feito em RUBY, não em SQL. `content_attributes` é coluna json com
      # `store ... coder: JSON` no Message, então o Rails grava o hash como STRING JSON dentro do
      # json ("{\"crm_follow_up_id\":1}") e `content_attributes ->> 'chave'` devolve sempre NULL.
      # O filtro SQL que estava aqui não excluía nada — falha silenciosa, que é o pior tipo.
      # A varredura é limitada porque a cadência tem no máximo um punhado de toques seguidos.
      # #1601: os mesmos papéis do #role_for — o eco do celular conta como fala humana; o follow-up, o convite e o aviso
      # do Agendamento, não.
      def last_human_agent_at
        Message.where(conversation_id: conversation_ids, account_id: @card.account_id, private: false)
               .where(sender_type: 'User').or(Message.where(conversation_id: conversation_ids, account_id: @card.account_id,
                                                            private: false, sender_type: nil))
               .outgoing
               .where('messages.status IS DISTINCT FROM ?', Message.statuses[:failed])
               .reorder(id: :desc)
               .limit(FOLLOW_UP_SCAN_LIMIT)
               .find { |message| role_for(message) == 'human_agent' }
               &.created_at
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
      # Com a flag `crm_ia_fatos_da_conversa`, na avaliação de etapa, a mensagem do cliente leva `after` (quem falou antes).
      def recent_messages
        mensagens = recent_records.map { |message| format_message(message) }
        fatos_da_ordem? ? FatosDaConversa.com_ordem(mensagens) : mensagens
      end

      def recent_records
        @recent_records ||= conversation_ids.flat_map { |conversation_id| latest_for(conversation_id) }
                                            .sort_by(&:id)
                                            .last(MAX_MESSAGES_CAP)
      end

      # reorder (not order) to override Message's default_scope(created_at: :asc), and by id (arrival
      # order) so just-arrived messages/media are always in the recent window even if provider
      # timestamps are skewed/out-of-order. includes(:attachments) evita N+1 no message_content.
      # Envio que falhou (#1923) não chegou ao cliente: sai do histórico, como no dos Agentes (PessoaDaEquipe). A falha
      # chega depois da criação (message_updated), quando a avaliação já foi agendada; é aqui que ela deixa de contar.
      # IS DISTINCT FROM: a coluna aceita nulo, e `status != 3` descartaria a mensagem sem status.
      def latest_for(conversation_id)
        Message.where(conversation_id: conversation_id, private: false)
               .where.not(message_type: :activity)
               .where('messages.status IS DISTINCT FROM ?', Message.statuses[:failed])
               .includes(:attachments)
               .reorder(id: :desc)
               .limit(janela_por_conversa)
      end

      def conversation_ids
        @conversation_ids ||= ([@card.conversation_id] + @card.card_conversations.pluck(:conversation_id)).compact.uniq
      end

      def janela_por_conversa
        @janela == :avaliacao ? self.class.janela_da_avaliacao(conversation_ids.size) : MAX_RECENT_MESSAGES
      end

      # #1807 (flag `email_autoria`): e-mail de outro endereço que não o do cliente ganha o aviso na frente e
      # "email_autoria" (outra_pessoa, equipe, automatica); o papel continua `customer` (é a resposta da conversa).
      def format_message(message, numerar: true)
        forwarded = forwarded_by_team?(message)
        content, marca_do_email = email_autoria.marcar(message, message_content(message).truncate(2000))
        payload = {
          **(@numeracao && numerar ? @numeracao.ref_de(message) : {}),
          role: role_for(message),
          content: forwarded ? "#{FORWARDED_PREFIX}#{content}" : content,
          created_at: message.created_at.iso8601
        }
        payload[:forwarded] = true if forwarded
        payload.merge!(marca_do_email)
        # Só desambigua a origem quando há mais de uma conversa; senão é ruído no prompt.
        payload[:conversation_id] = message.conversation_id if conversation_ids.size > 1
        payload
      end

      def email_autoria = (@email_autoria ||= Crm::Email::Autoria.new(@card.account))

      def forwarded_by_team?(message)
        attributes = message.content_attributes.to_h
        attributes['forwarded'] == true && attributes['forwarded_from'].present?
      end

      # Quem falou: a regra mora no Crm::Ai::PapelDaMensagem (a mesma da IA de assunto, IA entende a conversa F1).
      def role_for(message)
        Crm::Ai::PapelDaMensagem.de(message, robos: method(:platform_bot_ids))
      end

      def platform_bot_ids
        @platform_bot_ids ||= Crm::Ai::PapelDaMensagem.robos_da_conta(@card.account_id)
      end

      # Combines the text body with text extracted from media attachments
      # (audio transcription, image caption) and presence markers for media we
      # don't process (video, document). O fragmento de cada anexo é o do Crm::Ai::TextoDaMidia; com a flag
      # `crm_ia_leitor_de_midia` (IA entende a conversa F4), o texto do PDF lido entra também.
      def message_content(message)
        parts = []
        # #1807: e-mail recebido sem o histórico citado (com a flag); o resto, o content de sempre.
        text = email_autoria.texto(message).strip
        parts << text if text.present?
        message.attachments.each { |attachment| parts << Crm::Ai::TextoDaMidia.fragmento(attachment, pdf: le_pdf?) }
        parts.compact_blank.join("\n").presence || '[mensagem sem texto]'
      end

      def le_pdf?
        @le_pdf = Crm::Ai::LeitorDeMidia.ligada?(@card.account) unless defined?(@le_pdf)
        @le_pdf
      end
    end
  end
end
