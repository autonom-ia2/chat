class Crm::Conversations::CardSyncer
  AUTO_SYNC_METADATA = 'crm_auto_sync'.freeze
  OBSERVER_SOURCE = 'conversation_observer'.freeze

  def initialize(conversation:, message: nil)
    @conversation = conversation
    @message = message
    @account = conversation&.account
    @dedup_match_reason = nil
    @dedup_window_days = nil
  end

  def perform
    return unless Crm::Config.enabled?
    return unless load_conversation
    return if @conversation.inbox_id.blank?
    # #2395: a conversa do conector do WhatsApp (avisos de QR e de vínculo) não é de cliente: nem cria, nem liga card.
    return if Waha::IntegracaoDoConector.da_integracao?(@conversation)

    # Cliente com card aberto que escreve por outra caixa (#1150, R13): liga ao card antes de pensar em criar outro.
    Crm::Conversations::OutroCanal.new(conversation: @conversation, message: @message).perform

    pipeline_inbox = auto_create_pipeline_inbox
    return refresh_existing_card if pipeline_inbox.blank?

    sync_card(pipeline_inbox)
  end

  private

  def load_conversation
    @conversation = Conversation.find_by(id: @conversation&.id)
    @account = @conversation&.account
    @conversation.present? && @account.present?
  end

  def sync_card(pipeline_inbox)
    card = nil
    event_name = nil

    Crm::Conversations::SyncLock.new(account: @account, conversation: @conversation).perform do
      card = existing_card(pipeline_inbox)
      if card.present?
        event_name = refresh_card(card) ? Events::Types::CRM_CARD_UPDATED : nil
        log_dedup_reuse(card)
      else
        card = create_card(pipeline_inbox)
        event_name = Events::Types::CRM_CARD_CREATED if card.present?
      end
    end

    Crm::Cards::Broadcaster.broadcast(card, event_name) if card.present? && event_name.present?
    maybe_stop_ai_followup(card) if card.present?
    schedule_ai_evaluation(card) if card.present? && (!foco_depois_do_assunto? || event_name == Events::Types::CRM_CARD_CREATED)
    card
  end

  # #1675: com a flag `crm_avaliar_toda_mensagem` e a IA de assunto ligada na caixa (também a de 1 funil com card ao
  # chegar), a mensagem do cliente espera a decisão do assunto: o card que a deduplicação devolve aqui é o foco de ANTES
  # da mensagem, e pode não ser o assunto dela. Quem agenda a IA e conta a atividade é o Crm::Subjects::IdentifyJob, no
  # card em foco depois da decisão (Crm::Conversations::CardEmFoco). O resto da sincronização (dono, time, caixa) segue.
  # Card que nasce aqui já é o foco e é avaliado como sempre: a decisão pode ter rodado antes dele existir (fila high), e
  # se rodar depois, o Observer#agendada_desde? não agenda de novo.
  def foco_depois_do_assunto?
    return @foco_depois_do_assunto if defined?(@foco_depois_do_assunto)

    @foco_depois_do_assunto = @message.present? && @message.incoming? &&
                              Crm::Conversations::CardEmFoco.ligada?(@account) && Crm::Subjects.ligado?(@conversation)
  end

  # Auto-stop the AI follow-up cadence when the contact replies. Guarded internally
  # (acts only on an inbound message with an active ai_followup cadence); never
  # touches manual follow-ups or the sync/AI-evaluation flow above.
  # Sem criação automática na caixa, o card que outra via criou (automação, Kanban) continua acompanhando a própria
  # conversa: sem isto a troca de responsável nunca chegava a ele. Só o card principal da conversa, e sem marcá-lo como
  # automático, então um dono escolhido à mão segue intocado.
  # Só responsável e time (sincronização sem mensagem): a mensagem não avança a atividade desse card — senão o
  # StaleCardsJob voltaria a avaliá-lo com IA a cada período parado — nem abre lock em caixa que não tem card.
  # Com a flag `crm_avaliar_toda_mensagem` (#1675), a mensagem do cliente conta no card em foco e a IA o avalia
  # (Crm::Conversations::CardEmFoco), o que tira o motivo acima. Com a IA de assunto ligada na caixa, quem faz isso é o
  # Crm::Subjects::IdentifyJob, depois de decidir o assunto: aqui o foco ainda é o de antes da mensagem.
  def refresh_existing_card
    return mensagem_no_card_em_foco if @message.present?

    refresh_card_without_message
  end

  # A mensagem da pessoa da equipe também (#1923); quem decide o que conta é o CardEmFoco.
  def mensagem_no_card_em_foco
    return unless Crm::Conversations::CardEmFoco.ligada?(@account)
    return if foco_depois_do_assunto?

    Crm::Conversations::CardEmFoco.new(conversation: @conversation, message: @message).perform
  end

  def refresh_card_without_message
    return if inbox_crm_disabled?
    return if primary_conversation_card.blank?

    card = nil
    updated = false
    Crm::Conversations::SyncLock.new(account: @account, conversation: @conversation).perform do
      card = primary_conversation_card
      updated = card.present? && refresh_card(card, auto_sync: false)
    end

    Crm::Cards::Broadcaster.broadcast(card, Events::Types::CRM_CARD_UPDATED) if updated
    card
  end

  def primary_conversation_card
    card = Crm::Cards::ConversationCardFinder.new(account: @account).find(@conversation)
    card if card&.conversation_id == @conversation.id
  end

  def inbox_crm_disabled?
    setting = @account.crm_inbox_settings.find_by(inbox_id: @conversation.inbox_id)
    setting.present? && !setting.crm_enabled?
  end

  # Na ordem do turno, quem para a cadência é o Crm::Subjects::IdentifyJob, depois de decidir o assunto (#1606, corrida
  # f): aqui o foco ainda é o de antes da mensagem. Fora dela (inclusive com a IA de assunto ligada, mas sem a Fase 2 ou
  # sem área), para na hora, como sempre foi.
  def maybe_stop_ai_followup(card)
    return if @message&.incoming? && Crm::Subjects.ordem_do_turno?(@conversation)

    Crm::FollowUps::AutoFollowupCanceler.new(card: card, message: @message).maybe_cancel
  end

  def schedule_ai_evaluation(card)
    Crm::Ai::EnrichCardMediaJob.perform_later(card.id) if Crm::Ai::Config.media_enabled?
    Crm::Ai::Observer.new(card: card).schedule_evaluation
  end

  def auto_create_pipeline_inbox
    setting = @account.crm_inbox_settings.find_by(inbox_id: @conversation.inbox_id)
    return if inbox_auto_create_disabled?(setting)

    scope = @account.crm_pipeline_inboxes
                    .includes(:pipeline, :default_stage)
                    .joins(:pipeline)
                    .where(inbox_id: @conversation.inbox_id, auto_create_card: true)
                    .merge(Crm::Pipeline.active)
                    .order('crm_pipelines.position ASC, crm_pipeline_inboxes.id ASC')

    preferred_pipeline_inbox(scope, setting) || scope.first
  end

  def inbox_auto_create_disabled?(setting)
    setting.present? && (!setting.crm_enabled? || !setting.auto_create_card?)
  end

  def preferred_pipeline_inbox(scope, setting)
    return if setting&.default_pipeline_id.blank?

    scope.find_by(pipeline_id: setting.default_pipeline_id)
  end

  def existing_card(pipeline_inbox)
    @dedup_match_reason = nil
    result = Crm::Conversations::AutoCreateDeduplicator.new(
      account: @account,
      conversation: @conversation,
      pipeline_inbox: pipeline_inbox
    ).perform(@account.crm_cards.open)
    @dedup_match_reason = result.reason
    @dedup_window_days = result.window_days
    result.card
  end

  # #2084: contato fora do funil (parceiro, não é negócio) não ganha card sozinho. A reutilização do card aberto que já
  # existe (o feito à mão, o de outra caixa) continua: ele segue a conversa.
  def create_card(pipeline_inbox)
    return unless cria_card_sozinho?

    stage = default_stage_for(pipeline_inbox)
    return if stage.blank?

    Crm::Cards::Creator.new(
      account: @account,
      user: nil,
      conversation: @conversation,
      params: {
        pipeline_id: pipeline_inbox.pipeline_id,
        stage_id: stage.id,
        metadata: auto_sync_metadata
      }
    ).perform
  end

  # #2395: a conversa cujo card a IA arquivou como "não é negócio" não recria card por mensagem nenhuma (do cliente, da
  # equipe ou do robô): espera a IA de assunto decidir um pedido novo, ou uma pessoa.
  def cria_card_sozinho?
    return false if Crm::Relacao.fora_do_funil?(@conversation.contact)

    !Crm::Ai::NaoENegocio.conversa_fora_do_negocio?(@conversation)
  end

  def refresh_card(card, auto_sync: true)
    attributes = refresh_attributes(card, auto_sync)
    return false if attributes.blank?

    card.update!(attributes)
    ensure_conversation_link(card)
    log_refresh(card, attributes)
    true
  end

  def refresh_attributes(card, auto_sync)
    attributes = { contact_id: @conversation.contact_id, **caixa_attributes(card), metadata: refreshed_metadata(card, auto_sync) }.compact

    merge_activity_attributes(attributes)
    attributes[:conversation_id] = @conversation.id if card.conversation_id.blank?
    attributes[:owner_id] = @conversation.assignee_id if sync_assignment?(card) && assignee_can_own?(card)
    attributes[:team_id] = @conversation.team_id if sync_team?(card)
    attributes.reject { |key, value| values_equal?(card.public_send(key), value) }
  end

  # A caixa (e o canal) do card é a da conversa principal dele. Uma conversa de outra caixa ligada ao card (outro canal,
  # R13 do #1150, ou vínculo à mão) não o arrasta para a caixa dela: a caixa do card decide quem o vê no Kanban, e ele
  # pularia de caixa a cada mensagem de um canal ou do outro. Card sem principal adota a caixa de quem o adota.
  # Junto com a R13, atrás da flag `crm_outro_canal` (#1666): sem ela, a caixa do card segue a última conversa sincronizada.
  def caixa_attributes(card)
    da_caixa = card.conversation_id.blank? || own_conversation?(card)
    return {} unless da_caixa || !@account.feature_enabled?(Crm::Conversations::OutroCanal::FLAG)

    { inbox_id: @conversation.inbox_id, source: @conversation.inbox&.channel_type }
  end

  # Acesso por funil (#1148, decisão a): o atendente só vira dono se tiver o funil do card; senão o dono fica como está.
  # Desatribuir (sem atendente) segue zerando o dono, como antes.
  def assignee_can_own?(card)
    return true if @conversation.assignee_id == card.owner_id

    Crm::Access::CardGuard.new(user: nil, account: @account)
                          .assignee_can_own?(@conversation.assignee_id, inbox_id: @conversation.inbox_id, pipeline_id: card.pipeline_id)
  end

  # Assignment/team syncs arrive without @message; they must not move the card's
  # activity clock — stage moves and linkers legitimately set last_activity_at to
  # Time.current, and a stale real-message date would regress it.
  def merge_activity_attributes(attributes)
    return if @message.blank? || foco_depois_do_assunto?

    real_message_at = last_message_at
    return if real_message_at.blank?

    attributes[:last_message_at] = real_message_at
    attributes[:last_activity_at] = real_message_at
  end

  # Auto-synced cards mirror the assignee of THEIR OWN (primary) conversation exactly (set on assign,
  # clear on unassign) so owner stays a clean human field and reflects realtime.
  # Manually-owned cards, and cards reused or adopted by another conversation of the contact (#1273: a
  # new conversation not yet distributed must not wipe the owner), are only filled when blank.
  def sync_assignment?(card)
    return true if auto_synced_card?(card) && own_conversation?(card)

    @conversation.assignee_id.present? && card.owner_id.blank?
  end

  # Same rule for the team: only the card's own conversation overwrites it.
  def sync_team?(card)
    return false if @conversation.team_id.blank?

    (auto_synced_card?(card) && own_conversation?(card)) || card.team_id.blank?
  end

  # Read before conversation_id is filled on adoption: a card without a primary conversation is not
  # "own" yet, so adopting it only fills blanks.
  def own_conversation?(card)
    card.conversation_id == @conversation.id
  end

  def values_equal?(current_value, next_value)
    current_value == next_value
  end

  def default_stage_for(pipeline_inbox)
    pipeline_inbox.default_stage || pipeline_inbox.pipeline.stages.order(:position, :id).first
  end

  def last_message_at
    Crm::Conversations::LastRealMessageAt.for(@conversation)
  end

  def auto_sync_metadata
    {
      AUTO_SYNC_METADATA => {
        'source' => OBSERVER_SOURCE,
        'message_id' => @message&.id,
        'synced_at' => Time.current.iso8601
      }
    }
  end

  def refreshed_metadata(card, auto_sync)
    metadata = card.metadata || {}
    metadata = metadata.deep_merge(auto_sync_metadata) if auto_sync
    metadata.deep_merge(
      'source_conversation' => {
        'display_id' => @conversation.display_id,
        'status' => @conversation.status,
        'inbox_id' => @conversation.inbox_id,
        'assignee_id' => @conversation.assignee_id,
        'team_id' => @conversation.team_id
      }
    )
  end

  def auto_synced_card?(card)
    card.metadata.to_h.dig(AUTO_SYNC_METADATA, 'source') == OBSERVER_SOURCE
  end

  def log_refresh(card, attributes)
    audited_attributes = attributes.except(:last_message_at, :last_activity_at, :metadata)
    return if audited_attributes.blank?

    Crm::ActivityLogger.new(
      card: card,
      actor: nil,
      event_type: 'conversation_sync',
      conversation: @conversation,
      payload: audited_attributes
    ).perform
  end

  def log_dedup_reuse(card)
    return if @dedup_match_reason.blank?

    Crm::Conversations::DedupReuseLogger.new(
      card: card,
      conversation: @conversation,
      reason: @dedup_match_reason,
      window_days: @dedup_window_days
    ).perform
  end

  def ensure_conversation_link(card)
    Crm::CardConversation.find_or_create_by!(
      account: @account,
      card: card,
      conversation: @conversation
    ) do |link|
      link.is_primary = card.conversation_id == @conversation.id
    end
  end
end
