module Crm
  module Cards
    class Creator
      ATTRIBUTES = %i[
        pipeline_id stage_id contact_id conversation_id inbox_id owner_id team_id title description
        value_cents currency status lost_reason source priority score expected_close_at metadata external_id custom_attributes
      ].freeze

      # etapa_escolhida (#1918): a etapa em que o card nasce veio da pessoa (o formulário do quadro, que mostra a etapa, ou
      # a etapa no pedido da API, ou a da prospecção). Fica na linha do tempo, e a IA não mexe na etapa dele por um tempo
      # (Crm::Ai::Evaluator::RESPEITO_AO_MOVIMENTO). A etapa que o sistema põe sozinho (a padrão da caixa, a primeira do
      # funil ao aceitar a sugestão de assunto) não é escolha.
      def initialize(account:, user:, params:, conversation: nil, etapa_escolhida: false)
        @account = account
        @user = user
        @params = params.to_h.with_indifferent_access
        @conversation = conversation
        @etapa_escolhida = etapa_escolhida && user.present?
      end

      def perform
        ActiveRecord::Base.transaction do
          card = @account.crm_cards.new(card_attributes)
          hydrate_from_conversation(card) if @conversation.present?
          card.owner ||= default_owner(card)
          card.status = Crm::Cards::Outcome.status_for(card.pipeline, card.status)
          card.save!
          link_primary_conversation(card) if card.conversation_id.present?
          Crm::ActivityLogger.new(card: card, actor: @user, event_type: 'create', payload: activity_payload(card)).perform
          card
        end
      end

      private

      def card_attributes
        @params.slice(*ATTRIBUTES).compact_blank
      end

      def hydrate_from_conversation(card)
        card.primary_conversation = @conversation
        card.contact = @conversation.contact
        card.inbox = @conversation.inbox
        card.owner = conversation_owner(card)
        card.team = @conversation.team
        card.source = @conversation.inbox&.channel_type
        card.title = derived_title if card.title.blank?
        card.last_message_at ||= Crm::Conversations::LastRealMessageAt.for(@conversation)
        card.last_activity_at ||= @conversation.last_activity_at
        card.metadata = conversation_metadata(card)
      end

      def derived_title
        @params[:title].presence ||
          @conversation.contact&.name.presence ||
          @conversation.contact&.phone_number.presence ||
          "Conversa ##{@conversation.display_id}"
      end

      def conversation_metadata(card)
        (card.metadata || {}).merge(
          'source_conversation' => {
            'display_id' => @conversation.display_id,
            'status' => @conversation.status,
            'inbox_id' => @conversation.inbox_id,
            'assignee_id' => @conversation.assignee_id,
            'team_id' => @conversation.team_id
          }
        )
      end

      # Acesso por funil (#1148, decisão a): o atendente só vira dono se pode ter o card (ver CardGuard#assignee_can_own?);
      # senão o dono cai em quem cria.
      def conversation_owner(card)
        assignee = @conversation.assignee
        return if assignee.nil?

        guard = Crm::Access::CardGuard.new(user: @user, account: @account)
        assignee if guard.assignee_can_own?(assignee.id, inbox_id: @conversation.inbox_id, pipeline_id: card.pipeline_id)
      end

      def default_owner(card)
        return nil if @user.blank?
        return @user if card.owner_id.blank?

        card.owner
      end

      def link_primary_conversation(card)
        # Card criado pelo sistema não tira o assunto que uma pessoa acabou de escolher (#1260): nasce sem foco.
        sem_foco = @user.blank? && Crm::Cards::Focus.pessoa_escolheu?(account_id: @account.id, conversation_id: card.conversation_id)
        Crm::CardConversation.find_or_create_by!(
          account: @account,
          card: card,
          conversation_id: card.conversation_id
        ) do |link|
          link.is_primary = true
          link.linked_by = @user
          # Card novo vira o assunto atual da conversa (#1142): com outro card já aberto nela, é deste que se trata agora.
          link.focused_at = Time.current unless sem_foco
          link.focused_by_id = @user&.id
        end
      end

      def activity_payload(card)
        {
          pipeline_id: card.pipeline_id,
          stage_id: card.stage_id,
          contact_id: card.contact_id,
          conversation_id: card.conversation_id,
          inbox_id: card.inbox_id,
          owner_id: card.owner_id,
          etapa_escolhida: (true if @etapa_escolhida)
        }.compact
      end
    end
  end
end
